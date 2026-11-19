enum CustomerSegment {
  newCustomer('NEW', 'Nuevo'),
  frequent('FREQUENT', 'Frecuente'),
  regular('REGULAR', 'Regular'),
  occasional('OCCASIONAL', 'Ocasional'),
  atRisk('AT_RISK', 'En riesgo'),
  inactive('INACTIVE', 'Inactivo'),
  recovered('RECOVERED', 'Recuperado');

  const CustomerSegment(this.code, this.label);

  final String code;
  final String label;

  static CustomerSegment fromCode(String? value) => values.firstWhere(
    (segment) => segment.code == value,
    orElse: () => CustomerSegment.newCustomer,
  );
}

/// The three customer states shown to merchants. The detailed segment remains
/// available internally so the cadence model can keep its existing behavior.
enum CustomerAttention {
  newCustomer('Nuevo'),
  concerning('Preocupante'),
  risk('Riesgo');

  const CustomerAttention(this.label);

  final String label;

  static CustomerAttention? fromSegment(CustomerSegment segment) => switch (
    segment
  ) {
    CustomerSegment.newCustomer => CustomerAttention.newCustomer,
    CustomerSegment.atRisk => CustomerAttention.concerning,
    CustomerSegment.inactive => CustomerAttention.risk,
    CustomerSegment.frequent ||
    CustomerSegment.regular ||
    CustomerSegment.occasional ||
    CustomerSegment.recovered => null,
  };

  String get explanation => switch (this) {
    CustomerAttention.newCustomer =>
      'Todavía está construyendo su historial.',
    CustomerAttention.concerning =>
      'Se está atrasando respecto a su ritmo habitual.',
    CustomerAttention.risk =>
      'Superó ampliamente el tiempo que suele tardar en volver.',
  };
}

class CustomerIntelligence {
  const CustomerIntelligence({
    required this.segment,
    this.previousSegment,
    this.totalVisits = 0,
    this.totalTransactions = 0,
    this.totalSpendMinor = 0,
    this.averageTicketMinor = 0,
    this.daysSinceLastVisit,
    this.visits30d = 0,
    this.visits90d = 0,
    this.averageVisitIntervalDays,
    this.expectedVisitIntervalDays,
    this.expectedNextVisitAt,
    this.delayRatio,
    this.frequencyChange = 0,
    this.visitTrend = 'stable',
    this.spendTrend = 'stable',
    this.riskScore = 0,
    this.valueScore = 0,
    this.reasonCodes = const [],
    this.explanation = '',
    this.updatedAt,
  });

  final CustomerSegment segment;
  final CustomerSegment? previousSegment;
  final int totalVisits;
  final int totalTransactions;
  final int totalSpendMinor;
  final int averageTicketMinor;
  final int? daysSinceLastVisit;
  final int visits30d;
  final int visits90d;
  final double? averageVisitIntervalDays;
  final double? expectedVisitIntervalDays;
  final DateTime? expectedNextVisitAt;
  final double? delayRatio;
  final double frequencyChange;
  final String visitTrend;
  final String spendTrend;
  final double riskScore;
  final double valueScore;
  final List<String> reasonCodes;
  final String explanation;
  final DateTime? updatedAt;

  CustomerAttention? get attention => CustomerAttention.fromSegment(segment);

  String? get statusLabel => attention?.label;

  String get statusExplanation =>
      attention?.explanation ?? 'Su frecuencia se mantiene dentro de lo habitual.';

  String get valueLabel => switch (valueScore) {
    >= 0.75 => 'Valor alto',
    >= 0.4 => 'Valor medio',
    _ => 'Valor inicial',
  };

  Map<String, dynamic> toJson() => {
    'segment': segment.code,
    'previousSegment': previousSegment?.code,
    'totalVisits': totalVisits,
    'totalTransactions': totalTransactions,
    'totalSpendMinor': totalSpendMinor,
    'averageTicketMinor': averageTicketMinor,
    'daysSinceLastVisit': daysSinceLastVisit,
    'visits30d': visits30d,
    'visits90d': visits90d,
    'averageVisitIntervalDays': averageVisitIntervalDays,
    'expectedVisitIntervalDays': expectedVisitIntervalDays,
    'expectedNextVisitAt': expectedNextVisitAt?.toIso8601String(),
    'delayRatio': delayRatio,
    'frequencyChange': frequencyChange,
    'visitTrend': visitTrend,
    'spendTrend': spendTrend,
    'riskScore': riskScore,
    'valueScore': valueScore,
    'reasonCodes': reasonCodes,
    'explanation': explanation,
    'updatedAt': updatedAt?.toIso8601String(),
  };

  factory CustomerIntelligence.fromJson(Map<String, dynamic> json) {
    double? number(String key) => (json[key] as num?)?.toDouble();
    return CustomerIntelligence(
      segment: CustomerSegment.fromCode(
        (json['segment'] ?? json['segment_code'])?.toString(),
      ),
      previousSegment:
          json['previousSegment'] == null && json['previous_segment'] == null
          ? null
          : CustomerSegment.fromCode(
              (json['previousSegment'] ?? json['previous_segment'])?.toString(),
            ),
      totalVisits:
          (json['totalVisits'] ?? json['total_visits'] as num?)?.toInt() ?? 0,
      totalTransactions:
          (json['totalTransactions'] ?? json['total_transactions'] as num?)
              ?.toInt() ??
          0,
      totalSpendMinor:
          (json['totalSpendMinor'] ?? json['total_spend_minor'] as num?)
              ?.toInt() ??
          0,
      averageTicketMinor:
          (json['averageTicketMinor'] ?? json['average_ticket_minor'] as num?)
              ?.toInt() ??
          0,
      daysSinceLastVisit:
          (json['daysSinceLastVisit'] ?? json['days_since_last_visit'] as num?)
              ?.toInt(),
      visits30d:
          (json['visits30d'] ?? json['visits_30d'] as num?)?.toInt() ?? 0,
      visits90d:
          (json['visits90d'] ?? json['visits_90d'] as num?)?.toInt() ?? 0,
      averageVisitIntervalDays:
          number('averageVisitIntervalDays') ??
          number('average_visit_interval_days'),
      expectedVisitIntervalDays:
          number('expectedVisitIntervalDays') ??
          number('expected_visit_interval_days'),
      expectedNextVisitAt: DateTime.tryParse(
        (json['expectedNextVisitAt'] ?? json['expected_next_visit_at'])
                ?.toString() ??
            '',
      ),
      delayRatio: number('delayRatio') ?? number('delay_ratio'),
      frequencyChange:
          number('frequencyChange') ?? number('frequency_change') ?? 0,
      visitTrend:
          (json['visitTrend'] ?? json['visit_trend'])?.toString() ?? 'stable',
      spendTrend:
          (json['spendTrend'] ?? json['spend_trend'])?.toString() ?? 'stable',
      riskScore: number('riskScore') ?? number('risk_score') ?? 0,
      valueScore: number('valueScore') ?? number('value_score') ?? 0,
      reasonCodes: List<String>.from(
        (json['reasonCodes'] ?? json['reason_codes']) as List? ?? const [],
      ),
      explanation: json['explanation']?.toString() ?? '',
      updatedAt: DateTime.tryParse(
        (json['updatedAt'] ?? json['updated_at'])?.toString() ?? '',
      ),
    );
  }
}
