import 'dart:convert';
import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/supabase_config.dart';
import '../models/app_data.dart';
import '../models/customer_intelligence.dart';

class CloudStore {
  CloudStore._();

  static CloudStore? _instance;
  static CloudStore? get instance => _instance;
  static bool get configured => SupabaseConfig.configured;
  static String? initializationError;

  final SupabaseClient _client = Supabase.instance.client;
  String publicSlug = '';

  static Future<void> initialize() async {
    if (!configured) return;
    try {
      await Supabase.initialize(
        url: SupabaseConfig.url,
        publishableKey: SupabaseConfig.publishableKey,
      ).timeout(const Duration(seconds: 8));
      _instance = CloudStore._();
      initializationError = null;
    } catch (_) {
      initializationError = 'No se pudo iniciar el servicio';
      _instance = null;
    }
  }

  String get businessId {
    final user = _client.auth.currentUser;
    if (user == null) throw StateError('No existe una sesión activa');
    return user.id;
  }

  String? get accessToken => _client.auth.currentSession?.accessToken;

  User? get currentUser => _client.auth.currentUser;

  bool get hasRestaurantSession {
    final user = currentUser;
    return user != null && !user.isAnonymous && user.email != null;
  }

  Future<void> signInRestaurant({
    required String email,
    required String password,
  }) async {
    if (_client.auth.currentUser?.isAnonymous ?? false) {
      await _client.auth.signOut();
    }
    await _client.auth.signInWithPassword(
      email: email.trim().toLowerCase(),
      password: password,
    );
  }

  Future<void> signOutRestaurant() => _client.auth.signOut();

  Future<List<Map<String, dynamic>>> loadStoreProducts() async =>
      (await _client
              .from('storefront_products')
              .select()
              .eq('business_id', businessId)
              .order('created_at'))
          .map((row) => Map<String, dynamic>.from(row))
          .toList();

  Future<List<Map<String, dynamic>>> loadStoreOrders() async {
    final orders = <Map<String, dynamic>>[];
    for (var offset = 0; ; offset += 500) {
      final page = await _client
          .from('storefront_orders')
          .select()
          .eq('business_id', businessId)
          .order('created_at', ascending: false)
          .order('id')
          .range(offset, offset + 499);
      orders.addAll(page.map((row) => Map<String, dynamic>.from(row)));
      if (page.length < 500) return orders;
    }
  }

  Future<List<Map<String, dynamic>>> loadPendingRewardClaims() async =>
      (await _client
              .from('customer_reward_claims')
              .select(
                'customer_id,reward_id,program_id,reward_name,earned_at,reminder_count,last_reminder_at',
              )
              .eq('business_id', businessId)
              .isFilter('claimed_at', null)
              .order('earned_at', ascending: true))
          .map((row) => Map<String, dynamic>.from(row))
          .toList();

