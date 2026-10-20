import 'dart:async';
import 'dart:math';

import 'package:flutter/widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/app_data.dart';
import '../config/supabase_config.dart';
import '../services/cloud_store.dart';
import '../services/local_store.dart';
import '../services/wallet_service.dart';

class AppState extends ChangeNotifier with WidgetsBindingObserver {
  AppState(this._store, this.data, {this.cloudStore, this.cloudDataLoader}) {
    _assignMissingCustomerAvatars();
    if (cloudStore != null) {
      WidgetsBinding.instance.addObserver(this);
      _startRealtimeWatch();
    }
  }

  final LocalStore _store;
  final CloudStore? cloudStore;
  final Future<AppData?> Function()? cloudDataLoader;
  AppData data;
  bool _refreshing = false;
  bool _writingCloud = false;
  bool get saving => _refreshing || _writingCloud;
  String? cloudError;
  RealtimeChannel? _realtimeChannel;
  Timer? _refreshDebounce;
  Timer? _reconnectTimer;
  Timer? _cloudSaveDebounce;
  Future<void>? _localSaveInFlight;
  Future<void>? _cloudSaveInFlight;
  bool _localSaveAgain = false;
  bool _cloudSaveAgain = false;
  bool _cloudRefreshPending = false;
  int _dataRevision = 0;
  int _remoteMutationDepth = 0;
  bool _disposed = false;

  void _startRealtimeWatch() {
    if (_disposed || cloudStore == null) return;
    final previous = _realtimeChannel;
    if (previous != null) unawaited(cloudStore!.stopWatching(previous));
    _realtimeChannel = cloudStore!.watchAppChanges(
      onCustomerChange: _applyRealtimeCustomerChange,
      onDataChange: _scheduleCloudRefresh,
      onStatus: _handleRealtimeStatus,
    );
  }

  void _handleRealtimeStatus(RealtimeSubscribeStatus status, Object? error) {
    if (status == RealtimeSubscribeStatus.subscribed) {
      _reconnectTimer?.cancel();
      if (cloudError?.startsWith('Sincronización en tiempo real') ?? false) {
        cloudError = null;
      }
      notifyListeners();
      _scheduleCloudRefresh();
      return;
    }
    if (status == RealtimeSubscribeStatus.channelError ||
        status == RealtimeSubscribeStatus.timedOut) {
      cloudError = 'Sincronización en tiempo real reconectando…';
      notifyListeners();
      _reconnectTimer?.cancel();
      _reconnectTimer = Timer(const Duration(seconds: 2), _startRealtimeWatch);
    }
  }

  void _scheduleCloudRefresh() {
    _cloudRefreshPending = true;
    _refreshDebounce?.cancel();
    _refreshDebounce = Timer(
      const Duration(milliseconds: 180),
      () => unawaited(_runScheduledCloudRefresh()),
    );
  }

  Future<void> _runScheduledCloudRefresh() async {
    if (!_cloudRefreshPending) return;
    if (saving ||
        _cloudSaveAgain ||
        _cloudSaveInFlight != null ||
        _remoteMutationDepth > 0) {
      _refreshDebounce?.cancel();
      _refreshDebounce = Timer(
        const Duration(milliseconds: 180),
        () => unawaited(_runScheduledCloudRefresh()),
      );
      return;
    }
    _cloudRefreshPending = false;
    await refreshFromCloud();
    if (_cloudRefreshPending) _scheduleCloudRefresh();
  }

