import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import '../config/supabase_config.dart';
import '../models/app_data.dart';
import 'cloud_store.dart';

class WalletResult {
  const WalletResult({
    required this.ok,
    required this.message,
    this.code,
    this.value,
    this.queuedPasses = 0,
  });
  final bool ok;
  final String message;
  final String? code;
  final int? value;
  final int queuedPasses;
}

class WalletService {
  WalletService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;
  static const _channel = MethodChannel('app.fideli/wallet');
  static final Map<String, Future<WalletResult>> _inFlight = {};
  static final Map<String, Future<void>> _serialTails = {};

  Future<WalletResult> _runOnce(
    String key,
    Future<WalletResult> Function() request,
  ) async {
    final running = _inFlight[key];
    if (running != null) return running;
    final operation = request();
    _inFlight[key] = operation;
    try {
      return await operation;
    } finally {
      if (identical(_inFlight[key], operation)) _inFlight.remove(key);
    }
  }

  Future<WalletResult> _runSerial(
    String key,
    Future<WalletResult> Function() request,
  ) {
    final completer = Completer<WalletResult>();
    final previous = _serialTails[key] ?? Future<void>.value();
    late final Future<void> current;
    current = previous
        .catchError((_) {})
        .then((_) async {
          try {
            completer.complete(await request());
          } catch (error, stackTrace) {
            completer.completeError(error, stackTrace);
          }
        })
        .whenComplete(() {
          if (identical(_serialTails[key], current)) {
            _serialTails.remove(key);
          }
        });
    _serialTails[key] = current;
    return completer.future;
  }

  String _base(BusinessProfile business) {
    final value = SupabaseConfig.configured
        ? SupabaseConfig.walletFunctionUrl
        : business.backendUrl.trim();
    return value.replaceFirst(RegExp(r'/$'), '');
  }

  Future<WalletResult> checkBackend(BusinessProfile business) async {
    try {
      final response = await _client
          .get(Uri.parse('${_base(business)}/health'))
          .timeout(const Duration(seconds: 4));
      if (response.statusCode == 200) {
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        return WalletResult(
          ok: true,
          message: body['mode'] == 'real'
              ? 'Servicio conectado'
              : 'Servicio de prueba conectado',
        );
      }
      return WalletResult(ok: false, message: 'El servicio no está disponible');
    } catch (_) {
      return const WalletResult(
        ok: false,
        message: 'No se pudo conectar. Revisa tu conexión.',
      );
    }
  }

  Future<WalletResult> addApplePass(
    BusinessProfile business,
    Customer customer,
  ) async {
    if (!Platform.isIOS) {
      return const WalletResult(
        ok: false,
        message: 'Apple Wallet solo se instala desde un dispositivo iOS.',
      );
    }
    try {
      final uri = _customerUri(business, customer, 'apple');
      final response = await _client.get(uri);
      final contentType = response.headers['content-type'] ?? '';
      if (response.statusCode == 200 &&
          contentType.contains('application/vnd.apple.pkpass')) {
        final installed =
            await _channel.invokeMethod<bool>('addPass', {
              'base64': base64Encode(response.bodyBytes),
            }) ??
            false;
        return WalletResult(
          ok: installed,
          message: installed
              ? 'Pase enviado a Apple Wallet'
              : 'Se canceló la instalación',
        );
      }
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      return WalletResult(
        ok: false,
        message: body['message'] as String? ?? 'El pase no está disponible',
      );
    } catch (_) {
      return const WalletResult(
        ok: false,
        message: 'No se pudo crear el pase. Inténtalo nuevamente.',
      );
    }
  }

