import 'package:flutter/material.dart';

import '../models/app_data.dart';
import '../services/cloud_store.dart';
import '../services/wallet_service.dart';
import 'campaigns_screen.dart';
import '../state/app_scope.dart';
import '../theme/fideli_theme.dart';
import '../widgets/common.dart';
import '../widgets/customer_avatar.dart';

class RewardsScreen extends StatefulWidget {
  const RewardsScreen({super.key});

  @override
  State<RewardsScreen> createState() => _RewardsScreenState();
}

class _RewardsScreenState extends State<RewardsScreen> {
  List<Map<String, dynamic>> _claims = [];
  bool _loading = true;
  String? _error;
  String? _claimingId;
  bool _showBirthdays = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _loadClaims();
    });
  }

  Future<void> _loadClaims() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final cloud = CloudStore.instance;
      if (cloud == null) throw StateError('Cloud service unavailable');
      final sync = await WalletService().syncRewardClaims(
        AppScope.of(context).data.business,
      );
      if (!sync.ok) throw StateError(sync.message);
      final claims = await cloud.loadPendingRewardClaims();
      if (!mounted) return;
      setState(() {
        _claims = claims;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error =
            'No pudimos cargar los premios pendientes. Intenta actualizar.';
      });
    }
  }

  Future<void> _markClaimed(Map<String, dynamic> claim) async {
    final key = '${claim['customer_id']}:${claim['reward_id']}';
    setState(() => _claimingId = key);
    final state = AppScope.of(context);
    final result = await WalletService().markRewardClaimed(
      state.data.business,
      customerId: claim['customer_id'] as String,
      rewardId: claim['reward_id'] as String,
    );
    if (!mounted) return;
    setState(() => _claimingId = null);
    showMessage(context, result.message);
    if (result.ok) await _loadClaims();
  }

  String _earnedLabel(Object? raw) {
    final date = DateTime.tryParse(raw?.toString() ?? '')?.toLocal();
    if (date == null) return 'Fecha no disponible';
    final day = date.day.toString().padLeft(2, '0');
    final month = date.month.toString().padLeft(2, '0');
    final hour = date.hour.toString().padLeft(2, '0');
    final minute = date.minute.toString().padLeft(2, '0');
    final age = DateTime.now().difference(date).inDays;
    final ageText = age <= 0
        ? 'Hoy'
        : age == 1
        ? 'Hace 1 día'
        : 'Hace $age días';
    return '$ageText · $day/$month · $hour:$minute';
  }

  Future<void> _openBirthdayCampaign({Customer? customer}) async {
    final now = DateTime.now();
    final date =
        '${now.day.toString().padLeft(2, '0')}/'
        '${now.month.toString().padLeft(2, '0')}';
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => CampaignsScreen(
          openComposerOnStart: true,
          initialAudience: customer == null
              ? 'Cumpleañeros de hoy'
              : 'Una persona',
          initialTargetCustomerId: customer?.id,
          initialTargetCustomerName: customer?.name,
          initialName: customer == null
              ? 'Cumpleaños de hoy · $date'
              : 'Cumpleaños de ${customer.name}',
          initialNotificationTitle: '¡Feliz cumpleaños!',
          initialMessage:
              '¡Hoy es tu cumpleaños! 🎂 Queremos celebrarlo contigo. Te esperamos para que disfrutes de tu día.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final data = AppScope.of(context).data;
    final customers = {for (final item in data.customers) item.id: item};
    final programs = {for (final item in data.programs) item.id: item};
    final now = DateTime.now();
    final birthdays =
        data.customers
            .where(
              (customer) =>
                  customer.birthDate?.month == now.month &&
                  customer.birthDate?.day == now.day,
            )
            .toList()
          ..sort(
            (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
          );
    return PageBody(
      maxContentWidth: 1080,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                _showBirthdays ? 'Cumpleañeros de hoy' : 'Premios pendientes',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
            ),
            if (!_showBirthdays)
              IconButton(
                tooltip: 'Actualizar premios',
                onPressed: _loading ? null : _loadClaims,
                icon: const Icon(Icons.refresh_rounded),
              ),
          ],
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          children: [
            ChoiceChip(
              label: const Text('Premios pendientes'),
              selected: !_showBirthdays,
              onSelected: (_) => setState(() => _showBirthdays = false),
            ),
            ChoiceChip(
              label: Text('Cumpleañeros · ${birthdays.length}'),
              selected: _showBirthdays,
              onSelected: (_) => setState(() => _showBirthdays = true),
            ),
          ],
        ),
        const SizedBox(height: 18),
        if (_showBirthdays) ...[
          Text(
            'Solo aparecen los clientes que cumplen años hoy. El aviso del menú muestra cuántos hay y no desaparece al entrar.',
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: FideliTheme.muted),
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF0F1),
              borderRadius: BorderRadius.circular(24),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.cake_rounded, color: FideliTheme.coral),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        birthdays.isEmpty
                            ? 'Hoy no hay cumpleaños registrados.'
                            : '${birthdays.length} ${birthdays.length == 1 ? 'cumpleañero hoy' : 'cumpleañeros hoy'}',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
                if (birthdays.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton.icon(
                      onPressed: () => _openBirthdayCampaign(),
                      icon: const Icon(Icons.campaign_outlined),
                      label: const Text('Campaña para todos'),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 14),
          if (birthdays.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(28),
                child: Center(
                  child: Text('Vuelve a revisar cuando haya cumpleaños.'),
                ),
              ),
            )
          else
            for (final customer in birthdays)
              Card(
                child: ListTile(
                  leading: CustomerAvatar(customer: customer, size: 48),
                  title: Text(customer.name),
                  subtitle: Text(
                    customer.phone.isNotEmpty
                        ? customer.phone
                        : customer.email.isNotEmpty
                        ? customer.email
                        : 'Sin datos de contacto',
                  ),
                  trailing: IconButton.filledTonal(
                    tooltip: 'Preparar campaña para ${customer.name}',
                    onPressed: () => _openBirthdayCampaign(customer: customer),
                    icon: const Icon(Icons.campaign_outlined),
                  ),
                ),
              ),
        ] else ...[
          const SizedBox(height: 4),
          Text(
            'Clientes que ya ganaron un premio y todavía no lo han reclamado.',
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: FideliTheme.muted),
          ),
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF0F1),
              borderRadius: BorderRadius.circular(24),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.card_giftcard_rounded,
                  color: FideliTheme.coral,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _claims.isEmpty
                        ? 'No hay premios pendientes por entregar.'
                        : '${_claims.length} ${_claims.length == 1 ? 'premio pendiente' : 'premios pendientes'}',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          if (_loading)
            const Padding(
              padding: EdgeInsets.all(36),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_error != null)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(22),
                child: Column(
                  children: [
                    Text(_error!, textAlign: TextAlign.center),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: _loadClaims,
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('Reintentar'),
                    ),
                  ],
                ),
              ),
            )
          else if (_claims.isEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(30),
                child: Column(
                  children: [
                    const Icon(
                      Icons.celebration_rounded,
                      size: 42,
                      color: FideliTheme.coral,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Todo al día',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Cuando un cliente gane un premio, aparecerá aquí.',
                    ),
                  ],
                ),
              ),
            )
          else
            for (final claim in _claims)
              _ClaimCard(
                claim: claim,
                customer: customers[claim['customer_id']],
                program: programs[claim['program_id']],
                earnedLabel: _earnedLabel(claim['earned_at']),
                busy:
                    _claimingId ==
                    '${claim['customer_id']}:${claim['reward_id']}',
                onClaim: () => _markClaimed(claim),
              ),
        ],
      ],
    );
  }
}