  void _applyRealtimeCustomerChange(PostgresChangePayload payload) {
    final row = payload.eventType == PostgresChangeEvent.delete
        ? payload.oldRecord
        : payload.newRecord;
    final id = row['id']?.toString();
    if (id == null || id.isEmpty) {
      _scheduleCloudRefresh();
      return;
    }

    // Un eco de Realtime puede corresponder al valor que estaba en la nube
    // justo antes del cambio local. No debe reemplazar la edición optimista
    // mientras esa edición todavía está pendiente de persistencia.
    if (saving ||
        _cloudSaveAgain ||
        _cloudSaveInFlight != null ||
        _remoteMutationDepth > 0) {
      _scheduleCloudRefresh();
      return;
    }

    final existingIndex = data.customers.indexWhere((item) => item.id == id);
    final deleted =
        payload.eventType == PostgresChangeEvent.delete ||
        row['deleted_at'] != null;
    if (deleted) {
      if (existingIndex >= 0) data.customers.removeAt(existingIndex);
      data.activities.removeWhere((item) => item.customerId == id);
      _persistRealtimeData();
      _scheduleCloudRefresh();
      return;
    }

    final previous = existingIndex < 0 ? null : data.customers[existingIndex];
    final balances = row['card_balances'] is Map
        ? Map<String, dynamic>.from(row['card_balances'] as Map)
        : const <String, dynamic>{};
    final customer = Customer(
      id: id,
      name: row['name']?.toString() ?? previous?.name ?? 'Cliente',
      phone: row['phone']?.toString() ?? previous?.phone ?? '',
      email: row['email']?.toString() ?? previous?.email ?? '',
      birthDate:
          DateTime.tryParse(row['birth_date']?.toString() ?? '') ??
          previous?.birthDate,
      points: (row['points'] as num?)?.toInt() ?? previous?.points ?? 0,
      stamps: (row['stamps'] as num?)?.toInt() ?? previous?.stamps ?? 0,
      visits: (row['visits'] as num?)?.toInt() ?? previous?.visits ?? 0,
      tier: row['tier']?.toString() ?? previous?.tier ?? '',
      avatarIndex: previous?.avatarIndex ?? _nextCustomerAvatarIndex(),
      referralCode:
          row['referral_code']?.toString() ?? previous?.referralCode ?? id,
      joinedAt:
          DateTime.tryParse(row['joined_at']?.toString() ?? '') ??
          previous?.joinedAt ??
          DateTime.now(),
      unlockedRewardIds: previous?.unlockedRewardIds ?? const [],
      redeemedRewardIds: previous?.redeemedRewardIds ?? const [],
      intelligence: previous?.intelligence,
      cardBalances: balances.map(
        (key, value) => MapEntry(
          key,
          CardBalance.fromJson(Map<String, dynamic>.from(value as Map)),
        ),
      ),
    );
    _refreshCustomer(customer);
    if (existingIndex < 0) {
      data.customers.insert(0, customer);
    } else {
      data.customers[existingIndex] = customer;
    }
    _persistRealtimeData();
    _scheduleCloudRefresh();
  }

  void _persistRealtimeData() {
    _dataRevision += 1;
    notifyListeners();
    _localSaveAgain = true;
    if (_localSaveInFlight == null) {
      final operation = _drainLocalSaves();
      _localSaveInFlight = operation;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    _refreshDebounce?.cancel();
    _reconnectTimer?.cancel();
    _cloudSaveDebounce?.cancel();
    final channel = _realtimeChannel;
    if (channel != null) unawaited(cloudStore?.stopWatching(channel));
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _scheduleCloudRefresh();
      if (_realtimeChannel == null) _startRealtimeWatch();
    }
  }

