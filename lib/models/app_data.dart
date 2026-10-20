import 'dart:convert';

import 'customer_intelligence.dart';

String newId(String prefix) =>
    '$prefix-${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}';

enum ProgramType { points, stamps, visits, membership, hybrid }

class StampMilestone {
  StampMilestone({
    required this.id,
    required this.stamp,
    required this.reward,
    required this.message,
  });

  String id;
  int stamp;
  String reward;
  String message;

  Map<String, dynamic> toJson() => {
    'id': id,
    'stamp': stamp,
    'reward': reward,
    'message': message,
  };

  factory StampMilestone.fromJson(Map<String, dynamic> json) => StampMilestone(
    id: json['id'] as String? ?? '',
    stamp: json['stamp'] as int? ?? 1,
    reward: json['reward'] as String? ?? '',
    message: json['message'] as String? ?? '',
  );
}

extension ProgramTypeLabel on ProgramType {
  String get label => switch (this) {
    ProgramType.points => 'Puntos',
    ProgramType.stamps => 'Sellos',
    ProgramType.visits => 'Visitas',
    ProgramType.membership => 'Membresía',
    ProgramType.hybrid => 'Híbrido',
  };
}

class BusinessLocation {
  BusinessLocation({
    required this.id,
    this.name = '',
    this.address = '',
    required this.latitude,
    required this.longitude,
    this.radiusMeters = 180,
    this.message = '',
  });

  String id;
  String name;
  String address;
  double latitude;
  double longitude;
  int radiusMeters;
  String message;

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'address': address,
    'latitude': latitude,
    'longitude': longitude,
    'radiusMeters': radiusMeters,
    'message': message,
  };

  factory BusinessLocation.fromJson(Map<String, dynamic> json) =>
      BusinessLocation(
        id: json['id'] as String? ?? '',
        name: json['name'] as String? ?? '',
        address: json['address'] as String? ?? '',
        latitude: (json['latitude'] as num?)?.toDouble() ?? 0,
        longitude: (json['longitude'] as num?)?.toDouble() ?? 0,
        radiusMeters: (json['radiusMeters'] as num?)?.toInt() ?? 180,
        message: json['message'] as String? ?? '',
      );
}

class BusinessProfile {
  BusinessProfile({
    this.name = '',
    this.category = '',
    this.colorHex = '#9E483F',
    this.branches = const [],
    this.backendUrl = '',
    this.walletIconPath = '',
    this.walletLogoPath = '',
    this.publicSlug = '',
    this.locations = const [],
    this.onboarded = false,
  });

  String name;
  String category;
  String colorHex;
  List<String> branches;
  String backendUrl;
  String walletIconPath;
  String walletLogoPath;
  String publicSlug;
  List<BusinessLocation> locations;
  bool onboarded;

  Map<String, dynamic> toJson() => {
    'name': name,
    'category': category,
    'colorHex': colorHex,
    'branches': branches,
    'backendUrl': backendUrl,
    'walletIconPath': walletIconPath,
    'walletLogoPath': walletLogoPath,
    'publicSlug': publicSlug,
    'locations': locations.map((item) => item.toJson()).toList(),
    'onboarded': onboarded,
  };

  factory BusinessProfile.fromJson(
    Map<String, dynamic> json,
  ) => BusinessProfile(
    name: json['name'] as String? ?? '',
    category: json['category'] as String? ?? '',
    colorHex: json['colorHex'] as String? ?? '#9E483F',
    branches: List<String>.from(json['branches'] as List? ?? const []),
    backendUrl: json['backendUrl'] as String? ?? '',
    walletIconPath: json['walletIconPath'] as String? ?? '',
    walletLogoPath: json['walletLogoPath'] as String? ?? '',
    publicSlug: json['publicSlug'] as String? ?? '',
    locations: (json['locations'] as List? ?? const [])
        .map(
          (item) =>
              BusinessLocation.fromJson(Map<String, dynamic>.from(item as Map)),
        )
        .toList(),
    onboarded: json['onboarded'] as bool? ?? false,
  );
}