class _ClaimCard extends StatelessWidget {
  const _ClaimCard({
    required this.claim,
    required this.customer,
    required this.program,
    required this.earnedLabel,
    required this.busy,
    required this.onClaim,
  });

  final Map<String, dynamic> claim;
  final Customer? customer;
  final LoyaltyProgram? program;
  final String earnedLabel;
  final bool busy;
  final VoidCallback onClaim;

  @override
  Widget build(BuildContext context) {
    final reminders = (claim['reminder_count'] as num?)?.toInt() ?? 0;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (customer != null)
                  CustomerAvatar(customer: customer!, size: 50)
                else
                  const CircleAvatar(child: Icon(Icons.person_outline_rounded)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        customer?.name ?? 'Cliente',
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                        ),
                      ),
                      Text(program?.name ?? 'Tarjeta de fidelidad'),
                    ],
                  ),
                ),
                const Icon(
                  Icons.card_giftcard_rounded,
                  color: FideliTheme.coral,
                ),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(15),
              decoration: BoxDecoration(
                color: const Color(0xFFF8F7F8),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    claim['reward_name']?.toString() ?? 'Premio',
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 17,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    earnedLabel,
                    style: const TextStyle(color: FideliTheme.muted),
                  ),
                  if (reminders > 0) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Recordatorios enviados: $reminders',
                      style: const TextStyle(color: FideliTheme.muted),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 14),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                onPressed: busy ? null : onClaim,
                icon: busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.check_circle_outline_rounded),
                label: const Text('Marcar como entregado'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