  static Future<AppState> load({CloudStore? cloudStore}) async {
    final store = LocalStore(namespace: cloudStore?.currentUser?.id);
    var data = await store.load();
    if (cloudStore != null) {
      try {
        // Una cuenta autenticada nunca debe heredar el caché de otra cuenta.
        // Si todavía no tiene información remota, comienza realmente vacía.
        data =
            await cloudStore.load().timeout(const Duration(seconds: 10)) ??
            AppData.initial();
      } catch (_) {
        // El comercio puede seguir trabajando sin conexión, pero únicamente
        // con la copia local aislada por su propio usuario.
      }
    }
    final loadedSchemaVersion = data.schemaVersion;
    if (SupabaseConfig.configured) {
      data.business.backendUrl = SupabaseConfig.walletFunctionUrl;
    } else if (data.business.backendUrl.isEmpty ||
        data.business.backendUrl.contains('localhost')) {
      data.business.backendUrl = 'http://192.168.100.249:8787';
    }
    data.wallet
      ..passTypeIdentifier = 'pass.app.fideli.loyalty'
      ..teamIdentifier = 'F34F83K3QZ'
      ..demoMode = false;
    if (data.schemaVersion < 2) {
      if (data.business.onboarded && data.customers.isEmpty) {
        data.customers.add(
          Customer(
            id: 'cliente-prueba',
            name: 'Lucas Tejerina',
            points: 250,
            stamps: 4,
            visits: 7,
            tier: 'Plata',
            referralCode: 'LUC1234',
            joinedAt: DateTime.now(),
          ),
        );
        data.activities.insert(
          0,
          ActivityRecord(
            id: newId('activity'),
            customerId: 'cliente-prueba',
            description: 'Pase Apple Wallet importado',
            createdAt: DateTime.now(),
            pointsDelta: 250,
          ),
        );
      }
      data.schemaVersion = 2;
    }
    if (data.schemaVersion < 3) {
      if (data.programs.isEmpty) {
        data.programs.add(
          LoyaltyProgram(
            id: 'program-stamps',
            name: 'Tarjeta de sellos',
            type: ProgramType.stamps,
            goal: 7,
          ),
        );
      } else {
        for (final program in data.programs) {
          program.active = false;
        }
        data.programs.first
          ..name = 'Tarjeta de sellos'
          ..type = ProgramType.stamps
          ..earningRate = 1
          ..goal = 7
          ..active = true;
      }
      if (data.rewards.isEmpty) {
        data.rewards.add(
          Reward(
            id: 'reward-stamps-7',
            name: 'Producto de cortesía',
            stampsCost: 7,
          ),
        );
      } else {
        data.rewards.first
          ..pointsCost = 0
          ..stampsCost = 7
          ..active = true;
      }
      data.schemaVersion = 3;
    }
    if (data.schemaVersion < 4) {
      for (final program in data.programs) {
        program.cardKind = 'Fidelización';
      }
      data.schemaVersion = 4;
    }
    if (data.schemaVersion < 5) {
      final stampPrograms = data.programs
          .where((program) => program.type == ProgramType.stamps)
          .toList();
      if (stampPrograms.length == 1) {
        for (final customer in data.customers) {
          customer.cardBalances.putIfAbsent(
            stampPrograms.first.id,
            () => CardBalance(stamps: customer.stamps, visits: customer.visits),
          );
        }
      }
      data.schemaVersion = 5;
    }
    if (data.schemaVersion < 6) {
      final legacyTiers = data.tiers
          .map(
            (tier) => TierRule(
              id: tier.id,
              name: tier.name,
              threshold: tier.threshold,
            ),
          )
          .toList();
      for (final program in data.programs.where(
        (item) => item.type == ProgramType.points,
      )) {
        if (program.tiers.isEmpty) {
          program.tiers = legacyTiers
              .map(
                (tier) => TierRule(
                  id: '${program.id}-${tier.id}',
                  name: tier.name,
                  threshold: tier.threshold,
                ),
              )
              .toList();
        }
      }
      data.tiers.clear();
      data.challenges.clear();
      data.automations.clear();
      data.schemaVersion = 6;
    }
    if (data.schemaVersion < 7) {
      for (final reward in data.rewards.where(
        (reward) => reward.programId.isEmpty,
      )) {
        final compatibleProgram = data.programs
            .where(
              (program) =>
                  (reward.stampsCost > 0 &&
                      program.type == ProgramType.stamps) ||
                  (reward.pointsCost > 0 && program.type == ProgramType.points),
            )
            .firstOrNull;
        reward.programId = compatibleProgram?.id ?? '';
      }
      data.schemaVersion = 7;
    }
    if (data.schemaVersion < 8) {
      data.schemaVersion = 8;
    }
    if (data.schemaVersion < 9) {
      data.schemaVersion = 9;
    }
    if (data.schemaVersion < 10) {
      data.schemaVersion = 10;
    }
    await store.save(data);
    if (cloudStore != null && data.schemaVersion != loadedSchemaVersion) {
      try {
        await cloudStore.save(data);
      } catch (_) {
        // La migración inicial se reintentará en el próximo cambio local.
      }
    }
    return AppState(store, data, cloudStore: cloudStore);
  }

  Future<void> commit() {
    for (final customer in data.customers) {
      _refreshCustomer(customer);
    }
    _dataRevision += 1;
    notifyListeners();
    _localSaveAgain = true;
    _scheduleCloudSave();
    final running = _localSaveInFlight;
    if (running != null) return running;
    final operation = _drainLocalSaves();
    _localSaveInFlight = operation;
    return operation;
  }