class LoyaltyProgram {
  LoyaltyProgram({
    required this.id,
    required this.name,
    required this.type,
    this.earningRate = 1,
    this.goal = 10,
    this.active = true,
    this.cardKind = 'Fidelización',
    this.colorHex = '',
    this.backgroundImagePath = '',
    this.stampIcon = 'coffee',
    this.walletLayout = 'poster',
    this.welcomeMessage = '¡Bienvenido! Nos alegra tenerte aquí.',
    this.stampNotificationMessage = '¡Ya tienes {sellos} sellos! Sigue así.',
    this.completionMessage =
        '🎉 ¡Completaste tu tarjeta! Tu recompensa está lista.',
    this.expiresAt,
    List<TierRule>? tiers,
    List<StampMilestone>? stampMilestones,
  }) : tiers = tiers ?? [],
       stampMilestones = stampMilestones ?? [];

  String id;
  String name;
  ProgramType type;
  int earningRate;
  int goal;
  bool active;
  String cardKind;
  String colorHex;
  String backgroundImagePath;
  String stampIcon;
  String walletLayout;
  String welcomeMessage;
  String stampNotificationMessage;
  String completionMessage;
  DateTime? expiresAt;
  List<TierRule> tiers;
  List<StampMilestone> stampMilestones;

  bool get isExpired =>
      expiresAt != null && !expiresAt!.isAfter(DateTime.now());

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'type': type.name,
    'earningRate': earningRate,
    'goal': goal,
    'active': active,
    'cardKind': cardKind,
    'colorHex': colorHex,
    'backgroundImagePath': backgroundImagePath,
    'stampIcon': stampIcon,
    'walletLayout': walletLayout,
    'welcomeMessage': welcomeMessage,
    'stampNotificationMessage': stampNotificationMessage,
    'completionMessage': completionMessage,
    'expiresAt': expiresAt?.toIso8601String(),
    'tiers': tiers.map((value) => value.toJson()).toList(),
    'stampMilestones': stampMilestones.map((value) => value.toJson()).toList(),
  };

  factory LoyaltyProgram.fromJson(Map<String, dynamic> json) => LoyaltyProgram(
    id: json['id'] as String,
    name: json['name'] as String,
    type: ProgramType.values.firstWhere(
      (value) => value.name == json['type'],
      orElse: () => ProgramType.points,
    ),
    earningRate: json['earningRate'] as int? ?? 1,
    goal: json['goal'] as int? ?? 10,
    active: json['active'] as bool? ?? true,
    cardKind: json['cardKind'] as String? ?? 'Fidelización',
    colorHex: json['colorHex'] as String? ?? '',
    backgroundImagePath: json['backgroundImagePath'] as String? ?? '',
    stampIcon: json['stampIcon'] as String? ?? 'coffee',
    walletLayout: json['walletLayout'] as String? ?? 'poster',
    welcomeMessage:
        json['welcomeMessage'] as String? ??
        '¡Bienvenido! Nos alegra tenerte aquí.',
    stampNotificationMessage:
        json['stampNotificationMessage'] as String? ??
        '¡Ya tienes {sellos} sellos! Sigue así.',
    completionMessage:
        json['completionMessage'] as String? ??
        '🎉 ¡Completaste tu tarjeta! Tu recompensa está lista.',
    expiresAt: DateTime.tryParse(json['expiresAt'] as String? ?? ''),
    tiers: (json['tiers'] as List? ?? const [])
        .map(
          (item) => TierRule.fromJson(Map<String, dynamic>.from(item as Map)),
        )
        .toList(),
    stampMilestones: (json['stampMilestones'] as List? ?? const [])
        .map(
          (item) =>
              StampMilestone.fromJson(Map<String, dynamic>.from(item as Map)),
        )
        .toList(),
  );
}