  RealtimeChannel watchStoreOrders(void Function() onChange) => _client
      .channel(
        'store-orders-$businessId-${DateTime.now().microsecondsSinceEpoch}',
      )
      .onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'storefront_orders',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'business_id',
          value: businessId,
        ),
        callback: (_) => onChange(),
      )
      .subscribe();

  Future<void> stopWatchingStoreOrders(RealtimeChannel channel) =>
      _client.removeChannel(channel);

  Future<void> saveStoreProduct(Map<String, dynamic> product) async {
    await _client.from('storefront_products').upsert({
      ...product,
      'business_id': businessId,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }, onConflict: 'business_id,id');
  }

  Future<void> deleteStoreProduct(String id) async {
    await _client
        .from('storefront_products')
        .delete()
        .eq('business_id', businessId)
        .eq('id', id);
  }

  Future<Map<String, dynamic>> loadStoreSettings() async =>
      Map<String, dynamic>.from(
        await _client
                .from('storefront_settings')
                .select()
                .eq('business_id', businessId)
                .maybeSingle() ??
            {},
      );

  Future<void> saveStoreSettings(Map<String, dynamic> settings) async {
    await _client.from('storefront_settings').upsert({
      ...settings,
      'business_id': businessId,
    });
  }

  Future<String> uploadStoreImage(String key, Uint8List bytes) async {
    if (!RegExp(r'^[a-zA-Z0-9_-]+$').hasMatch(key) || bytes.length > 1800000) {
      throw StateError('La imagen es demasiado grande. Elige otra foto.');
    }
    final bucket = _client.storage.from('storefront-images');
    final path = '$businessId/$key.jpg';
    await bucket.uploadBinary(
      path,
      bytes,
      fileOptions: const FileOptions(
        contentType: 'image/jpeg',
        upsert: true,
        cacheControl: '60',
      ),
    );
    return '${bucket.getPublicUrl(path)}?v=${DateTime.now().millisecondsSinceEpoch}';
  }

  Future<void> updateStoreContact(String phone) async {
    await _client
        .from('businesses')
        .update({'whatsapp_phone': phone.trim()})
        .eq('id', businessId);
  }

  Future<void> updateStoreOrderStatus(String id, String status) async {
    await _client
        .from('storefront_orders')
        .update({
          'status': status,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('business_id', businessId)
        .eq('id', id);
  }

  Future<Map<String, dynamic>?> loadPublicStore(String slug) async {
    final result = await _client.rpc(
      'get_storefront',
      params: {'p_slug': slug},
    );
    return result is Map ? Map<String, dynamic>.from(result) : null;
  }

  Future<Map<String, dynamic>> createPublicStoreOrder({
    required String slug,
    required String name,
    required String phone,
    required List<Map<String, dynamic>> items,
    String? requestId,
    String comment = '',
  }) async {
    try {
      final result = await _client.rpc(
        'place_storefront_order',
        params: {
          'p_slug': slug,
          'p_name': name,
          'p_phone': phone,
          'p_comment': comment,
          'p_items': items,
          'p_request_id': ?requestId,
        },
      );
      return Map<String, dynamic>.from(result as Map);
    } on PostgrestException catch (error) {
      const safeMessages = [
        'Local no encontrado',
        'Escribe tu nombre',
        'El comentario es demasiado largo',
        'Este local aún no configuró su WhatsApp. Inténtalo más tarde.',
        'El carrito no es válido',
        'El carrito está vacío',
        'El carrito contiene un producto inválido',
        'La cantidad de un producto no es válida',
        'El carrito contiene productos repetidos',
        'No hay productos disponibles',
        'Uno o más productos ya no están disponibles. Actualiza el catálogo e inténtalo otra vez.',
      ];
      final safeMessage = safeMessages.cast<String?>().firstWhere(
        (message) => message != null && error.message.startsWith(message),
        orElse: () => null,
      );
      throw StateError(
        safeMessage ??
            'No se pudo registrar el pedido. Comprueba tu conexión e inténtalo otra vez.',
      );
    }
  }

  /// Devuelve true si la cuenta quedó autenticada inmediatamente. Si Supabase
  /// exige confirmar el correo, devuelve false y el usuario debe confirmarlo.
  Future<bool> registerRestaurant({
    required String restaurantName,
    required String email,
    required String password,
  }) async {
    if (_client.auth.currentUser != null) {
      await _client.auth.signOut();
    }
    final response = await _client.auth.signUp(
      email: email.trim().toLowerCase(),
      password: password,
      data: {
        'restaurant_name': restaurantName.trim(),
        'account_type': 'restaurant',
      },
    );
    return response.session != null && response.user != null;
  }

  RealtimeChannel watchAppChanges({
    required void Function(PostgresChangePayload payload) onCustomerChange,
    required void Function() onDataChange,
    void Function(RealtimeSubscribeStatus status, Object? error)? onStatus,
  }) {
    final businessFilter = PostgresChangeFilter(
      type: PostgresChangeFilterType.eq,
      column: 'business_id',
      value: businessId,
    );
    return _client
        .channel(
          'fideli-live-$businessId-${DateTime.now().microsecondsSinceEpoch}',
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'customers',
          filter: businessFilter,
          callback: onCustomerChange,
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'module_records',
          filter: businessFilter,
          callback: (_) => onDataChange(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'loyalty_cards',
          filter: businessFilter,
          callback: (_) => onDataChange(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'customer_features',
          filter: businessFilter,
          callback: (_) => onDataChange(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'customer_segments',
          filter: businessFilter,
          callback: (_) => onDataChange(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'loyalty_events',
          filter: businessFilter,
          callback: (_) => onDataChange(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'customer_reward_redemptions',
          filter: businessFilter,
          callback: (_) => onDataChange(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'businesses',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'id',
            value: businessId,
          ),
          callback: (_) => onDataChange(),
        )
        .subscribe(onStatus);
  }

  Future<void> stopWatching(RealtimeChannel channel) =>
      _client.removeChannel(channel);

  Future<AppData?> load() async {
    final row = await _client
        .from('app_snapshots')
        .select('payload')
        .eq('business_id', businessId)
        .maybeSingle();
    final payload = row?['payload'];
    final data = payload is Map
        ? AppData.decode(jsonEncode(Map<String, dynamic>.from(payload)))
        : AppData.initial();
    final businessRow = await _client
        .from('businesses')
        .select(
          'name,category,color_hex,branches,wallet_icon_path,wallet_logo_path,public_slug,locations',
        )
        .eq('id', businessId)
        .maybeSingle();
    if (payload is! Map && businessRow == null) return null;
    data.business.name = businessRow?['name'] as String? ?? data.business.name;
    data.business.category =
        businessRow?['category'] as String? ?? data.business.category;
    data.business.colorHex =
        businessRow?['color_hex'] as String? ?? data.business.colorHex;
    data.business.branches = List<String>.from(
      businessRow?['branches'] as List? ?? data.business.branches,
    );
    data.business.walletIconPath =
        businessRow?['wallet_icon_path'] as String? ??
        data.business.walletIconPath;
    data.business.walletLogoPath =
        businessRow?['wallet_logo_path'] as String? ??
        data.business.walletLogoPath;
    data.business.publicSlug =
        businessRow?['public_slug'] as String? ?? data.business.publicSlug;
    data.business.locations = (businessRow?['locations'] as List? ?? const [])
        .map(
          (item) =>
              BusinessLocation.fromJson(Map<String, dynamic>.from(item as Map)),
        )
        .toList();
    publicSlug = data.business.publicSlug;
    final previous = {
      for (final customer in data.customers) customer.id: customer,
    };
    final remoteRows = await _client
        .from('customers')
        .select()
        .eq('business_id', businessId)
        .isFilter('deleted_at', null)
        .order('joined_at', ascending: false);
    final avatarCounts = List<int>.filled(4, 0);
    data.customers = remoteRows.map((row) {
      final old = previous[row['id'] as String];
      final previousAvatar = old?.avatarIndex ?? -1;
      final avatarIndex = previousAvatar >= 0 && previousAvatar < 4
          ? previousAvatar
          : _leastUsedAvatarIndex(avatarCounts, row['id'] as String);
      avatarCounts[avatarIndex] += 1;
      return Customer(
        id: row['id'] as String,
        name: row['name'] as String,
        phone: row['phone'] as String? ?? '',
        email: row['email'] as String? ?? '',
        birthDate: DateTime.tryParse(row['birth_date'] as String? ?? ''),
        points: row['points'] as int? ?? 0,
        stamps: row['stamps'] as int? ?? 0,
        visits: row['visits'] as int? ?? 0,
        tier: row['tier'] as String? ?? '',
        avatarIndex: avatarIndex,
        referralCode: row['referral_code'] as String,
        joinedAt:
            DateTime.tryParse(row['joined_at'] as String? ?? '') ??
            DateTime.now(),
        unlockedRewardIds: old?.unlockedRewardIds ?? const [],
        redeemedRewardIds: old?.redeemedRewardIds ?? const [],
        intelligence: old?.intelligence,
        cardBalances: (row['card_balances'] as Map? ?? const {}).map(
          (key, value) => MapEntry(
            key as String,
            CardBalance.fromJson(Map<String, dynamic>.from(value as Map)),
          ),
        ),
      );
    }).toList();
    await _loadCustomerIntelligence(data);
    final moduleRows = await _client
        .from('module_records')
        .select('module_type,payload')
        .eq('business_id', businessId);
    // module_records is authoritative even when the result is empty. Keeping
    // values from app_snapshots in that case resurrected the final deleted
    // program, reward or campaign until a later full save completed.
    List<Map<String, dynamic>> records(String type) => moduleRows
        .where((row) => row['module_type'] == type)
        .map((row) => Map<String, dynamic>.from(row['payload'] as Map))
        .toList();
    final programs = records('program');
    final rewards = records('reward');
    final campaigns = records('campaign');
    data.programs = programs.map(LoyaltyProgram.fromJson).toList();
    data.rewards = rewards.map(Reward.fromJson).toList();
    data.campaigns = campaigns.map(Campaign.fromJson).toList();
    // loyalty_cards es la fuente operativa que consumen Apple Wallet,
    // Google Wallet, la PWA y el escáner. Se superpone al snapshot para que
    // una edición recién aplicada nunca vuelva a mostrar una meta antigua.
    final cardRows = await _client
        .from('loyalty_cards')
        .select(
          'id,name,card_kind,program_type,earning_rate,goal,active,color_hex,background_image_path,stamp_icon,wallet_layout,welcome_message,stamp_notification_message,completion_message,reward_milestones,expires_at',
        )
        .eq('business_id', businessId);
    for (final row in cardRows) {
      final id = row['id'] as String;
      final index = data.programs.indexWhere((item) => item.id == id);
      final previous = index < 0 ? null : data.programs[index];
      final remote = LoyaltyProgram(
        id: id,
        name: row['name'] as String? ?? previous?.name ?? 'Tarjeta',
        type: ProgramType.values.firstWhere(
          (value) => value.name == row['program_type'],
          orElse: () => previous?.type ?? ProgramType.stamps,
        ),
        earningRate: (row['earning_rate'] as num?)?.toInt() ?? 1,
        goal: (row['goal'] as num?)?.toInt() ?? previous?.goal ?? 1,
        active: row['active'] as bool? ?? true,
        cardKind:
            row['card_kind'] as String? ?? previous?.cardKind ?? 'Fidelización',
        colorHex: row['color_hex'] as String? ?? previous?.colorHex ?? '',
        backgroundImagePath:
            row['background_image_path'] as String? ??
            previous?.backgroundImagePath ??
            '',
        stampIcon:
            row['stamp_icon'] as String? ?? previous?.stampIcon ?? 'coffee',
        walletLayout:
            row['wallet_layout'] as String? ??
            previous?.walletLayout ??
            'poster',
        welcomeMessage:
            row['welcome_message'] as String? ??
            previous?.welcomeMessage ??
            '¡Bienvenido! Nos alegra tenerte aquí.',
        stampNotificationMessage:
            row['stamp_notification_message'] as String? ??
            previous?.stampNotificationMessage ??
            '¡Ya tienes {sellos} sellos! Sigue así.',
        completionMessage:
            row['completion_message'] as String? ??
            previous?.completionMessage ??
            '🎉 ¡Completaste tu tarjeta! Tu recompensa está lista.',
        expiresAt: DateTime.tryParse(row['expires_at'] as String? ?? ''),
        tiers: previous?.tiers,
        stampMilestones: (row['reward_milestones'] as List? ?? const [])
            .map(
              (item) => StampMilestone.fromJson(
                Map<String, dynamic>.from(item as Map),
              ),
            )
            .toList(),
      );
      if (index < 0) {
        data.programs.add(remote);
      } else {
        data.programs[index] = remote;
      }
    }
    final activityRows = await _client
        .from('loyalty_events')
        .select()
        .eq('business_id', businessId)
        .order('created_at', ascending: false);
    data.activities = activityRows
        .map(
          (row) => ActivityRecord(
            id: row['id'] as String,
            customerId: row['customer_id'] as String,
            description: row['description'] as String,
            createdAt:
                DateTime.tryParse(row['created_at'] as String? ?? '') ??
                DateTime.now(),
            pointsDelta: (row['points_delta'] as num?)?.toInt() ?? 0,
            eventType: row['event_type'] as String? ?? 'other',
            programId: row['program_id'] as String?,
            amountMinor: (row['amount_minor'] as num?)?.toInt() ?? 0,
            currency: row['currency'] as String? ?? 'BOB',
            metadata: Map<String, dynamic>.from(
              row['metadata'] as Map? ?? const <String, dynamic>{},
            ),
          ),
        )
        .toList();
    try {
      final redemptionRows = await _client
          .from('customer_reward_redemptions')
          .select('customer_id,reward_id')
          .eq('business_id', businessId);
      final redeemedByCustomer = <String, List<String>>{};
      for (final row in redemptionRows) {
        redeemedByCustomer
            .putIfAbsent(row['customer_id'] as String, () => <String>[])
            .add(row['reward_id'] as String);
      }
      for (final customer in data.customers) {
        customer.redeemedRewardIds =
            redeemedByCustomer[customer.id] ?? const [];
      }
    } on PostgrestException {
      // Compatibilidad mientras se aplica la migración de canjes únicos.
    }
    data.tiers.clear();
    data.challenges.clear();
    data.automations.clear();
    return data;
  }

  Future<void> save(AppData data) async {
    final userId = businessId;
    await _client.from('businesses').upsert({
      'id': userId,
      'owner_id': userId,
      'name': data.business.name.isEmpty ? 'Fideli' : data.business.name,
      'category': data.business.category,
      'color_hex': data.business.colorHex,
      'branches': data.business.branches,
      'wallet_icon_path': data.business.walletIconPath.isEmpty
          ? null
          : data.business.walletIconPath,
      'wallet_logo_path': data.business.walletLogoPath.isEmpty
          ? null
          : data.business.walletLogoPath,
      'locations': data.business.locations
          .take(10)
          .map((item) => item.toJson())
          .toList(),
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    });
    await _client.from('business_members').upsert({
      'business_id': userId,
      'user_id': userId,
      'role': 'owner',
    });
    await _syncPrograms(data.programs, userId);
    final updates = <Future<void>>[
      _client.from('app_snapshots').upsert({
        'business_id': userId,
        'owner_id': userId,
        'payload': data.toJson(),
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }),
      _syncModule(
        'reward',
        data.rewards.map((item) => MapEntry(item.id, item.toJson())),
        userId,
      ),
      _syncModule(
        'campaign',
        data.campaigns.map((item) => MapEntry(item.id, item.toJson())),
        userId,
      ),
    ];

    if (data.customers.isNotEmpty) {
      updates.add(
        _client
            .from('customers')
            .upsert(
              data.customers
                  .map(
                    (customer) => {
                      'id': customer.id,
                      'business_id': userId,
                      'name': customer.name,
                      'phone': customer.phone,
                      'phone_normalized': customer.phone.replaceAll(
                        RegExp(r'\D'),
                        '',
                      ),
                      'email': customer.email,
                      'birth_date': customer.birthDate
                          ?.toIso8601String()
                          .split('T')
                          .first,
                      'points': customer.points,
                      'stamps': customer.stamps,
                      'visits': customer.visits,
                      'tier': customer.tier,
                      'referral_code': customer.referralCode,
                      'card_balances': customer.cardBalances.map(
                        (key, value) => MapEntry(key, value.toJson()),
                      ),
                      'joined_at': customer.joinedAt.toUtc().toIso8601String(),
                      'updated_at': DateTime.now().toUtc().toIso8601String(),
                    },
                  )
                  .toList(),
              onConflict: 'business_id,id',
            ),
      );
    }

    if (data.activities.isNotEmpty) {
      updates.add(
        _client
            .from('loyalty_events')
            .upsert(
              data.activities
                  .map(
                    (activity) => {
                      'id': activity.id,
                      'business_id': userId,
                      'customer_id': activity.customerId,
                      'description': activity.description,
                      'points_delta': activity.pointsDelta,
                      'event_type': activity.eventType,
                      'program_id': activity.programId,
                      'amount_minor': activity.amountMinor,
                      'currency': activity.currency,
                      'metadata': activity.metadata,
                      'created_at': activity.createdAt
                          .toUtc()
                          .toIso8601String(),
                    },
                  )
                  .toList(),
            ),
      );
    }
    await Future.wait(updates);
    try {
      final recentLimit = DateTime.now().subtract(const Duration(minutes: 2));
      final affectedCustomers = data.activities
          .where((activity) => activity.createdAt.isAfter(recentLimit))
          .map((activity) => activity.customerId)
          .toSet();
      await Future.wait(
        affectedCustomers.map(
          (customerId) => _client.rpc(
            'refresh_customer_intelligence',
            params: {'p_business_id': userId, 'p_customer_id': customerId},
          ),
        ),
      );
    } on PostgrestException {
      // La app sigue funcionando antes de aplicar la migración de inteligencia.
    }
  }

  Future<void> _loadCustomerIntelligence(AppData data) async {
    try {
      final results = await Future.wait([
        _client
            .from('customer_features')
            .select()
            .eq('business_id', businessId),
        _client
            .from('customer_segments')
            .select()
            .eq('business_id', businessId),
      ]);
      final features = <String, Map<String, dynamic>>{
        for (final row in results[0])
          row['customer_id'].toString(): Map<String, dynamic>.from(row),
      };
      final segments = <String, Map<String, dynamic>>{
        for (final row in results[1])
          row['customer_id'].toString(): Map<String, dynamic>.from(row),
      };
      for (final customer in data.customers) {
        final feature = features[customer.id];
        final segment = segments[customer.id];
        if (feature == null && segment == null) continue;
        customer.intelligence = CustomerIntelligence.fromJson({
          ...?feature,
          ...?segment,
        });
      }
    } on PostgrestException {
      // Compatibilidad durante despliegues escalonados de la base de datos.
    }
  }

  Future<String> uploadWalletIcon({
    required Uint8List icon,
    required Uint8List icon2x,
    required Uint8List icon3x,
  }) async {
    final version = DateTime.now().microsecondsSinceEpoch;
    final folder = '$businessId/wallet/$version';
    const options = FileOptions(
      cacheControl: '31536000',
      upsert: false,
      contentType: 'image/png',
    );
    final bucket = _client.storage.from('business-assets');
    await Future.wait([
      bucket.uploadBinary('$folder/icon.png', icon, fileOptions: options),
      bucket.uploadBinary('$folder/icon@2x.png', icon2x, fileOptions: options),
      bucket.uploadBinary('$folder/icon@3x.png', icon3x, fileOptions: options),
    ]);
    return folder;
  }

  Future<String> uploadWalletLogo({
    required Uint8List logo,
    required Uint8List logo2x,
    required Uint8List logo3x,
  }) async {
    final version = DateTime.now().microsecondsSinceEpoch;
    final folder = '$businessId/logo/$version';
    const options = FileOptions(
      cacheControl: '31536000',
      upsert: false,
      contentType: 'image/png',
    );
    final bucket = _client.storage.from('business-assets');
    await Future.wait([
      bucket.uploadBinary('$folder/logo.png', logo, fileOptions: options),
      bucket.uploadBinary('$folder/logo@2x.png', logo2x, fileOptions: options),
      bucket.uploadBinary('$folder/logo@3x.png', logo3x, fileOptions: options),
    ]);
    return folder;
  }

  Future<void> deleteWalletIconFolder(String folder) async {
    if (folder.isEmpty) return;
    await _client.storage.from('business-assets').remove([
      '$folder/icon.png',
      '$folder/icon@2x.png',
      '$folder/icon@3x.png',
    ]);
  }

  Future<void> deleteWalletLogoFolder(String folder) async {
    if (folder.isEmpty) return;
    await _client.storage.from('business-assets').remove([
      '$folder/logo.png',
      '$folder/logo@2x.png',
      '$folder/logo@3x.png',
    ]);
  }

  Future<Uint8List?> downloadWalletIcon(String folder) async {
    if (folder.isEmpty) return null;
    try {
      return await _client.storage
          .from('business-assets')
          .download('$folder/icon@3x.png');
    } catch (_) {
      return null;
    }
  }

  Future<Uint8List?> downloadWalletLogo(String folder) async {
    if (folder.isEmpty) return null;
    try {
      return await _client.storage
          .from('business-assets')
          .download('$folder/logo@3x.png');
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, String>?> loadBusinessBranding() async {
    final row = await _client
        .from('businesses')
        .select('name,wallet_logo_path,wallet_icon_path')
        .eq('id', businessId)
        .maybeSingle();
    if (row == null) return null;
    return {
      'name': row['name'] as String? ?? '',
      'logoPath': row['wallet_logo_path'] as String? ?? '',
      'iconPath': row['wallet_icon_path'] as String? ?? '',
    };
  }

  Future<Uint8List?> downloadBusinessMark({
    required String logoPath,
    required String iconPath,
  }) async {
    final notificationIcon = await downloadWalletIcon(iconPath);
    if (notificationIcon != null) return notificationIcon;
    return downloadWalletLogo(logoPath);
  }

  Future<String> uploadCardBackground({
    required String programId,
    required Uint8List image,
    required Uint8List image2x,
  }) async {
    final version = DateTime.now().microsecondsSinceEpoch;
    final folder = '$businessId/cards/$programId/$version';
    const options = FileOptions(
      cacheControl: '31536000',
      upsert: false,
      contentType: 'image/png',
    );
    final bucket = _client.storage.from('business-assets');
    await Future.wait([
      bucket.uploadBinary('$folder/strip.png', image, fileOptions: options),
      bucket.uploadBinary(
        '$folder/strip@2x.png',
        image2x,
        fileOptions: options,
      ),
    ]);
    return folder;
  }

  Future<Uint8List?> downloadCardBackground(String folder) async {
    if (folder.isEmpty) return null;
    try {
      return await _client.storage
          .from('business-assets')
          .download('$folder/strip.png');
    } catch (_) {
      return null;
    }
  }

  Future<void> _syncPrograms(
    List<LoyaltyProgram> programs,
    String userId,
  ) async {
    if (programs.isNotEmpty) {
      await _client
          .from('loyalty_cards')
          .upsert(
            programs
                .map(
                  (program) => {
                    'id': program.id,
                    'business_id': userId,
                    'name': program.name,
                    'card_kind': program.cardKind,
                    'program_type': program.type.name,
                    'earning_rate': program.earningRate,
                    'goal': program.goal,
                    'active': program.active,
                    'color_hex': program.colorHex.isEmpty
                        ? null
                        : program.colorHex,
                    'background_image_path': program.backgroundImagePath.isEmpty
                        ? null
                        : program.backgroundImagePath,
                    'stamp_icon': program.stampIcon,
                    'wallet_layout': program.walletLayout,
                    'welcome_message': program.welcomeMessage,
                    'stamp_notification_message':
                        program.stampNotificationMessage,
                    'completion_message': program.completionMessage,
                    'reward_milestones': program.stampMilestones
                        .map((item) => item.toJson())
                        .toList(),
                    'expires_at': program.expiresAt?.toUtc().toIso8601String(),
                    'updated_at': DateTime.now().toUtc().toIso8601String(),
                  },
                )
                .toList(),
            onConflict: 'business_id,id',
          );
    }
    await _syncModule(
      'program',
      programs.map((item) => MapEntry(item.id, item.toJson())),
      userId,
    );
  }

  Future<void> _syncModule(
    String type,
    Iterable<MapEntry<String, Map<String, dynamic>>> entries,
    String userId,
  ) async {
    final values = entries.toList();
    final existing = await _client
        .from('module_records')
        .select('record_id')
        .eq('business_id', userId)
        .eq('module_type', type);
    final wanted = values.map((item) => item.key).toSet();
    final stale = existing
        .map((row) => row['record_id'] as String)
        .where((id) => !wanted.contains(id))
        .toList();
    if (stale.isNotEmpty) {
      await _client
          .from('module_records')
          .delete()
          .eq('business_id', userId)
          .eq('module_type', type)
          .inFilter('record_id', stale);
    }
    if (values.isNotEmpty) {
      await _client
          .from('module_records')
          .upsert(
            values
                .map(
                  (item) => {
                    'business_id': userId,
                    'module_type': type,
                    'record_id': item.key,
                    'payload': item.value,
                    'updated_at': DateTime.now().toUtc().toIso8601String(),
                  },
                )
                .toList(),
            onConflict: 'business_id,module_type,record_id',
          );
    }
  }
}

int _leastUsedAvatarIndex(List<int> counts, String seed) {
  final minimum = counts.reduce((left, right) => left < right ? left : right);
  final available = <int>[
    for (var index = 0; index < counts.length; index++)
      if (counts[index] == minimum) index,
  ];
  final seedValue = seed.codeUnits.fold<int>(0, (sum, unit) => sum + unit);
  return available[seedValue % available.length];
}