  /// Guarda la edición en este dispositivo sin programar una segunda escritura
  /// completa a Supabase. Se usa cuando una API específica persiste el cambio.
  Future<void> commitLocalOnly() {
    for (final customer in data.customers) {
      _refreshCustomer(customer);
    }
    _dataRevision += 1;
    notifyListeners();
    _localSaveAgain = true;
    final running = _localSaveInFlight;
    if (running != null) return running;
    final operation = _drainLocalSaves();
    _localSaveInFlight = operation;
    return operation;
  }

  /// Persiste de inmediato los cambios que deben estar disponibles en otros
  /// dispositivos antes de continuar (programas, metas y premios).
  Future<void> commitAndSync() async {
    await commit();
    if (cloudStore == null) return;
    _cloudSaveDebounce?.cancel();
    await _flushCloudSaves();
  }

  Future<void> _drainLocalSaves() async {
    try {
      while (_localSaveAgain) {
        _localSaveAgain = false;
        await _store.save(data);
      }
    } finally {
      _localSaveInFlight = null;
    }
  }

  void _scheduleCloudSave() {
    if (cloudStore == null) return;
    _cloudSaveAgain = true;
    _cloudSaveDebounce?.cancel();
    _cloudSaveDebounce = Timer(const Duration(milliseconds: 450), () {
      unawaited(_flushCloudSaves());
    });
  }

  Future<void> _flushCloudSaves() {
    final running = _cloudSaveInFlight;
    if (running != null) return running;
    final operation = _drainCloudSaves();
    _cloudSaveInFlight = operation;
    return operation;
  }

  Future<void> _drainCloudSaves() async {
    _writingCloud = true;
    final previousError = cloudError;
    try {
      while (_cloudSaveAgain) {
        _cloudSaveAgain = false;
        final snapshot = AppData.decode(data.encode());
        try {
          await cloudStore!.save(snapshot);
          cloudError = null;
        } catch (_) {
          cloudError = 'Cambios pendientes. Revisa tu conexión.';
        }
      }
    } finally {
      _cloudSaveInFlight = null;
      _writingCloud = false;
      if (previousError != cloudError) notifyListeners();
      if (_cloudRefreshPending) _scheduleCloudRefresh();
    }
  }

  Future<bool> refreshFromCloud() async {
    final loader = cloudDataLoader ?? cloudStore?.load;
    if (loader == null ||
        saving ||
        _cloudSaveAgain ||
        _cloudSaveInFlight != null ||
        _remoteMutationDepth > 0) {
      return false;
    }
    final revisionAtStart = _dataRevision;
    final previousError = cloudError;
    var applied = false;
    _refreshing = true;
    try {
      final remote = await loader();
      // Never let a response that started before a local edit replace that
      // newer edit. This was the cause of deleted rows reappearing briefly or
      // permanently throughout the app.
      final stillCurrent =
          revisionAtStart == _dataRevision &&
          !_cloudSaveAgain &&
          _cloudSaveInFlight == null &&
          _remoteMutationDepth == 0;
      if (remote != null && stillCurrent) {
        data = remote;
        data.business.backendUrl = SupabaseConfig.walletFunctionUrl;
        await _store.save(data);
        applied = true;
      }
      cloudError = null;
      return applied;
    } catch (_) {
      cloudError = 'No se pudo actualizar. Revisa tu conexión.';
      return false;
    } finally {
      _refreshing = false;
      if (applied || previousError != cloudError) notifyListeners();
    }
  }

  /// Blocks realtime reloads while an API mutation is in flight. The local
  /// optimistic state remains authoritative until the server confirms or the
  /// caller rolls it back.
  Future<T> runRemoteMutation<T>(Future<T> Function() operation) async {
    _remoteMutationDepth += 1;
    try {
      return await operation();
    } finally {
      _remoteMutationDepth -= 1;
      if (_remoteMutationDepth == 0 && _cloudRefreshPending) {
        _scheduleCloudRefresh();
      }
    }
  }

  Future<void> finishOnboarding({
    required String name,
    required String category,
    required String branch,
  }) async {
    data.business
      ..name = name.trim()
      ..category = category.trim()
      ..branches = [branch.trim()]
      ..onboarded = true;
    await commit();
  }