  Future<WalletResult> addGooglePass(
    BusinessProfile business,
    Customer customer, {
    LoyaltyProgram? program,
  }) async {
    try {
      final baseUri = _customerUri(business, customer, 'google');
      final uri = program == null
          ? baseUri
          : baseUri.replace(
              queryParameters: {...baseUri.queryParameters, 'card': program.id},
            );
      final response = await _client.get(uri);
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final url = body['saveUrl'] as String?;
      if (response.statusCode == 200 && url != null) {
        final opened = await launchUrl(
          Uri.parse(url),
          mode: LaunchMode.externalApplication,
        );
        return WalletResult(
          ok: opened,
          message: opened
              ? 'Abriendo Google Wallet'
              : 'No se pudo abrir Google Wallet',
        );
      }
      return WalletResult(
        ok: false,
        message: body['message'] as String? ?? 'El pase no está disponible',
      );
    } catch (_) {
      return const WalletResult(
        ok: false,
        message: 'No se pudo crear el pase. Inténtalo nuevamente.',
      );
    }
  }

  Uri appleEnrollmentUrl(
    BusinessProfile business,
    Customer customer, {
    LoyaltyProgram? program,
  }) {
    final uri = _customerUri(business, customer, 'apple');
    return program == null
        ? uri
        : uri.replace(
            queryParameters: {...uri.queryParameters, 'card': program.id},
          );
  }