class CardBalance {
  CardBalance({this.points = 0, this.stamps = 0, this.visits = 0});

  int points;
  int stamps;
  int visits;

  Map<String, dynamic> toJson() => {
    'points': points,
    'stamps': stamps,
    'visits': visits,
  };

  factory CardBalance.fromJson(Map<String, dynamic> json) => CardBalance(
    points: json['points'] as int? ?? 0,
    stamps: json['stamps'] as int? ?? 0,
    visits: json['visits'] as int? ?? 0,
  );
}

class Customer {
  Customer({
    required this.id,
    required this.name,
    this.phone = '',
    this.email = '',
    this.birthDate,
    this.points = 0,
    this.stamps = 0,
    this.visits = 0,
    this.tier = '',
    this.avatarIndex = -1,
    required this.referralCode,
    required this.joinedAt,
    this.unlockedRewardIds = const [],
    this.redeemedRewardIds = const [],
    this.intelligence,
    Map<String, CardBalance>? cardBalances,
  }) : cardBalances = cardBalances ?? {};

  String id;
  String name;
  String phone;
  String email;
  DateTime? birthDate;
  int points;
  int stamps;
  int visits;
  String tier;
  int avatarIndex;
  String referralCode;
  DateTime joinedAt;
  List<String> unlockedRewardIds;
  List<String> redeemedRewardIds;
  CustomerIntelligence? intelligence;
  Map<String, CardBalance> cardBalances;

  CardBalance balanceFor(String programId) =>
      cardBalances.putIfAbsent(programId, CardBalance.new);

  String get qrPayload => 'fideli://customer/$id?ref=$referralCode';

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'phone': phone,
    'email': email,
    'birthDate': birthDate?.toIso8601String(),
    'points': points,
    'stamps': stamps,
    'visits': visits,
    'tier': tier,
    'avatarIndex': avatarIndex,
    'referralCode': referralCode,
    'joinedAt': joinedAt.toIso8601String(),
    'unlockedRewardIds': unlockedRewardIds,
    'redeemedRewardIds': redeemedRewardIds,
    'intelligence': intelligence?.toJson(),
    'cardBalances': cardBalances.map(
      (key, value) => MapEntry(key, value.toJson()),
    ),
  };

  factory Customer.fromJson(Map<String, dynamic> json) => Customer(
    id: json['id'] as String,
    name: json['name'] as String,
    phone: json['phone'] as String? ?? '',
    email: json['email'] as String? ?? '',
    birthDate: DateTime.tryParse(json['birthDate'] as String? ?? ''),
    points: json['points'] as int? ?? 0,
    stamps: json['stamps'] as int? ?? 0,
    visits: json['visits'] as int? ?? 0,
    tier: json['tier'] as String? ?? '',
    avatarIndex: (json['avatarIndex'] as num?)?.toInt() ?? -1,
    referralCode: json['referralCode'] as String,
    joinedAt:
        DateTime.tryParse(json['joinedAt'] as String? ?? '') ?? DateTime.now(),
    unlockedRewardIds: List<String>.from(
      json['unlockedRewardIds'] as List? ?? const [],
    ),
    redeemedRewardIds: List<String>.from(
      json['redeemedRewardIds'] as List? ?? const [],
    ),
    intelligence: json['intelligence'] is Map
        ? CustomerIntelligence.fromJson(
            Map<String, dynamic>.from(json['intelligence'] as Map),
          )
        : null,
    cardBalances: (json['cardBalances'] as Map? ?? const <String, dynamic>{})
        .map(
          (key, value) => MapEntry(
            key as String,
            CardBalance.fromJson(Map<String, dynamic>.from(value as Map)),
          ),
        ),
  );
}

class Reward {
  Reward({
    required this.id,
    required this.name,
    this.programId = '',
    this.pointsCost = 0,
    this.stampsCost = 0,
    this.active = true,
    this.redemptions = 0,
  });