  Customer addCustomer({
    required String name,
    String phone = '',
    String email = '',
    DateTime? birthDate,
    String? referredBy,
  }) {
    final id = newId('customer');
    final code =
        '${name.trim().toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '').padRight(3, 'X').substring(0, 3)}${Random().nextInt(9000) + 1000}';
    final customer = Customer(
      id: id,
      name: name.trim(),
      phone: phone.trim(),
      email: email.trim(),
      birthDate: birthDate,
      avatarIndex: _nextCustomerAvatarIndex(),
      referralCode: code,
      joinedAt: DateTime.now(),
    );
    data.customers.add(customer);
    _activity(customer.id, 'Alta de cliente', eventType: 'wallet_pass_created');
    if (referredBy != null && referredBy.isNotEmpty) {
      final referrer = data.customers.where(
        (c) => c.referralCode == referredBy,
      );
      if (referrer.isNotEmpty) {
        referrer.first.points += 50;
        final program = data.programs
            .where((item) => item.active && !item.isExpired)
            .firstOrNull;
        if (program != null) {
          referrer.first.balanceFor(program.id).points += 50;
        }
        _activity(
          referrer.first.id,
          'Referido registrado',
          points: 50,
          eventType: 'referral',
          metadata: {'referred_customer_id': customer.id},
        );
      }
    }
    _refreshCustomer(customer);
    commit();
    return customer;
  }

  int _nextCustomerAvatarIndex() {
    final counts = List<int>.filled(4, 0);
    for (final customer in data.customers) {
      if (customer.avatarIndex < 0 || customer.avatarIndex >= counts.length) {
        continue;
      }
      final index = customer.avatarIndex;
      counts[index] += 1;
    }
    final minimum = counts.reduce(min);
    final available = <int>[
      for (var index = 0; index < counts.length; index++)
        if (counts[index] == minimum) index,
    ];
    return available[Random().nextInt(available.length)];
  }

  void _assignMissingCustomerAvatars() {
    for (final customer in data.customers) {
      if (customer.avatarIndex < 0 || customer.avatarIndex > 3) {
        customer.avatarIndex = _nextCustomerAvatarIndex();
      }
    }
  }

  String referralQrPayload(Customer customer, {LoyaltyProgram? program}) {
    final businessId = cloudStore?.businessId;
    if (businessId == null || businessId.isEmpty) return customer.qrPayload;
    final base = SupabaseConfig.publicClubUriForBusiness(
      businessId,
      publicSlug: data.business.publicSlug,
    );
    return base
        .replace(
          queryParameters: {
            ...base.queryParameters,
            'ref': customer.referralCode,
            'customer': customer.id,
            if (program != null) 'card': program.id,
          },
        )
        .toString();
  }

  Future<WalletResult> deleteCustomer(String id) async {
    final index = data.customers.indexWhere((item) => item.id == id);
    if (index < 0) {
      return const WalletResult(ok: true, message: 'Cliente eliminado');
    }
    return runRemoteMutation(() async {
      final removedCustomer = data.customers[index];
      final removedActivities = data.activities
          .where((item) => item.customerId == id)
          .toList();
      data.customers.removeAt(index);
      data.activities.removeWhere((item) => item.customerId == id);
      await commitLocalOnly();
      final result = await WalletService().deleteCustomer(data.business, id);
      if (result.ok) return result;
      data.customers.insert(
        index.clamp(0, data.customers.length).toInt(),
        removedCustomer,
      );
      data.activities.addAll(removedActivities);
      data.activities.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      await commitLocalOnly();
      return result;
    });
  }

  Future<WalletResult> deleteCustomerCard(
    String customerId,
    String cardId,
  ) async {
    return runRemoteMutation(() async {
      final customer = customerById(customerId);
      final removedBalance = customer?.cardBalances.remove(cardId);
      final removedActivities = data.activities
          .where(
            (item) => item.customerId == customerId && item.programId == cardId,
          )
          .toList();
      data.activities.removeWhere(
        (item) => item.customerId == customerId && item.programId == cardId,
      );
      await commitLocalOnly();
      final result = await WalletService().deleteCustomerCard(
        data.business,
        customerId: customerId,
        cardId: cardId,
      );
      if (result.ok) return result;
      if (customer != null && removedBalance != null) {
        customer.cardBalances[cardId] = removedBalance;
      }
      data.activities.addAll(removedActivities);
      data.activities.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      await commitLocalOnly();
      return result;
    });
  }