  Future<WalletResult> syncCustomer(
    BusinessProfile business,
    Customer customer, {
    bool recordActivity = false,
    String? programId,
    int? previousProgramValue,
  }) => _runSerial('customer:${customer.id}', () async {
    try {
      final response = await _client.post(
        Uri.parse('${_base(business)}/api/customers/${customer.id}'),
        headers: {
          'content-type': 'application/json',
          if (CloudStore.instance?.accessToken case final token?)
            'authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'id': customer.id,
          'name': customer.name,
          'phone': customer.phone,
          'email': customer.email,
          'birthDate': customer.birthDate?.toIso8601String().split('T').first,
          'points': customer.points,
          'stamps': customer.stamps,
          'visits': customer.visits,
          'tier': customer.tier,
          'referral': customer.referralCode,
          'cardBalances': customer.cardBalances.map(
            (key, value) => MapEntry(key, value.toJson()),
          ),
          'recordActivity': recordActivity,
          'programId': programId,
          'previousProgramValue': ?previousProgramValue,
          'business': business.name,
          'color': business.colorHex,
        }),
      );
      if (response.statusCode >= 200 && response.statusCode < 300) {
        Map<String, dynamic> body = const {};
        try {
          body = jsonDecode(response.body) as Map<String, dynamic>;
        } catch (_) {}
        final queuedPasses = body['queuedPasses'] as int? ?? 0;
        return WalletResult(
          ok: true,
          message: queuedPasses > 0
              ? 'Cambio guardado. Wallet se está actualizando'
              : 'Cambio guardado. Esta tarjeta todavía no está registrada para actualizaciones de Wallet',
        );
      }
      return WalletResult(
        ok: false,
        message: 'No se pudo sincronizar (${response.statusCode})',
      );
    } catch (_) {
      return const WalletResult(
        ok: false,
        message: 'Sin conexión con el servicio',
      );
    }
  });

  Future<WalletResult> setCardBalance(
    BusinessProfile business,
    Customer customer,
    LoyaltyProgram program, {
    required int value,
    required int previousValue,
  }) => _runSerial('customer:${customer.id}', () async {
    try {
      final response = await _client.post(
        Uri.parse(
          '${_base(business)}/api/customers/${customer.id}/card-balance',
        ),
        headers: {
          'content-type': 'application/json',
          if (CloudStore.instance?.accessToken case final token?)
            'authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'programId': program.id,
          'value': value,
          'previousValue': previousValue,
        }),
      );
      Map<String, dynamic> body = const {};
      try {
        body = jsonDecode(response.body) as Map<String, dynamic>;
      } catch (_) {}
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return WalletResult(
          ok: true,
          message: 'Saldo actualizado',
          value: (body['value'] as num?)?.toInt() ?? value,
          queuedPasses: (body['queuedPasses'] as num?)?.toInt() ?? 0,
        );
      }
      return WalletResult(
        ok: false,
        message:
            body['message'] as String? ??
            'No se pudo guardar el saldo (${response.statusCode})',
      );
    } catch (_) {
      return const WalletResult(
        ok: false,
        message: 'No se pudo guardar el saldo',
      );
    }
  });

  Future<WalletResult> refreshBusinessPasses(
    BusinessProfile business,
  ) => _runOnce('business-passes', () async {
    try {
      final response = await _client.post(
        Uri.parse('${_base(business)}/api/business/refresh-passes'),
        headers: _merchantHeaders,
        body: jsonEncode({
          'name': business.name,
          'walletIconPath': business.walletIconPath,
          'walletLogoPath': business.walletLogoPath,
        }),
      );
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode >= 200 && response.statusCode < 300) {
        final passes = body['affectedPasses'] as int? ?? 0;
        final queuedPasses = body['queuedPasses'] as int? ?? 0;
        return WalletResult(
          ok: true,
          message:
              'Icono guardado. $passes tarjeta(s) actualizadas; $queuedPasses actualización(es) en curso.',
        );
      }
      return WalletResult(
        ok: false,
        message: body['message'] as String? ?? 'No se pudo actualizar Wallet',
      );
    } catch (_) {
      return const WalletResult(
        ok: false,
        message: 'Icono guardado. Wallet se actualizará después.',
      );
    }
  });

  Future<WalletResult> sendCampaign(
    BusinessProfile business, {
    required String requestId,
    String campaignId = '',
    String campaignName = '',
    String notificationTitle = '',
    required String message,
    required String audience,
    String? targetCustomerId,
    String? linkUrl,
  }) => _runOnce('campaign:$requestId', () async {
    try {
      final response = await _client.post(
        Uri.parse('${_base(business)}/api/campaigns/send'),
        headers: {
          'content-type': 'application/json',
          if (CloudStore.instance?.accessToken case final token?)
            'authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'requestId': requestId,
          'campaignId': campaignId,
          'campaignName': campaignName,
          'notificationTitle': notificationTitle,
          'message': message,
          'audience': audience,
          if (targetCustomerId != null && targetCustomerId.isNotEmpty)
            'targetCustomerId': targetCustomerId,
          if (linkUrl != null && linkUrl.isNotEmpty) 'linkUrl': linkUrl,
        }),
      );
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode >= 200 && response.statusCode < 300) {
        final customers = body['targetedCustomers'] as int? ?? 0;
        final queuedPasses = body['queuedPasses'] as int? ?? 0;
        return WalletResult(
          ok: true,
          message: customers == 0
              ? 'No hay clientes en ese público'
              : 'Campaña enviada a $customers cliente(s). $queuedPasses Wallet(s) se están actualizando.',
        );
      }
      return WalletResult(
        ok: false,
        message: body['message'] as String? ?? 'No se pudo enviar la campaña',
      );
    } catch (_) {
      return const WalletResult(
        ok: false,
        message: 'No se pudo enviar la campaña',
      );
    }
  });

  Future<WalletResult> saveCampaign(
    BusinessProfile business,
    Campaign campaign,
  ) => _runSerial('save-campaign:${campaign.id}', () async {
    try {
      final response = await _client.post(
        Uri.parse('${_base(business)}/api/campaigns/save'),
        headers: _merchantHeaders,
        body: jsonEncode({...campaign.toJson(), 'campaignName': campaign.name}),
      );
      Map<String, dynamic> body = const {};
      try {
        body = jsonDecode(response.body) as Map<String, dynamic>;
      } catch (_) {}
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return const WalletResult(ok: true, message: 'Campaña guardada');
      }
      return WalletResult(
        ok: false,
        message:
            body['message'] as String? ??
            'No se pudo guardar la campaña (${response.statusCode})',
      );
    } catch (_) {
      return const WalletResult(
        ok: false,
        message: 'No se pudo guardar la campaña',
      );
    }
  });

  Future<WalletResult> redeemReward(
    BusinessProfile business, {
    required String customerId,
    required String rewardId,
  }) => _runOnce('reward:$customerId:$rewardId', () async {
    try {
      final response = await _client.post(
        Uri.parse('${_base(business)}/api/rewards/redeem'),
        headers: {
          'content-type': 'application/json',
          if (CloudStore.instance?.accessToken case final token?)
            'authorization': 'Bearer $token',
        },
        body: jsonEncode({'customerId': customerId, 'rewardId': rewardId}),
      );
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      return WalletResult(
        ok: response.statusCode >= 200 && response.statusCode < 300,
        code: body['code'] as String?,
        message:
            body['message'] as String? ??
            (response.statusCode == 409
                ? 'Esta recompensa ya fue cobrada'
                : 'No se pudo cobrar la recompensa'),
        queuedPasses: body['queuedPasses'] as int? ?? 0,
      );
    } catch (_) {
      return const WalletResult(
        ok: false,
        message: 'No se pudo cobrar la recompensa',
      );
    }
  });

  Future<WalletResult> syncProgram(
    BusinessProfile business,
    LoyaltyProgram program, {
    bool notifyWallet = true,
  }) => _runOnce('program:${program.id}', () async {
    try {
      final response = await _client.post(
        Uri.parse('${_base(business)}/api/cards/${program.id}'),
        headers: _merchantHeaders,
        body: jsonEncode({
          'name': program.name,
          'cardKind': program.cardKind,
          'programType': program.type.name,
          'earningRate': program.earningRate,
          'goal': program.goal,
          'active': program.active,
          'colorHex': program.colorHex,
          'backgroundImagePath': program.backgroundImagePath,
          'stampIcon': program.stampIcon,
          'walletLayout': program.walletLayout,
          'welcomeMessage': program.welcomeMessage,
          'stampNotificationMessage': program.stampNotificationMessage,
          'completionMessage': program.completionMessage,
          'rewardMilestones': program.stampMilestones
              .map((item) => item.toJson())
              .toList(),
          'expiresAt': program.expiresAt?.toUtc().toIso8601String(),
          'notifyWallet': notifyWallet,
        }),
      );
      Map<String, dynamic> body = const {};
      try {
        body = jsonDecode(response.body) as Map<String, dynamic>;
      } catch (_) {}
      if (response.statusCode >= 200 && response.statusCode < 300) {
        final passes = body['affectedPasses'] as int? ?? 0;
        final queuedPasses = body['queuedPasses'] as int? ?? 0;
        return WalletResult(
          ok: true,
          message: queuedPasses > 0
              ? 'Diseño guardado. $queuedPasses Wallet(s) se están actualizando'
              : passes > 0
              ? 'Diseño guardado. Las tarjetas se actualizarán al volver a conectarse con Wallet'
              : 'Diseño guardado. Todavía no hay tarjetas instaladas de este tipo',
        );
      }
      return WalletResult(
        ok: false,
        message:
            body['message'] as String? ??
            'No se pudo sincronizar (${response.statusCode})',
      );
    } catch (_) {
      return const WalletResult(
        ok: false,
        message: 'No se pudo sincronizar. Revisa tu conexión.',
      );
    }
  });

  Future<WalletResult> expireProgram(
    BusinessProfile business,
    LoyaltyProgram program,
  ) => _runOnce('expire-program:${program.id}', () async {
    try {
      final response = await _client.delete(
        Uri.parse('${_base(business)}/api/cards/${program.id}'),
        headers: _merchantHeaders,
      );
      return _simpleResult(response, 'Tarjeta eliminada correctamente');
    } catch (_) {
      return const WalletResult(ok: false, message: 'No se pudo eliminar');
    }
  });

  Future<WalletResult> deleteCustomer(
    BusinessProfile business,
    String customerId,
  ) => _runOnce('delete-customer:$customerId', () async {
    try {
      final response = await _client.delete(
        Uri.parse('${_base(business)}/api/customers/$customerId'),
        headers: _merchantHeaders,
      );
      return _simpleResult(response, 'Cliente eliminado y tarjeta anulada');
    } catch (_) {
      return const WalletResult(ok: false, message: 'No se pudo eliminar');
    }
  });

  Future<WalletResult> deleteCustomerCard(
    BusinessProfile business, {
    required String customerId,
    required String cardId,
  }) => _runOnce('delete-customer-card:$customerId:$cardId', () async {
    try {
      final response = await _client.delete(
        Uri.parse('${_base(business)}/api/customers/$customerId/cards/$cardId'),
        headers: _merchantHeaders,
      );
      return _simpleResult(
        response,
        'Tarjeta eliminada completamente del cliente',
      );
    } catch (_) {
      return const WalletResult(
        ok: false,
        message: 'No se pudo eliminar la tarjeta',
      );
    }
  });

  Future<WalletResult> deleteAllCustomers(BusinessProfile business) =>
      _runOnce('delete-all-customers', () async {
        try {
          final response = await _client.delete(
            Uri.parse('${_base(business)}/api/customers'),
            headers: _merchantHeaders,
          );
          return _simpleResult(
            response,
            'Clientes eliminados y tarjetas anuladas',
          );
        } catch (_) {
          return const WalletResult(ok: false, message: 'No se pudo eliminar');
        }
      });

  Future<WalletResult> deleteCampaign(
    BusinessProfile business,
    String campaignId,
  ) => _runOnce('delete-campaign:$campaignId', () async {
    try {
      final response = await _client.delete(
        Uri.parse('${_base(business)}/api/campaigns/$campaignId'),
        headers: _merchantHeaders,
      );
      return _simpleResult(response, 'Campaña eliminada correctamente');
    } catch (_) {
      return const WalletResult(
        ok: false,
        message: 'No se pudo eliminar la campaña',
      );
    }
  });

  Future<WalletResult> validatePrivateCardQr(
    BusinessProfile business, {
    required String customerId,
    required String programId,
    required String token,
  }) async {
    final cloud = CloudStore.instance;
    if (cloud == null || token.length < 32) {
      return const WalletResult(ok: false, message: 'Código privado no válido');
    }
    try {
      final uri = Uri.parse(
        '${_base(business)}/api/customers/$customerId/cards/$programId/validate-qr',
      );
      final response = await _client.post(
        uri,
        headers: _merchantHeaders,
        body: jsonEncode({'token': token}),
      );
      Map<String, dynamic> body = const {};
      try {
        body = jsonDecode(response.body) as Map<String, dynamic>;
      } catch (_) {}
      return WalletResult(
        ok: response.statusCode == 200,
        message: response.statusCode == 200
            ? 'Código válido'
            : body['message'] as String? ?? 'Código privado no válido',
      );
    } catch (_) {
      return const WalletResult(
        ok: false,
        message: 'No se pudo validar el código',
      );
    }
  }

  Map<String, String> get _merchantHeaders => {
    'content-type': 'application/json',
    if (CloudStore.instance?.accessToken case final token?)
      'authorization': 'Bearer $token',
  };

  WalletResult _simpleResult(http.Response response, String success) {
    Map<String, dynamic> body = const {};
    try {
      body = jsonDecode(response.body) as Map<String, dynamic>;
    } catch (_) {}
    return WalletResult(
      ok: response.statusCode >= 200 && response.statusCode < 300,
      message: response.statusCode >= 200 && response.statusCode < 300
          ? success
          : body['message'] as String? ?? 'Error ${response.statusCode}',
    );
  }

  Uri _customerUri(
    BusinessProfile business,
    Customer customer,
    String platform,
  ) {
    return Uri.parse(
      '${_base(business)}/api/wallet/$platform/${customer.id}',
    ).replace(
      queryParameters: {
        'name': customer.name,
        'points': '${customer.points}',
        'stamps': '${customer.stamps}',
        'visits': '${customer.visits}',
        'tier': customer.tier,
        'referral': customer.referralCode,
        'business': business.name,
        'color': business.colorHex,
      },
    );
  }
}