  String id;
  String name;
  String programId;
  int pointsCost;
  int stampsCost;
  bool active;
  int redemptions;

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'programId': programId,
    'pointsCost': pointsCost,
    'stampsCost': stampsCost,
    'active': active,
    'redemptions': redemptions,
  };

  factory Reward.fromJson(Map<String, dynamic> json) => Reward(
    id: json['id'] as String,
    name: json['name'] as String,
    programId: json['programId'] as String? ?? '',
    pointsCost: json['pointsCost'] as int? ?? 0,
    stampsCost: json['stampsCost'] as int? ?? 0,
    active: json['active'] as bool? ?? true,
    redemptions: json['redemptions'] as int? ?? 0,
  );
}

class TierRule {
  TierRule({required this.id, required this.name, required this.threshold});
  String id;
  String name;
  int threshold;

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'threshold': threshold,
  };
  factory TierRule.fromJson(Map<String, dynamic> json) => TierRule(
    id: json['id'] as String,
    name: json['name'] as String,
    threshold: json['threshold'] as int? ?? 0,
  );
}

class Challenge {
  Challenge({
    required this.id,
    required this.name,
    this.targetVisits = 3,
    this.bonusPoints = 50,
    this.active = true,
  });
  String id;
  String name;
  int targetVisits;
  int bonusPoints;
  bool active;

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'targetVisits': targetVisits,
    'bonusPoints': bonusPoints,
    'active': active,
  };
  factory Challenge.fromJson(Map<String, dynamic> json) => Challenge(
    id: json['id'] as String,
    name: json['name'] as String,
    targetVisits: json['targetVisits'] as int? ?? 3,
    bonusPoints: json['bonusPoints'] as int? ?? 50,
    active: json['active'] as bool? ?? true,
  );
}

class Campaign {
  Campaign({
    required this.id,
    required this.name,
    required this.message,
    this.notificationTitle = '',
    this.audience = 'Todos',
    this.targetCustomerId,
    this.targetCustomerName,
    this.linkUrl,
    this.sentAt,
  });
  String id;
  String name;
  String message;
  String notificationTitle;
  String audience;
  String? targetCustomerId;
  String? targetCustomerName;
  String? linkUrl;
  DateTime? sentAt;

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'message': message,
    'notificationTitle': notificationTitle,
    'audience': audience,
    'targetCustomerId': targetCustomerId,
    'targetCustomerName': targetCustomerName,
    'linkUrl': linkUrl,
    'sentAt': sentAt?.toIso8601String(),
  };
  factory Campaign.fromJson(Map<String, dynamic> json) => Campaign(
    id: json['id'] as String,
    name: json['name'] as String,
    message: json['message'] as String? ?? '',
    notificationTitle:
        (json['notificationTitle'] as String?)?.trim().isNotEmpty == true
        ? json['notificationTitle'] as String
        : '',
    audience: json['audience'] as String? ?? 'Todos',
    targetCustomerId: json['targetCustomerId'] as String?,
    targetCustomerName: json['targetCustomerName'] as String?,
    linkUrl: json['linkUrl'] as String?,
    sentAt: DateTime.tryParse(json['sentAt'] as String? ?? ''),
  );
}

class AutomationRule {
  AutomationRule({
    required this.id,
    required this.event,
    required this.action,
    this.active = true,
  });
  String id;
  String event;
  String action;
  bool active;

  Map<String, dynamic> toJson() => {
    'id': id,
    'event': event,
    'action': action,
    'active': active,
  };
  factory AutomationRule.fromJson(Map<String, dynamic> json) => AutomationRule(
    id: json['id'] as String,
    event: json['event'] as String,
    action: json['action'] as String,
    active: json['active'] as bool? ?? true,
  );
}