  Future<WalletResult> deleteAllCustomers() async {
    return runRemoteMutation(() async {
      final removedCustomers = List<Customer>.from(data.customers);
      final removedActivities = List<ActivityRecord>.from(data.activities);
      data.customers.clear();
      data.activities.clear();
      await commitLocalOnly();
      final result = await WalletService().deleteAllCustomers(data.business);
      if (result.ok) return result;
      data.customers
        ..clear()
        ..addAll(removedCustomers);
      data.activities
        ..clear()
        ..addAll(removedActivities);
      await commitLocalOnly();
      return result;
    });
  }

  void recordVisit(String customerId, {int purchaseAmount = 0}) {
    final customer = customerById(customerId);
    if (customer == null) return;
    final program = data.programs.where((item) => item.active).firstOrNull;
    final earned = switch (program?.type) {
      ProgramType.points || ProgramType.hybrid =>
        max(1, purchaseAmount) * (program?.earningRate ?? 1),
      _ => 0,
    };
    customer.visits += 1;
    if (program?.type == ProgramType.stamps) {
      customer.stamps += program?.earningRate ?? 1;
    } else if (program?.type == ProgramType.hybrid) {
      customer.stamps += 1;
    }
    customer.points += earned;
    _activity(
      customer.id,
      'Visita registrada',
      points: earned,
      eventType: purchaseAmount > 0 ? 'purchase' : 'visit',
      programId: program?.id,
      amountMinor: purchaseAmount,
    );
    _refreshCustomer(customer);
    commit();
  }

  void adjustCustomer(
    String customerId, {
    int pointsDelta = 0,
    int stampsDelta = 0,
    int visitsDelta = 0,
    String note = 'Ajuste manual',
  }) {
    final customer = customerById(customerId);
    if (customer == null) return;
    customer
      ..points = max(0, customer.points + pointsDelta)
      ..stamps = max(0, customer.stamps + stampsDelta)
      ..visits = max(0, customer.visits + visitsDelta);
    final details = <String>[
      if (pointsDelta != 0) '${pointsDelta > 0 ? '+' : ''}$pointsDelta pts',
      if (stampsDelta != 0) '${stampsDelta > 0 ? '+' : ''}$stampsDelta sellos',
      if (visitsDelta != 0) '${visitsDelta > 0 ? '+' : ''}$visitsDelta visitas',
    ].join(' · ');
    _activity(
      customer.id,
      details.isEmpty ? note : '$note: $details',
      points: pointsDelta,
    );
    _refreshCustomer(customer);
    commit();
  }

  Future<void> registerStampVisit(
    String customerId, {
    String? programId,
  }) async {
    final customer = customerById(customerId);
    if (customer == null) return;
    final program = programId == null
        ? data.programs
              .where((item) => item.active && !item.isExpired)
              .firstOrNull
        : data.programs
              .where(
                (item) =>
                    item.id == programId && item.active && !item.isExpired,
              )
              .firstOrNull;
    customer.visits += 1;
    final cardBalance = program == null
        ? null
        : customer.balanceFor(program.id);
    if (cardBalance != null) cardBalance.visits += 1;
    final amount = program?.earningRate ?? 1;
    if (program?.type == ProgramType.points) {
      customer.points += amount;
      if (cardBalance != null) cardBalance.points += amount;
    } else if (program?.type == ProgramType.stamps ||
        program?.type == ProgramType.hybrid) {
      customer.stamps += amount;
      if (cardBalance != null) cardBalance.stamps += amount;
    }
    final unit = switch (program?.type) {
      ProgramType.points => 'puntos',
      ProgramType.visits || ProgramType.membership => 'visita',
      _ => 'sellos',
    };
    _activity(
      customer.id,
      'Visita en ${program?.name ?? 'tarjeta principal'}: +${unit == 'visita' ? 1 : amount} $unit',
      points: program?.type == ProgramType.points
          ? program?.earningRate ?? 1
          : 0,
      eventType: program?.type == ProgramType.points
          ? 'points_added'
          : 'stamp_added',
      programId: program?.id,
    );
    _refreshCustomer(customer);
    await commit();
  }

