import 'dart:async';

import 'package:flutter/cupertino.dart';

import 'package:flutter/material.dart';

import 'package:qr_flutter/qr_flutter.dart';

import 'package:url_launcher/url_launcher.dart';

import '../models/app_data.dart';
import '../models/customer_intelligence.dart';

import '../services/wallet_service.dart';

import '../state/app_scope.dart';
import '../theme/fideli_theme.dart';

import '../widgets/common.dart';

import '../widgets/customer_avatar.dart';

class CustomersScreen extends StatefulWidget {
  const CustomersScreen({super.key});

  @override
  State<CustomersScreen> createState() => _CustomersScreenState();
}

class _CustomersScreenState extends State<CustomersScreen> {
  final _search = TextEditingController();

  CustomerAttention? _attention;

  _CustomerSort _sort = _CustomerSort.risk;

  bool _busy = false;

  Future<void> _openCustomer(Customer customer) async {
    if (MediaQuery.sizeOf(context).width < 900) {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => CustomerDetailScreen(customerId: customer.id),
        ),
      );
      return;
    }

    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Cerrar detalle del cliente',
      barrierColor: const Color(0x26000000),
      transitionDuration: const Duration(milliseconds: 620),
      pageBuilder: (dialogContext, animation, secondaryAnimation) {
        final width = (MediaQuery.sizeOf(dialogContext).width * .42)
            .clamp(460.0, 620.0)
            .toDouble();
        return SafeArea(
          child: Align(
            alignment: Alignment.centerRight,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
              child: Container(
                key: const ValueKey('customer-side-panel'),
                width: width,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(32),
                  border: Border.all(color: FideliTheme.line),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x30000000),
                      blurRadius: 46,
                      spreadRadius: -8,
                      offset: Offset(-14, 14),
                    ),
                  ],
                ),
                clipBehavior: Clip.antiAlias,
                child: CustomerDetailScreen(
                  customerId: customer.id,
                  panelMode: true,
                ),
              ),
            ),
          ),
        );
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        final entrance = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutBack,
          reverseCurve: Curves.easeInCubic,
        );
        final fade = CurvedAnimation(
          parent: animation,
          curve: const Interval(0, .55, curve: Curves.easeOut),
          reverseCurve: Curves.easeIn,
        );
        final expansion = TweenSequence<double>([
          TweenSequenceItem(
            tween: Tween<double>(
              begin: .90,
              end: 1.025,
            ).chain(CurveTween(curve: Curves.easeOutCubic)),
            weight: 78,
          ),
          TweenSequenceItem(
            tween: Tween<double>(
              begin: 1.025,
              end: 1,
            ).chain(CurveTween(curve: Curves.easeOutBack)),
            weight: 22,
          ),
        ]).animate(animation);

        return FadeTransition(
          opacity: fade,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(1.08, 0),
              end: Offset.zero,
            ).animate(entrance),
            child: ScaleTransition(
              alignment: Alignment.centerRight,
              scale: expansion,
              child: child,
            ),
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    _search.dispose();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);

    final query = _search.text.trim().toLowerCase();

    final customers = state.data.customers
        .where(
          (customer) =>
              (_attention == null ||
                  customer.intelligence?.attention == _attention) &&
              (query.isEmpty ||
                  customer.name.toLowerCase().contains(query) ||
                  customer.referralCode.toLowerCase().contains(query) ||
                  customer.phone.toLowerCase().contains(query) ||
                  customer.email.toLowerCase().contains(query)),
        )
        .toList();
    customers.sort(
      (a, b) => switch (_sort) {
        _CustomerSort.name => a.name.compareTo(b.name),
        _CustomerSort.value => (b.intelligence?.valueScore ?? 0).compareTo(
          a.intelligence?.valueScore ?? 0,
        ),
        _CustomerSort.risk => (b.intelligence?.riskScore ?? 0).compareTo(
          a.intelligence?.riskScore ?? 0,
        ),
        _CustomerSort.frequency =>
          (b.intelligence?.visits90d ?? b.visits).compareTo(
            a.intelligence?.visits90d ?? a.visits,
          ),
        _CustomerSort.spend => (b.intelligence?.totalSpendMinor ?? 0).compareTo(
          a.intelligence?.totalSpendMinor ?? 0,
        ),
        _CustomerSort.recent =>
          (a.intelligence?.daysSinceLastVisit ?? 999999).compareTo(
            b.intelligence?.daysSinceLastVisit ?? 999999,
          ),
        _CustomerSort.absent =>
          (b.intelligence?.daysSinceLastVisit ?? -1).compareTo(
            a.intelligence?.daysSinceLastVisit ?? -1,
          ),
      },
    );

    return PageBody(
      children: [
        TextField(
          controller: _search,

          onChanged: (_) => setState(() {}),

          decoration: InputDecoration(
            hintText: 'Nombre, código, teléfono o correo',

            prefixIcon: const Icon(
              Icons.search_rounded,

              color: FideliTheme.ink,
            ),

            suffixIcon: _search.text.isEmpty
                ? null
                : IconButton(
                    onPressed: () {
                      _search.clear();

                      setState(() {});
                    },

                    icon: const Icon(Icons.close_rounded),
                  ),

            filled: true,

            fillColor: Colors.white,

            contentPadding: const EdgeInsets.symmetric(
              horizontal: 18,

              vertical: 17,
            ),

            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(20),

              borderSide: BorderSide.none,
            ),

            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(20),

              borderSide: const BorderSide(color: Color(0x0F000000)),
            ),

            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(20),

              borderSide: const BorderSide(color: FideliTheme.ink, width: 1.5),
            ),
          ),
        ),

        const SizedBox(height: 12),

        SizedBox(
          height: 42,
          child: ListView(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            children: [
              _SegmentChip(
                label: 'Todos',
                count: state.data.customers.length,
                selected: _attention == null,
                onTap: () => setState(() => _attention = null),
              ),
              for (final attention in CustomerAttention.values)
                _SegmentChip(
                  label: attention.label,
                  count: state.data.customers
                      .where(
                        (customer) =>
                            customer.intelligence?.attention == attention,
                      )
                      .length,
                  selected: _attention == attention,
                  onTap: () => setState(() => _attention = attention),
                ),
            ],
          ),
        ),

        const SizedBox(height: 8),

        Align(
          alignment: Alignment.centerRight,
          child: PopupMenuButton<_CustomerSort>(
            initialValue: _sort,
            onSelected: (value) => setState(() => _sort = value),
            itemBuilder: (_) => _CustomerSort.values
                .map(
                  (value) =>
                      PopupMenuItem(value: value, child: Text(value.label)),
                )
                .toList(),
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.swap_vert_rounded, size: 19),
                  SizedBox(width: 5),
                  Text('Ordenar'),
                ],
              ),
            ),
          ),
        ),

        if (state.data.customers.isNotEmpty) ...[
          const SizedBox(height: 8),

          Align(
            alignment: Alignment.centerRight,

            child: TextButton.icon(
              style: TextButton.styleFrom(foregroundColor: Colors.red),

              onPressed: _busy ? null : () => _deleteAll(context),

              icon: const Icon(Icons.delete_sweep_outlined),

              label: const Text('Borrar todos'),
            ),
          ),
        ],

        const SizedBox(height: 12),

        for (final customer in customers)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),

            child: Material(
              color: Colors.white,

              borderRadius: BorderRadius.circular(24),

              clipBehavior: Clip.antiAlias,

              child: ListTile(
                minTileHeight: 78,

                contentPadding: const EdgeInsets.fromLTRB(14, 8, 8, 8),

                leading: CustomerAvatar(customer: customer, size: 50),

                title: Text(
                  customer.name,

                  style: const TextStyle(
                    fontFamily: 'Poppins',

                    fontSize: 15,

                    fontWeight: FontWeight.w600,
                  ),
                ),

                subtitle: Text(
                  customer.intelligence == null
                      ? (customer.phone.isNotEmpty
                            ? customer.phone
                            : customer.email.isNotEmpty
                            ? customer.email
                            : 'Sin datos de contacto')
                      : customer.intelligence!.statusLabel == null
                      ? customer.intelligence!.statusExplanation
                      : '${customer.intelligence!.statusLabel} · ${customer.intelligence!.statusExplanation}',

                  maxLines: 2,

                  overflow: TextOverflow.ellipsis,

                  style: const TextStyle(
                    fontFamily: 'Poppins',

                    fontSize: 12,

                    height: 1.4,

                    color: Color(0xFF7C7472),
                  ),
                ),

                trailing: IconButton.filledTonal(
                  tooltip: 'Administrar cliente',

                  style: IconButton.styleFrom(
                    backgroundColor: const Color(0x129E483F),

                    foregroundColor: FideliTheme.ink,
                  ),

                  icon: const Icon(Icons.manage_accounts_outlined),

                  onPressed: () => _openCustomer(customer),
                ),

                onTap: () => _openCustomer(customer),
              ),
            ),
          ),

        if (customers.isEmpty)
          ListTile(
            title: Text(
              query.isEmpty
                  ? 'No hay clientes.'
                  : 'No se encontraron clientes.',
            ),
          ),

        const SizedBox(height: 80),
      ],
    );
  }

  Future<void> _deleteAll(BuildContext context) async {
    if (_busy) return;

    final state = AppScope.of(context);

    final accepted = await showDialog<bool>(
      context: context,

      builder: (dialogContext) => AlertDialog(
        title: const Text('¿Borrar todos los clientes?'),

        content: const Text(
          'Se quitarán del dashboard y todas sus tarjetas quedarán anuladas. Esta acción no se puede deshacer.',
        ),

        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),

            child: const Text('Cancelar'),
          ),

          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),

            onPressed: () => Navigator.pop(dialogContext, true),

            child: const Text('Borrar todos'),
          ),
        ],
      ),
    );

    if (accepted != true || !context.mounted) return;

    setState(() => _busy = true);

    try {
      final result = await state.deleteAllCustomers();

      if (context.mounted) showMessage(context, result.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

class CustomerServiceScreen extends StatefulWidget {
  const CustomerServiceScreen({
    super.key,

    required this.customerId,

    this.programId,

    this.walletService,
  });

  final String customerId;

  final String? programId;

  final WalletService? walletService;

  @override
  State<CustomerServiceScreen> createState() => _CustomerServiceScreenState();
}

class _CustomerServiceScreenState extends State<CustomerServiceScreen> {
  late final WalletService _wallet;

  bool _saving = false;

  FixedExtentScrollController? _valueController;

  int? _selectedValue;

  String? _pickerProgramId;

  @override
  void initState() {
    super.initState();
    _wallet = widget.walletService ?? WalletService();
  }

  void _ensurePicker(LoyaltyProgram program, int value) {
    if (_pickerProgramId == program.id && _valueController != null) return;

    _valueController?.dispose();

    _pickerProgramId = program.id;

    _selectedValue = value;

    _valueController = FixedExtentScrollController(initialItem: value);
  }

  Future<void> _sendSelectedValue(
    Customer customer,

    LoyaltyProgram program,

    int currentValue,
  ) async {
    final target = _selectedValue ?? currentValue;

    final delta = target - currentValue;

    if (_saving || delta == 0) return;

    final state = AppScope.of(context);

    setState(() => _saving = true);

    await state.adjustCardValue(
      customer.id,

      program.id,

      delta: delta,

      description: delta > 0 ? 'Sellos enviados' : 'Sellos corregidos',
    );

    final result = await _wallet.syncCustomer(
      state.data.business,

      customer,

      recordActivity: delta > 0,

      programId: program.id,

      previousProgramValue: currentValue,
    );

    if (!mounted) return;

    setState(() => _saving = false);

    showMessage(context, result.ok ? 'Sellos actualizados' : result.message);
  }

  Future<void> _adjustCard(
    Customer customer,

    LoyaltyProgram program, {

    required bool add,
  }) async {
    final isGift = program.cardKind == 'Tarjeta de regalo';

    var enteredAmount = '';

    final acceptedAmount = await showDialog<int>(
      context: context,

      builder: (dialogContext) => AlertDialog(
        title: Text(
          isGift
              ? (add ? 'Cargar saldo' : 'Consumir saldo')
              : (add ? 'Agregar puntos' : 'Descontar puntos'),
        ),

        content: TextField(
          autofocus: true,

          keyboardType: TextInputType.number,

          onChanged: (value) => enteredAmount = value,

          decoration: InputDecoration(
            labelText: isGift ? 'Monto en Bs' : 'Cantidad de puntos',
          ),
        ),

        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),

            child: const Text('Cancelar'),
          ),

          FilledButton(
            onPressed: () => Navigator.pop(
              dialogContext,
              int.tryParse(enteredAmount.trim()) ?? 0,
            ),

            child: const Text('Confirmar'),
          ),
        ],
      ),
    );

    if (acceptedAmount == null || acceptedAmount <= 0 || !mounted) return;

    // `showDialog` completa antes de que termine por completo su animación de
    // salida. Esperar el desmontaje evita reconstruir AppScope mientras la
    // ruta del diálogo todavía conserva dependientes activos.
    await Future<void>.delayed(const Duration(milliseconds: 240));
    if (!mounted || _saving) return;

    final state = AppScope.of(context);

    final current = customer.balanceFor(program.id).points;

    if (!add && acceptedAmount > current) {
      showMessage(context, 'Saldo insuficiente');

      return;
    }

    setState(() => _saving = true);

    final requestedDelta = add ? acceptedAmount : -acceptedAmount;
    final target = current + requestedDelta;

    try {
      // La pantalla cambia inmediatamente, pero el servidor recibe un valor
      // absoluto e idempotente para que ningún guardado atrasado lo revierta.
      await state.setCardValue(customer.id, program.id, target);

      final updatedCustomer = state.customerById(customer.id) ?? customer;

      final result = await _wallet.setCardBalance(
        state.data.business,
        updatedCustomer,
        program,
        value: target,
        previousValue: current,
      );

      if (!result.ok) {
        await state.setCardValue(customer.id, program.id, current);
      } else {
        final savedValue = result.value ?? target;
        await state.setCardValue(customer.id, program.id, savedValue);
        await state.recordCardValueActivity(
          customer.id,
          program.id,
          delta: savedValue - current,
          description: isGift
              ? (add
                    ? 'Carga de tarjeta de regalo'
                    : 'Consumo de tarjeta de regalo')
              : (add ? 'Puntos agregados' : 'Puntos descontados'),
        );
      }

      if (!mounted) return;

      showMessage(
        context,
        result.ok
            ? (isGift ? 'Saldo actualizado' : 'Puntos enviados')
            : result.message,
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _redeemReward(Customer customer, Reward reward) async {
    if (_saving) return;
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('¿Cobrar esta recompensa?'),
        content: Text(
          '${reward.name}\n\nEl canje quedará guardado y no podrá cobrarse nuevamente.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Cobrar recompensa'),
          ),
        ],
      ),
    );
    if (accepted != true || !mounted) return;

    final state = AppScope.of(context);
    setState(() => _saving = true);
    final result = await _wallet.redeemReward(
      state.data.business,
      customerId: customer.id,
      rewardId: reward.id,
    );
    if (result.ok || result.code == 'already_redeemed') {
      await state.refreshFromCloud();
    }
    if (!mounted) return;
    setState(() => _saving = false);
    showMessage(context, result.message);
  }

  @override
  void dispose() {
    _valueController?.dispose();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);

    final customer = state.customerById(widget.customerId);

    if (customer == null) {
      return const Scaffold(body: Center(child: Text('Cliente no encontrado')));
    }

    final activePrograms = state.data.activeProgramsForCustomer(customer);

    if (widget.programId != null &&
        !customer.cardBalances.containsKey(widget.programId)) {
      return const Scaffold(
        body: Center(child: Text('El cliente no pertenece a esta tarjeta')),
      );
    }

    if (widget.programId == null && activePrograms.length > 1) {
      return Scaffold(
        appBar: AppBar(title: Text('Tarjetas de ${customer.name}')),

        body: ListView(
          padding: const EdgeInsets.all(16),

          children: [
            const Text(
              'Elige la tarjeta que el cliente está presentando. Cada una tiene acciones independientes.',
            ),

            const SizedBox(height: 12),

            for (final item in activePrograms)
              Card(
                child: ListTile(
                  leading: Icon(switch (item.cardKind) {
                    'Tarjeta de regalo' => Icons.card_giftcard,

                    'Membresía' => Icons.badge_outlined,

                    _ =>
                      item.type == ProgramType.points
                          ? Icons.stars_outlined
                          : Icons.grid_view_outlined,
                  }),

                  title: Text(item.name),

                  subtitle: Text('${item.cardKind} · ${item.type.label}'),

                  trailing: const Icon(Icons.chevron_right),

                  onTap: () => Navigator.of(context).pushReplacement(
                    MaterialPageRoute<void>(
                      builder: (_) => CustomerServiceScreen(
                        customerId: customer.id,

                        programId: item.id,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      );
    }

    final program = widget.programId == null
        ? activePrograms.firstOrNull
        : state.data.programs
              .where(
                (item) =>
                    item.id == widget.programId &&
                    item.active &&
                    !item.isExpired,
              )
              .firstOrNull;

    final goal = program?.goal ?? 7;

    final balance = program == null ? null : customer.balanceFor(program.id);

    final stamps = balance?.stamps ?? customer.stamps;

    final points = balance?.points ?? customer.points;

    final visits = balance?.visits ?? customer.visits;

    final usesPoints = program?.type == ProgramType.points;

    final usesVisits =
        program?.type == ProgramType.visits ||
        program?.type == ProgramType.membership;

    final value = usesPoints ? points : (usesVisits ? visits : stamps);

    final unit = usesPoints ? 'puntos' : (usesVisits ? 'visitas' : 'sellos');

    final isGift = program?.cardKind == 'Tarjeta de regalo';

    final isMembership = program?.cardKind == 'Membresía';

    final availableReward = program == null
        ? null
        : state.data.rewards
              .where(
                (reward) =>
                    reward.active &&
                    reward.programId == program.id &&
                    state.canRedeemReward(customer.id, reward.id),
              )
              .firstOrNull;

    final milestones = [...?program?.stampMilestones]
      ..sort((left, right) => left.stamp.compareTo(right.stamp));
    final reachedMilestones = milestones
        .where((item) => item.stamp <= value && item.reward.trim().isNotEmpty)
        .toList();
    final reachedMilestone = reachedMilestones.lastOrNull;
    final nextMilestone = milestones
        .where((item) => item.stamp > value && item.reward.trim().isNotEmpty)
        .firstOrNull;

    final progress = (value / goal).clamp(0.0, 1.0);

    if (program != null && !isGift && !usesPoints) {
      _ensurePicker(program, value);
    }

    final pickerMaximum = goal > value ? goal : value;

    return Scaffold(
      appBar: AppBar(title: const Text('Atender cliente')),

      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),

          child: ListView(
            padding: const EdgeInsets.all(24),

            children: [
              Center(child: CustomerAvatar(customer: customer, size: 68)),

              const SizedBox(height: 12),

              Text(
                customer.name,

                textAlign: TextAlign.center,

                style: Theme.of(context).textTheme.headlineSmall,
              ),

              Text(
                'Código ${customer.referralCode}',

                textAlign: TextAlign.center,
              ),

              if (program != null)
                Text(program.name, textAlign: TextAlign.center),

              const SizedBox(height: 30),

              Text(
                isGift
                    ? 'Saldo disponible: Bs $value'
                    : isMembership
                    ? (program?.isExpired == true
                          ? 'Membresía vencida'
                          : 'Membresía vigente')
                    : '$value de $goal $unit',

                textAlign: TextAlign.center,

                style: Theme.of(context).textTheme.headlineMedium,
              ),

              const SizedBox(height: 12),

              if (!isGift && !isMembership) ...[
                LinearProgressIndicator(value: progress, minHeight: 14),

                const SizedBox(height: 8),

                Text(
                  reachedMilestone != null && !usesVisits
                      ? 'Premio desbloqueado: ${reachedMilestone.reward}'
                      : value >= goal
                      ? 'Recompensa lista para canjear'
                      : nextMilestone != null && !usesVisits
                      ? 'Próximo premio: ${nextMilestone.reward} · sello ${nextMilestone.stamp}'
                      : 'Faltan ${goal - value} $unit',

                  textAlign: TextAlign.center,
                ),

                if (availableReward != null) ...[
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: _saving
                        ? null
                        : () => _redeemReward(customer, availableReward),
                    icon: const Icon(Icons.redeem_rounded),
                    label: Text('Cobrar ${availableReward.name}'),
                  ),
                ],
              ],

              const SizedBox(height: 30),

              if (isGift || usesPoints) ...[
                FilledButton.icon(
                  onPressed: _saving || program == null
                      ? null
                      : () => _adjustCard(customer, program, add: true),

                  icon: const Icon(Icons.add_circle_outline),

                  label: Text(isGift ? 'Cargar saldo' : 'Agregar puntos'),
                ),

                const SizedBox(height: 12),

                OutlinedButton.icon(
                  onPressed: _saving || value == 0 || program == null
                      ? null
                      : () => _adjustCard(customer, program, add: false),

                  icon: const Icon(Icons.remove_circle_outline),

                  label: Text(isGift ? 'Consumir saldo' : 'Descontar puntos'),
                ),
              ] else if (program != null) ...[
                _HorizontalValuePicker(
                  controller: _valueController!,

                  maximum: pickerMaximum,

                  unit: unit,

                  enabled: !_saving,

                  onChanged: (selected) {
                    setState(() => _selectedValue = selected);
                  },
                ),

                const SizedBox(height: 16),

                FilledButton(
                  onPressed: _saving || (_selectedValue ?? value) == value
                      ? null
                      : () => _sendSelectedValue(customer, program, value),

                  child: const Padding(
                    padding: EdgeInsets.symmetric(vertical: 14),

                    child: Text('Enviar'),
                  ),
                ),
              ],

              const SizedBox(height: 20),

              Text(
                '$visits visitas registradas en esta tarjeta',

                textAlign: TextAlign.center,
              ),

              if (_saving) ...[
                const SizedBox(height: 16),

                const LinearProgressIndicator(),

                const Text(
                  'Sincronizando con Wallet…',

                  textAlign: TextAlign.center,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _HorizontalValuePicker extends StatelessWidget {
  const _HorizontalValuePicker({
    required this.controller,

    required this.maximum,

    required this.unit,

    required this.enabled,

    required this.onChanged,
  });

  final FixedExtentScrollController controller;

  final int maximum;

  final String unit;

  final bool enabled;

  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      opacity: enabled ? 1 : 0.48,

      duration: const Duration(milliseconds: 180),

      child: Container(
        height: 128,

        decoration: BoxDecoration(
          color: Colors.white,

          borderRadius: BorderRadius.circular(28),
        ),

        clipBehavior: Clip.antiAlias,

        child: IgnorePointer(
          ignoring: !enabled,

          child: RotatedBox(
            quarterTurns: 3,

            child: CupertinoPicker.builder(
              scrollController: controller,

              itemExtent: 82,

              diameterRatio: 1.35,

              squeeze: 0.9,

              useMagnifier: true,

              magnification: 1.12,

              selectionOverlay: CupertinoPickerDefaultSelectionOverlay(
                background: FideliTheme.ink.withValues(alpha: 0.12),
              ),

              childCount: maximum + 1,

              onSelectedItemChanged: onChanged,

              itemBuilder: (context, index) => RotatedBox(
                quarterTurns: 1,

                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,

                    children: [
                      Text(
                        '$index',

                        style: const TextStyle(
                          fontFamily: 'Poppins',

                          fontSize: 30,

                          fontWeight: FontWeight.w700,

                          color: Color(0xFF30292A),
                        ),
                      ),

                      Text(
                        unit,

                        style: const TextStyle(
                          fontFamily: 'Poppins',

                          fontSize: 10,

                          fontWeight: FontWeight.w500,

                          color: Color(0xFF837A78),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class CustomerDetailScreen extends StatefulWidget {
  const CustomerDetailScreen({
    super.key,
    required this.customerId,
    this.panelMode = false,
  });

  final String customerId;
  final bool panelMode;

  @override
  State<CustomerDetailScreen> createState() => _CustomerDetailScreenState();
}

class _CustomerDetailScreenState extends State<CustomerDetailScreen> {
  static const _accent = FideliTheme.ink;
  static const _background = Colors.white;
  static const _actionSurface = Colors.white;
  static const _text = Color(0xFF2C2425);
  static const _muted = Color(0xFF746A6B);
  final Set<String> _redeemingRewardIds = {};

  String _date(DateTime? value) {
    if (value == null) return 'No registrada';
    final local = value.toLocal();
    String two(int number) => number.toString().padLeft(2, '0');
    return '${two(local.day)}/${two(local.month)}/${local.year}';
  }

  String _dateTime(DateTime value) {
    final local = value.toLocal();
    String two(int number) => number.toString().padLeft(2, '0');
    return '${two(local.day)}/${two(local.month)}/${local.year} · '
        '${two(local.hour)}:${two(local.minute)}';
  }

  Future<void> _openWhatsApp(String phone) async {
    var number = phone.replaceAll(RegExp(r'[^0-9]'), '');
    if (number.startsWith('00')) number = number.substring(2);
    // Los números locales bolivianos tienen ocho dígitos. Los números que ya
    // incluyen prefijo internacional se conservan tal como fueron registrados.
    if (number.length == 8) number = '591$number';
    if (number.isEmpty) return;
    final opened = await launchUrl(
      Uri.https('wa.me', '/$number'),
      mode: LaunchMode.externalApplication,
    );
    if (!opened && mounted) showMessage(context, 'No se pudo abrir WhatsApp');
  }

  Future<void> _openEmail(String email) async {
    final address = email.trim();
    if (address.isEmpty) return;
    final opened = await launchUrl(
      Uri(scheme: 'mailto', path: address),
      mode: LaunchMode.externalApplication,
    );
    if (!opened && mounted) showMessage(context, 'No se pudo abrir el correo');
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final customer = state.customerById(widget.customerId);

    if (customer == null) {
      return const Scaffold(
        backgroundColor: _background,
        body: Center(
          child: Text(
            'Cliente no encontrado',
            style: TextStyle(fontFamily: 'Poppins'),
          ),
        ),
      );
    }

    final activities =
        state.data.activities
            .where((item) => item.customerId == customer.id)
            .toList()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    final rewards = state.data.rewards
        .where(
          (reward) =>
              reward.active &&
              (reward.programId.isEmpty ||
                  customer.cardBalances.containsKey(reward.programId)),
        )
        .toList();
    final customerPrograms = state.data.programs
        .where((program) => customer.cardBalances.containsKey(program.id))
        .toList();

    return Scaffold(
      backgroundColor: _background,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final horizontalPadding = widget.panelMode
                ? 28.0
                : constraints.maxWidth < 700
                ? 22.0
                : 42.0;
            final maxContentWidth = widget.panelMode
                ? 560.0
                : constraints.maxWidth < 700
                ? 620.0
                : 920.0;

            return SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              padding: EdgeInsets.fromLTRB(
                horizontalPadding,
                18,
                horizontalPadding,
                48,
              ),
              child: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: maxContentWidth),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          _RoundIconButton(
                            icon: widget.panelMode
                                ? Icons.close_rounded
                                : Icons.arrow_back_rounded,
                            tooltip: widget.panelMode ? 'Cerrar' : 'Volver',
                            onTap: () => Navigator.of(context).pop(),
                          ),
                          _RoundIconButton(
                            icon: Icons.delete_outline_rounded,
                            tooltip: 'Borrar cliente',
                            onTap: () => _delete(customer),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),

                      Center(
                        child: Column(
                          children: [
                            CustomerAvatar(customer: customer, size: 82),
                            const SizedBox(height: 14),
                            const Text(
                              'CLIENTE',
                              style: TextStyle(
                                fontFamily: 'Poppins',
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 2.2,
                                color: _accent,
                              ),
                            ),
                            const SizedBox(height: 5),
                            Text(
                              customer.name,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontFamily: 'Poppins',
                                fontSize: 31,
                                height: 1.05,
                                fontWeight: FontWeight.w700,
                                letterSpacing: -1.1,
                                color: _text,
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 42),

                      if (customer.intelligence case final intelligence?) ...[
                        _CustomerIntelligenceCard(intelligence: intelligence),
                        const SizedBox(height: 18),
                      ],

                      _CustomerDetailRow(
                        title: 'Celular',
                        subtitle: customer.phone.isEmpty
                            ? 'No registrado'
                            : customer.phone,
                        icon: Icons.phone_rounded,
                        onTap: customer.phone.isEmpty
                            ? null
                            : () => _openWhatsApp(customer.phone),
                      ),
                      _CustomerDetailRow(
                        title: 'Correo',
                        subtitle: customer.email.isEmpty
                            ? 'No registrado'
                            : customer.email,
                        icon: Icons.mail_outline_rounded,
                        onTap: customer.email.isEmpty
                            ? null
                            : () => _openEmail(customer.email),
                      ),
                      _CustomerDetailRow(
                        title: 'Nacimiento',
                        subtitle: _date(customer.birthDate),
                        icon: Icons.cake_outlined,
                      ),

                      const SizedBox(height: 18),
                      const _SectionEyebrow(title: 'TARJETAS DEL CLIENTE'),
                      const SizedBox(height: 16),

                      if (customerPrograms.isEmpty)
                        const _CustomerDetailRow(
                          title: 'Sin tarjetas',
                          subtitle: 'Este cliente no tiene tarjetas asignadas',
                          icon: Icons.credit_card_off_outlined,
                        )
                      else
                        for (final program in customerPrograms)
                          Builder(
                            builder: (context) {
                              final balance = customer.cardBalances[program.id];
                              final value = switch (program.type) {
                                ProgramType.stamps =>
                                  '${balance?.stamps ?? 0} de ${program.goal} sellos',
                                ProgramType.points || ProgramType.hybrid =>
                                  '${balance?.points ?? 0} puntos',
                                ProgramType.visits =>
                                  '${balance?.visits ?? 0} visitas',
                                ProgramType.membership =>
                                  program.isExpired
                                      ? 'Membresía vencida'
                                      : 'Membresía activa',
                              };
                              return _CustomerDetailRow(
                                title: program.name,
                                subtitle:
                                    '${program.cardKind} · $value · Toca para eliminarla',
                                icon: Icons.delete_outline_rounded,
                                onTap: () => _deleteCard(customer, program),
                              );
                            },
                          ),

                      const SizedBox(height: 18),
                      const _SectionEyebrow(title: 'RECOMPENSAS'),
                      const SizedBox(height: 16),

                      if (rewards.isEmpty)
                        const _CustomerDetailRow(
                          title: 'Sin recompensas',
                          subtitle: 'Todavía no tiene recompensas disponibles',
                          icon: Icons.redeem_outlined,
                        )
                      else
                        for (final reward in rewards)
                          Builder(
                            builder: (context) {
                              final redeemed = customer.redeemedRewardIds
                                  .contains(reward.id);
                              final available = state.canRedeemReward(
                                customer.id,
                                reward.id,
                              );

                              final subtitle = redeemed
                                  ? 'Cobrada · no puede volver a reclamarse'
                                  : available
                                  ? 'Disponible · toca para cobrarla'
                                  : reward.pointsCost > 0
                                  ? '${reward.pointsCost} puntos'
                                  : '${reward.stampsCost} sellos';

                              return _CustomerDetailRow(
                                title: reward.name,
                                subtitle: subtitle,
                                icon: redeemed
                                    ? Icons.check_rounded
                                    : Icons.redeem_rounded,
                                emphasized: available && !redeemed,
                                onTap:
                                    available &&
                                        !redeemed &&
                                        !_redeemingRewardIds.contains(reward.id)
                                    ? () => _redeemReward(customer, reward)
                                    : null,
                              );
                            },
                          ),

                      const SizedBox(height: 18),
                      const _SectionEyebrow(title: 'HISTORIAL'),
                      const SizedBox(height: 16),

                      if (activities.isEmpty)
                        const _CustomerDetailRow(
                          title: 'Sin movimientos',
                          subtitle: 'Todavía no hay actividad registrada',
                          icon: Icons.history_rounded,
                        )
                      else
                        for (final activity in activities)
                          _CustomerHistoryRow(
                            title: activity.description,
                            subtitle: _dateTime(activity.createdAt),
                            pointsDelta: activity.pointsDelta,
                            eventType: activity.eventType,
                          ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Future<void> _delete(Customer customer) async {
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        title: Text(
          '¿Borrar a ${customer.name}?',
          style: const TextStyle(
            fontFamily: 'Poppins',
            fontWeight: FontWeight.w700,
            color: _text,
          ),
        ),
        content: const Text(
          'El cliente desaparecerá del dashboard y sus tarjetas quedarán anuladas en Wallet.',
          style: TextStyle(fontFamily: 'Poppins', height: 1.45, color: _muted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text(
              'Cancelar',
              style: TextStyle(fontFamily: 'Poppins', color: _muted),
            ),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: _accent,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text(
              'Borrar',
              style: TextStyle(
                fontFamily: 'Poppins',
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );

    if (accepted != true || !mounted) return;

    final result = await AppScope.of(context).deleteCustomer(customer.id);
    if (!mounted) return;

    showMessage(context, result.message);
    if (result.ok) Navigator.pop(context);
  }

  Future<void> _redeemReward(Customer customer, Reward reward) async {
    if (_redeemingRewardIds.contains(reward.id)) return;
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        title: const Text(
          '¿Cobrar esta recompensa?',
          style: TextStyle(
            fontFamily: 'Poppins',
            fontWeight: FontWeight.w700,
            color: _text,
          ),
        ),
        content: Text(
          '${reward.name}\n\nEl canje quedará guardado en el historial de ${customer.name} y no podrá cobrarse una segunda vez.',
          style: const TextStyle(
            fontFamily: 'Poppins',
            height: 1.45,
            color: _muted,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Cobrar recompensa'),
          ),
        ],
      ),
    );
    if (accepted != true || !mounted) return;

    setState(() => _redeemingRewardIds.add(reward.id));
    final state = AppScope.of(context);
    final result = await WalletService().redeemReward(
      state.data.business,
      customerId: customer.id,
      rewardId: reward.id,
    );
    if (result.ok || result.code == 'already_redeemed') {
      await state.refreshFromCloud();
    }
    if (!mounted) return;
    setState(() => _redeemingRewardIds.remove(reward.id));
    showMessage(context, result.message);
  }

  Future<void> _deleteCard(Customer customer, LoyaltyProgram program) async {
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        title: Text(
          '¿Eliminar ${program.name}?',
          style: const TextStyle(
            fontFamily: 'Poppins',
            fontWeight: FontWeight.w700,
            color: _text,
          ),
        ),
        content: Text(
          'Se quitará esta tarjeta de ${customer.name}, de su PWA y de Wallet. '
          'También se borrarán su saldo, inscripción e historial de esta tarjeta.',
          style: const TextStyle(
            fontFamily: 'Poppins',
            height: 1.45,
            color: _muted,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text(
              'Cancelar',
              style: TextStyle(fontFamily: 'Poppins', color: _muted),
            ),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: _accent,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text(
              'Eliminar tarjeta',
              style: TextStyle(
                fontFamily: 'Poppins',
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
    if (accepted != true || !mounted) return;
    final result = await AppScope.of(
      context,
    ).deleteCustomerCard(customer.id, program.id);
    if (!mounted) return;
    showMessage(context, result.message);
    if (result.ok) setState(() {});
  }
}

class _SectionEyebrow extends StatelessWidget {
  const _SectionEyebrow({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: const TextStyle(
        fontFamily: 'Poppins',
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 2.0,
        color: _CustomerDetailScreenState._accent,
      ),
    );
  }
}

class _RoundIconButton extends StatelessWidget {
  const _RoundIconButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(999),
          child: SizedBox(
            width: 46,
            height: 46,
            child: Icon(
              icon,
              color: _CustomerDetailScreenState._accent,
              size: 25,
            ),
          ),
        ),
      ),
    );
  }
}

class _CustomerDetailRow extends StatelessWidget {
  const _CustomerDetailRow({
    required this.title,
    required this.subtitle,
    required this.icon,
    this.emphasized = false,
    this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final bool emphasized;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 520;
    final actionWidth = compact ? 106.0 : 132.0;
    final actionHeight = compact ? 84.0 : 92.0;

    return Padding(
      padding: const EdgeInsets.only(bottom: 22),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(right: 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 19,
                      fontWeight: FontWeight.w700,
                      height: 1.1,
                      color: _CustomerDetailScreenState._text,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    subtitle,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      height: 1.35,
                      color: _CustomerDetailScreenState._muted,
                    ),
                  ),
                ],
              ),
            ),
          ),
          Semantics(
            button: onTap != null,
            label: onTap == null ? null : '$title: $subtitle',
            child: Material(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(24),
              child: Ink(
                width: actionWidth,
                height: actionHeight,
                decoration: BoxDecoration(
                  color: emphasized
                      ? _CustomerDetailScreenState._accent.withValues(
                          alpha: .10,
                        )
                      : _CustomerDetailScreenState._actionSurface,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: .92),
                    width: 1.2,
                  ),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x12000000),
                      blurRadius: 26,
                      offset: Offset(0, 12),
                    ),
                  ],
                ),
                child: InkWell(
                  onTap: onTap,
                  borderRadius: BorderRadius.circular(24),
                  child: Center(
                    child: Icon(
                      icon,
                      color: _CustomerDetailScreenState._accent,
                      size: 30,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CustomerHistoryRow extends StatelessWidget {
  const _CustomerHistoryRow({
    required this.title,
    required this.subtitle,
    required this.pointsDelta,
    required this.eventType,
  });

  final String title;
  final String subtitle;
  final int pointsDelta;
  final String eventType;

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 520;

    return Padding(
      padding: const EdgeInsets.only(bottom: 22),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(right: 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      height: 1.2,
                      color: _CustomerDetailScreenState._text,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: _CustomerDetailScreenState._muted,
                    ),
                  ),
                ],
              ),
            ),
          ),
          Container(
            width: compact ? 106 : 132,
            height: compact ? 84 : 92,
            decoration: BoxDecoration(
              color: _CustomerDetailScreenState._actionSurface,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: Colors.white.withValues(alpha: .92),
                width: 1.2,
              ),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x12000000),
                  blurRadius: 26,
                  offset: Offset(0, 12),
                ),
              ],
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  switch (eventType) {
                    'campaign_sent' => Icons.campaign_outlined,
                    'reward_redeemed' => Icons.redeem_rounded,
                    'qr_scan' => Icons.qr_code_scanner_rounded,
                    _ => Icons.history_rounded,
                  },
                  color: _CustomerDetailScreenState._accent,
                  size: 27,
                ),
                if (pointsDelta != 0) ...[
                  const SizedBox(height: 4),
                  Text(
                    '${pointsDelta > 0 ? '+' : ''}$pointsDelta',
                    style: const TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: _CustomerDetailScreenState._accent,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

enum _CustomerSort {
  name('Nombre'),
  value('Mayor valor'),
  risk('Mayor riesgo'),
  frequency('Más frecuentes'),
  spend('Mayor gasto'),
  recent('Más recientes'),
  absent('Más tiempo sin venir');

  const _CustomerSort(this.label);
  final String label;
}

class _SegmentChip extends StatelessWidget {
  const _SegmentChip({
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(right: 8),
    child: ChoiceChip(
      label: Text('$label  $count'),
      selected: selected,
      onSelected: (_) => onTap(),
      showCheckmark: false,
      selectedColor: FideliTheme.ink,
      backgroundColor: Colors.white,
      labelStyle: TextStyle(
        fontFamily: 'Poppins',
        fontSize: 11,
        fontWeight: FontWeight.w700,
        color: selected ? Colors.white : const Color(0xFF5C5352),
      ),
      side: BorderSide.none,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    ),
  );
}

class _CustomerIntelligenceCard extends StatelessWidget {
  const _CustomerIntelligenceCard({required this.intelligence});

  final CustomerIntelligence intelligence;

  @override
  Widget build(BuildContext context) {
    final risk = (intelligence.riskScore * 100).round();
    final cadence = intelligence.expectedVisitIntervalDays?.round();
    final spend = intelligence.totalSpendMinor / 100;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  intelligence.statusLabel ?? 'Análisis de visitas',
                  style: const TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: _CustomerDetailScreenState._text,
                  ),
                ),
              ),
              Text(
                'Riesgo $risk%',
                style: const TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: _CustomerDetailScreenState._accent,
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          Text(
            intelligence.statusExplanation,
            style: const TextStyle(
              fontFamily: 'Poppins',
              fontSize: 12,
              color: _CustomerDetailScreenState._muted,
            ),
          ),
          const SizedBox(height: 18),
          Wrap(
            spacing: 18,
            runSpacing: 12,
            children: [
              _IntelligenceMetric(
                value: '${intelligence.visits90d}',
                label: 'visitas · 90 días',
              ),
              _IntelligenceMetric(
                value: intelligence.daysSinceLastVisit == null
                    ? '—'
                    : '${intelligence.daysSinceLastVisit} d',
                label: 'desde la última visita',
              ),
              _IntelligenceMetric(
                value: cadence == null ? '—' : '$cadence d',
                label: 'ritmo esperado',
              ),
              _IntelligenceMetric(
                value: 'Bs ${spend.toStringAsFixed(2)}',
                label: intelligence.valueLabel,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _IntelligenceMetric extends StatelessWidget {
  const _IntelligenceMetric({required this.value, required this.label});
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 132,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: const TextStyle(
            fontFamily: 'Poppins',
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
        ),
        Text(
          label,
          style: const TextStyle(
            fontFamily: 'Poppins',
            fontSize: 10,
            color: _CustomerDetailScreenState._muted,
          ),
        ),
      ],
    ),
  );
}

class ClubViewScreen extends StatelessWidget {
  const ClubViewScreen({super.key, required this.customerId});

  final String customerId;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);

    final customer = state.customerById(customerId);

    if (customer == null) {
      return const Scaffold(body: Center(child: Text('Cliente no encontrado')));
    }

    final pointProgram = state.data.programs
        .where(
          (program) =>
              program.active &&
              !program.isExpired &&
              program.type == ProgramType.points &&
              program.tiers.isNotEmpty,
        )
        .firstOrNull;

    final pointBalance = pointProgram == null
        ? customer.points
        : customer.cardBalances[pointProgram.id]?.points ?? customer.points;

    return Scaffold(
      appBar: AppBar(title: const Text('Mi club')),

      body: ListView(
        padding: const EdgeInsets.all(20),

        children: [
          Text(
            state.data.business.name,

            style: Theme.of(context).textTheme.headlineMedium,

            textAlign: TextAlign.center,
          ),

          const SizedBox(height: 8),

          Text(
            'Hola, ${customer.name}',

            style: Theme.of(context).textTheme.titleLarge,

            textAlign: TextAlign.center,
          ),

          const SizedBox(height: 20),

          Center(
            child: QrImageView(
              data: state.referralQrPayload(customer),

              size: 220,
            ),
          ),

          const SizedBox(height: 12),

          if (pointProgram != null)
            Text(
              '$pointBalance puntos · nivel ${customer.tier}',

              textAlign: TextAlign.center,
            ),

          Text(
            '${customer.stamps} sellos · ${customer.visits} visitas',

            textAlign: TextAlign.center,
          ),

          const SizedBox(height: 24),

          Text(
            'Tus recompensas',

            style: Theme.of(context).textTheme.titleLarge,
          ),

          for (final reward in state.data.rewards.where(
            (reward) => customer.unlockedRewardIds.contains(reward.id),
          ))
            ListTile(
              leading: const Icon(Icons.card_giftcard),

              title: Text(reward.name),

              subtitle: const Text('Disponible para canjear en el comercio'),
            ),

          if (customer.unlockedRewardIds.isEmpty)
            const ListTile(
              title: Text('Sigue acumulando para desbloquear recompensas.'),
            ),

          const SizedBox(height: 16),

          Text(
            'Comparte este QR. Si un amigo se registra, ganas 50 puntos. Código ${customer.referralCode}',

            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