class ActivityRecord {
  ActivityRecord({
    required this.id,
    required this.customerId,
    required this.description,
    required this.createdAt,
    this.pointsDelta = 0,
    this.eventType = 'other',
    this.programId,
    this.amountMinor = 0,
    this.currency = 'BOB',
    this.metadata = const {},
  });
  String id;
  String customerId;
  String description;
  DateTime createdAt;
  int pointsDelta;
  String eventType;
  String? programId;
  int amountMinor;
  String currency;
  Map<String, dynamic> metadata;

  Map<String, dynamic> toJson() => {
    'id': id,
    'customerId': customerId,
    'description': description,
    'createdAt': createdAt.toIso8601String(),
    'pointsDelta': pointsDelta,
    'eventType': eventType,
    'programId': programId,
    'amountMinor': amountMinor,
    'currency': currency,
    'metadata': metadata,
  };
  factory ActivityRecord.fromJson(Map<String, dynamic> json) => ActivityRecord(
    id: json['id'] as String,
    customerId: json['customerId'] as String,
    description: json['description'] as String,
    createdAt:
        DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.now(),
    pointsDelta: json['pointsDelta'] as int? ?? 0,
    eventType: json['eventType'] as String? ?? 'other',
    programId: json['programId'] as String?,
    amountMinor: (json['amountMinor'] as num?)?.toInt() ?? 0,
    currency: json['currency'] as String? ?? 'BOB',
    metadata: Map<String, dynamic>.from(
      json['metadata'] as Map? ?? const <String, dynamic>{},
    ),
  );
}

class WalletCardTemplate {
  WalletCardTemplate({
    this.colorHex = '',
    this.backgroundImagePath = '',
    this.stampIcon = 'coffee',
    this.walletLayout = 'poster',
  });

  String colorHex;
  String backgroundImagePath;
  String stampIcon;
  String walletLayout;

  Map<String, dynamic> toJson() => {
    'colorHex': colorHex,
    'backgroundImagePath': backgroundImagePath,
    'stampIcon': stampIcon,
    'walletLayout': walletLayout,
  };

  factory WalletCardTemplate.fromJson(Map<String, dynamic> json) =>
      WalletCardTemplate(
        colorHex: json['colorHex'] as String? ?? '',
        backgroundImagePath: json['backgroundImagePath'] as String? ?? '',
        stampIcon: json['stampIcon'] as String? ?? 'coffee',
        walletLayout: json['walletLayout'] as String? ?? 'poster',
      );
}

class WalletSettings {
  WalletSettings({
    this.passTypeIdentifier = 'pass.app.fideli.loyalty',
    this.teamIdentifier = 'F34F83K3QZ',
    this.googleIssuerId = '',
    this.googleClassSuffix = 'fideli_loyalty',
    this.demoMode = false,
    Map<String, WalletCardTemplate>? cardTemplates,
  }) : cardTemplates = cardTemplates ?? {};
  String passTypeIdentifier;
  String teamIdentifier;
  String googleIssuerId;
  String googleClassSuffix;
  bool demoMode;
  Map<String, WalletCardTemplate> cardTemplates;

  WalletCardTemplate templateFor(String type) => cardTemplates.putIfAbsent(
    type,
    () => WalletCardTemplate(
      stampIcon: switch (type) {
        'gift' => 'gift',
        'membership' => 'check',
        'points' => 'star',
        _ => 'coffee',
      },
    ),
  );