  Future<void> correctProgramValue(
    String customerId, {
    String? programId,
  }) async {
    final customer = customerById(customerId);
    if (customer == null) return;
    final program = programId == null
        ? null
        : data.programs.where((item) => item.id == programId).firstOrNull;
    final cardBalance = programId == null
        ? null
        : customer.cardBalances[programId];
    if (program?.type == ProgramType.points && cardBalance != null) {
      if (cardBalance.points == 0) return;
      cardBalance.points -= 1;
      customer.points = max(0, customer.points - 1);
      _activity(
        customer.id,
        'Corrección: -1 punto',
        points: -1,
        eventType: 'adjustment',
        programId: programId,
      );
    } else if ((program?.type == ProgramType.visits ||
            program?.type == ProgramType.membership) &&
        cardBalance != null) {
      if (cardBalance.visits == 0) return;
      cardBalance.visits -= 1;
      customer.visits = max(0, customer.visits - 1);
      _activity(
        customer.id,
        'Corrección: -1 visita',
        eventType: 'adjustment',
        programId: programId,
      );
    } else if (cardBalance != null) {
      if (cardBalance.stamps == 0 && customer.stamps > 0) {
        cardBalance.stamps = customer.stamps;
      }
      if (cardBalance.stamps == 0) return;
      cardBalance.stamps -= 1;
      customer.stamps = max(0, customer.stamps - 1);
      _activity(
        customer.id,
        'Corrección: -1 sello',
        eventType: 'adjustment',
        programId: programId,
      );
    } else if (customer.stamps == 0) {
      return;
    } else {
      customer.stamps -= 1;
      _activity(
        customer.id,
        'Corrección: -1 sello',
        eventType: 'adjustment',
        programId: programId,
      );
    }
    _refreshCustomer(customer);
    await commit();
  }

  Future<void> adjustCardValue(
    String customerId,
    String programId, {
    required int delta,
    required String description,
    bool syncImmediately = false,
  }) async {
    final customer = customerById(customerId);
    final program = data.programs
        .where((item) => item.id == programId)
        .firstOrNull;
    if (customer == null || program == null || delta == 0) return;
    final balance = customer.balanceFor(programId);
    switch (program.type) {
      case ProgramType.points:
        final applied = max(-balance.points, delta);
        balance.points += applied;
        customer.points = max(0, customer.points + applied);
        _activity(
          customer.id,
          '$description: ${applied > 0 ? '+' : ''}$applied',
          points: applied,
          eventType: applied > 0 ? 'points_added' : 'adjustment',
          programId: program.id,
        );
      case ProgramType.visits:
      case ProgramType.membership:
        final applied = max(-balance.visits, delta);
        balance.visits += applied;
        customer.visits = max(0, customer.visits + applied);
        _activity(
          customer.id,
          '$description: ${applied > 0 ? '+' : ''}$applied accesos',
          eventType: applied > 0 ? 'visit' : 'adjustment',
          programId: program.id,
        );
      case ProgramType.stamps:
      case ProgramType.hybrid:
        final applied = max(-balance.stamps, delta);
        balance.stamps += applied;
        customer.stamps = max(0, customer.stamps + applied);
        _activity(
          customer.id,
          '$description: ${applied > 0 ? '+' : ''}$applied sellos',
          eventType: applied > 0 ? 'stamp_added' : 'adjustment',
          programId: program.id,
        );
    }
    _refreshCustomer(customer);
    if (syncImmediately) {
      await commitAndSync();
    } else {
      await commit();
    }
  }

  Future<void> setCardValue(
    String customerId,
    String programId,
    int value,
  ) async {
    final customer = customerById(customerId);
    final program = data.programs
        .where((item) => item.id == programId)
        .firstOrNull;
    if (customer == null || program == null) return;
    final target = max(0, value);
    final balance = customer.balanceFor(programId);
    switch (program.type) {
      case ProgramType.points:
        final delta = target - balance.points;
        balance.points = target;
        customer.points = max(0, customer.points + delta);
      case ProgramType.visits:
      case ProgramType.membership:
        final delta = target - balance.visits;
        balance.visits = target;
        customer.visits = max(0, customer.visits + delta);
      case ProgramType.stamps:
      case ProgramType.hybrid:
        final delta = target - balance.stamps;
        balance.stamps = target;
        customer.stamps = max(0, customer.stamps + delta);
    }
    _refreshCustomer(customer);
    await commit();
  }

  Future<void> recordCardValueActivity(
    String customerId,
    String programId, {
    required int delta,
    required String description,
  }) async {
    if (delta == 0) return;
    _activity(
      customerId,
      '$description: ${delta > 0 ? '+' : ''}$delta',
      points: delta,
      eventType: delta > 0 ? 'points_added' : 'adjustment',
      programId: programId,
    );
    await commit();
  }

  bool redeemReward(String customerId, String rewardId) {
    final customer = customerById(customerId);
    final reward = data.rewards
        .where((item) => item.id == rewardId)
        .firstOrNull;
    if (customer == null ||
        reward == null ||
        !reward.active ||
        customer.redeemedRewardIds.contains(rewardId)) {
      return false;
    }
    final program = data.programs
        .where((item) => item.id == reward.programId)
        .firstOrNull;
    if (program == null) return false;
    final balance = customer.balanceFor(program.id);
    if (balance.points < reward.pointsCost ||
        balance.stamps < reward.stampsCost) {
      return false;
    }
    final isIntermediateStampMilestone = program.stampMilestones.any(
      (item) => item.id == reward.id && item.stamp < program.goal,
    );
    if (!isIntermediateStampMilestone) {
      balance
        ..points -= reward.pointsCost
        ..stamps -= reward.stampsCost;
    }
    customer
      ..points = isIntermediateStampMilestone
          ? customer.points
          : max(0, customer.points - reward.pointsCost)
      ..stamps = isIntermediateStampMilestone
          ? customer.stamps
          : max(0, customer.stamps - reward.stampsCost)
      ..redeemedRewardIds = [...customer.redeemedRewardIds, reward.id];
    reward.redemptions += 1;
    _activity(
      customer.id,
      'Canje: ${reward.name}',
      points: isIntermediateStampMilestone ? 0 : -reward.pointsCost,
      eventType: 'reward_redeemed',
      programId: program.id,
      metadata: {'reward_id': reward.id, 'reward_name': reward.name},
    );
    _refreshCustomer(customer);
    commit();
    return true;
  }

  bool canRedeemReward(String customerId, String rewardId) {
    final customer = customerById(customerId);
    final reward = data.rewards
        .where((item) => item.id == rewardId && item.active)
        .firstOrNull;
    if (customer == null || reward == null || reward.programId.isEmpty) {
      return false;
    }
    if (customer.redeemedRewardIds.contains(reward.id)) return false;
    final balance = customer.cardBalances[reward.programId];
    return balance != null &&
        balance.points >= reward.pointsCost &&
        balance.stamps >= reward.stampsCost;
  }

  Customer? customerById(String id) =>
      data.customers.where((item) => item.id == id).firstOrNull;

  void _refreshCustomer(Customer customer) {
    final pointsProgram = data.programs
        .where(
          (program) =>
              program.active &&
              !program.isExpired &&
              program.type == ProgramType.points &&
              program.tiers.isNotEmpty,
        )
        .firstOrNull;
    final eligibleTiers = [...?pointsProgram?.tiers]
      ..sort((a, b) => a.threshold.compareTo(b.threshold));
    final programPoints = pointsProgram == null
        ? customer.points
        : customer.cardBalances[pointsProgram.id]?.points ?? customer.points;
    customer.tier = eligibleTiers.isEmpty ? '' : eligibleTiers.first.name;
    for (final tier in eligibleTiers) {
      if (programPoints >= tier.threshold) customer.tier = tier.name;
    }
    customer.unlockedRewardIds = data.rewards
        .where((reward) {
          if (!reward.active || reward.programId.isEmpty) return false;
          final balance = customer.cardBalances[reward.programId];
          return balance != null &&
              balance.points >= reward.pointsCost &&
              balance.stamps >= reward.stampsCost;
        })
        .map((reward) => reward.id)
        .toList();
  }

  void _activity(
    String customerId,
    String description, {
    int points = 0,
    String eventType = 'other',
    String? programId,
    int amountMinor = 0,
    Map<String, dynamic> metadata = const {},
  }) {
    data.activities.insert(
      0,
      ActivityRecord(
        id: newId('activity'),
        customerId: customerId,
        description: description,
        createdAt: DateTime.now(),
        pointsDelta: points,
        eventType: eventType,
        programId: programId,
        amountMinor: amountMinor,
        metadata: metadata,
      ),
    );
  }

  Future<void> resetDemo() async {
    data = AppData.initial();
    await _store.clear();
    notifyListeners();
  }
}