  Map<String, dynamic> toJson() => {
    'passTypeIdentifier': passTypeIdentifier,
    'teamIdentifier': teamIdentifier,
    'googleIssuerId': googleIssuerId,
    'googleClassSuffix': googleClassSuffix,
    'demoMode': demoMode,
    'cardTemplates': cardTemplates.map(
      (key, value) => MapEntry(key, value.toJson()),
    ),
  };
  factory WalletSettings.fromJson(Map<String, dynamic> json) => WalletSettings(
    passTypeIdentifier:
        (json['passTypeIdentifier'] as String?)?.isNotEmpty == true
        ? json['passTypeIdentifier'] as String
        : 'pass.app.fideli.loyalty',
    teamIdentifier: (json['teamIdentifier'] as String?)?.isNotEmpty == true
        ? json['teamIdentifier'] as String
        : 'F34F83K3QZ',
    googleIssuerId: json['googleIssuerId'] as String? ?? '',
    googleClassSuffix: json['googleClassSuffix'] as String? ?? 'fideli_loyalty',
    demoMode: json['demoMode'] as bool? ?? false,
    cardTemplates: Map.fromEntries(
      Map<String, dynamic>.from(json['cardTemplates'] as Map? ?? const {})
          .entries
          .where((entry) => entry.key != 'event')
          .map(
            (entry) => MapEntry(
              entry.key,
              WalletCardTemplate.fromJson(
                Map<String, dynamic>.from(entry.value as Map),
              ),
            ),
          ),
    ),
  );
}

class AppData {
  AppData({
    required this.schemaVersion,
    required this.business,
    required this.wallet,
    required this.programs,
    required this.customers,
    required this.rewards,
    required this.tiers,
    required this.challenges,
    required this.campaigns,
    required this.automations,
    required this.activities,
  });

  int schemaVersion;
  BusinessProfile business;
  WalletSettings wallet;
  List<LoyaltyProgram> programs;
  List<Customer> customers;
  List<Reward> rewards;
  List<TierRule> tiers;
  List<Challenge> challenges;
  List<Campaign> campaigns;
  List<AutomationRule> automations;
  List<ActivityRecord> activities;

  List<LoyaltyProgram> activeProgramsForCustomer(Customer customer) => programs
      .where(
        (program) =>
            program.active &&
            !program.isExpired &&
            customer.cardBalances.containsKey(program.id),
      )
      .toList();

  factory AppData.initial() => AppData(
    schemaVersion: 10,
    business: BusinessProfile(),
    wallet: WalletSettings(),
    programs: [],
    customers: [],
    rewards: [],
    tiers: [],
    challenges: [],
    campaigns: [],
    automations: [],
    activities: [],
  );

  Map<String, dynamic> toJson() => {
    'schemaVersion': schemaVersion,
    'business': business.toJson(),
    'wallet': wallet.toJson(),
    'programs': programs.map((value) => value.toJson()).toList(),
    'customers': customers.map((value) => value.toJson()).toList(),
    'rewards': rewards.map((value) => value.toJson()).toList(),
    'tiers': tiers.map((value) => value.toJson()).toList(),
    'challenges': challenges.map((value) => value.toJson()).toList(),
    'campaigns': campaigns.map((value) => value.toJson()).toList(),
    'automations': automations.map((value) => value.toJson()).toList(),
    'activities': activities.map((value) => value.toJson()).toList(),
  };

  String encode() => jsonEncode(toJson());

  factory AppData.decode(String source) {
    final json = jsonDecode(source) as Map<String, dynamic>;
    List<T> listOf<T>(String key, T Function(Map<String, dynamic>) decode) =>
        (json[key] as List? ?? const [])
            .map((item) => decode(Map<String, dynamic>.from(item as Map)))
            .toList();
    return AppData(
      schemaVersion: json['schemaVersion'] as int? ?? 1,
      business: BusinessProfile.fromJson(
        Map<String, dynamic>.from(json['business'] as Map? ?? const {}),
      ),
      wallet: WalletSettings.fromJson(
        Map<String, dynamic>.from(json['wallet'] as Map? ?? const {}),
      ),
      programs: listOf('programs', LoyaltyProgram.fromJson),
      customers: listOf('customers', Customer.fromJson),
      rewards: listOf('rewards', Reward.fromJson),
      tiers: listOf('tiers', TierRule.fromJson),
      challenges: listOf('challenges', Challenge.fromJson),
      campaigns: listOf('campaigns', Campaign.fromJson),
      automations: listOf('automations', AutomationRule.fromJson),
      activities: listOf('activities', ActivityRecord.fromJson),
    );
  }
}
