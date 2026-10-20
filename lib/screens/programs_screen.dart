import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../models/app_data.dart';
import '../services/wallet_service.dart';
import '../state/app_scope.dart';
import '../theme/fideli_theme.dart';
import '../widgets/common.dart';
import '../widgets/program_qr_sheet.dart';

class ProgramsScreen extends StatelessWidget {
  const ProgramsScreen({
    super.key,
    this.walletService,
    this.openCreatorOnStart = false,
  });

  final WalletService? walletService;
  final bool openCreatorOnStart;

  WalletService get _wallet => walletService ?? WalletService();

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);

    final programs = state.data.programs;
    final active = programs
        .where((item) => item.active && !item.isExpired)
        .length;

    Widget cardFor(LoyaltyProgram item) => _ProgramCard(
      program: item,
      details: _programSummary(state.data.rewards, item),
      onTap: () => _editProgram(context, program: item),
      onQrTap: () => showProgramQrSheet(context, item),
      onChanged: item.isExpired
          ? null
          : (value) async {
              item.active = value;
              // La activación del programa pertenece al estado de Fideli y no
              // debe depender de que Apple/Google Wallet estén disponibles.
              // Primero se guarda y sincroniza el programa; Wallet se actualiza
              // después como una operación complementaria.
              await state.commitAndSync();
              final result = await _wallet.syncProgram(
                state.data.business,
                item,
              );
              if (!context.mounted) return;
              final status = value ? 'Tarjeta activada' : 'Tarjeta desactivada';
              showMessage(
                context,
                result.ok
                    ? status
                    : '$status. Wallet se actualizará cuando vuelva a estar disponible.',
              );
            },
    );

    final content = Scaffold(
      backgroundColor: FideliTheme.canvas,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            final compact = width < 690;
            final gutter = compact ? 18.0 : 34.0;
            final contentWidth = (width - gutter * 2)
                .clamp(0.0, 1040.0)
                .toDouble();
            final columns = contentWidth >= 1050
                ? 3
                : contentWidth >= 680
                ? 2
                : 1;
            const gap = 18.0;
            final cardWidth = (contentWidth - gap * (columns - 1)) / columns;
            return SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                gutter,
                compact ? 24 : 42,
                gutter,
                64,
              ),
              child: Align(
                alignment: Alignment.topCenter,
                child: SizedBox(
                  width: contentWidth,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 18,
                        runSpacing: 16,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          SizedBox(
                            width: compact ? contentWidth : contentWidth - 210,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Mis tarjetas',
                                  style: TextStyle(
                                    fontFamily: 'Poppins',
                                    fontSize: 30,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: -1.1,
                                    color: Color(0xFF282329),
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  'Gestiona tus programas de fidelización',
                                  style: TextStyle(
                                    fontFamily: 'Poppins',
                                    fontSize: 13,
                                    color: Colors.black.withValues(alpha: .48),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          SizedBox(
                            width: compact ? contentWidth : 192,
                            height: 48,
                            child: FilledButton(
                              onPressed: () => _editProgram(context),
                              style: FilledButton.styleFrom(
                                backgroundColor: FideliTheme.ink,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(18),
                                ),
                              ),
                              child: const Text('Nueva tarjeta'),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 28),
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: [
                          _ProgramMetric(
                            label: 'Total de tarjetas',
                            value: '${programs.length}',
                          ),
                          _ProgramMetric(label: 'Activas', value: '$active'),
                          _ProgramMetric(
                            label: 'Inactivas',
                            value: '${programs.length - active}',
                          ),
                        ],
                      ),
                      const SizedBox(height: 32),
                      if (programs.isEmpty)
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 72,
                          ),
                          decoration: BoxDecoration(
                            color: FideliTheme.surfaceSoft,
                            borderRadius: BorderRadius.circular(28),
                            border: Border.all(color: FideliTheme.line),
                          ),
                          child: Column(
                            children: [
                              const Icon(
                                Icons.wallet_outlined,
                                size: 54,
                                color: FideliTheme.ink,
                              ),
                              const SizedBox(height: 16),
                              const Text(
                                'Todavía no tienes tarjetas',
                                style: TextStyle(
                                  fontFamily: 'Poppins',
                                  fontWeight: FontWeight.w600,
                                  fontSize: 17,
                                ),
                              ),
                              const SizedBox(height: 7),
                              const Text(
                                'Crea tu primer programa para empezar.',
                                style: TextStyle(color: Color(0xFF8A8280)),
                              ),
                              const SizedBox(height: 20),
                              OutlinedButton(
                                onPressed: () => _editProgram(context),
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 22,
                                    vertical: 16,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                ),
                                child: const Text('Crear tarjeta'),
                              ),
                            ],
                          ),
                        )
                      else
                        Wrap(
                          spacing: gap,
                          runSpacing: gap,
                          children: [
                            for (final item in programs)
                              SizedBox(width: cardWidth, child: cardFor(item)),
                          ],
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
    if (!openCreatorOnStart) return content;
    return _OpenProgramCreatorOnce(
      onOpen: () => _editProgram(context),
      child: content,
    );
  }

  // =========================================================
  // CREAR / EDITAR
  // =========================================================

  Future<void> _editProgram(
    BuildContext context, {
    LoyaltyProgram? program,
  }) async {
    final state = AppScope.of(context);
    final pageContext = context;

    final programId = program?.id ?? newId('program');

    final existingRewards = state.data.rewards
        .where((reward) => reward.programId == programId)
        .toList();

    final existingReward = existingRewards
        .where((reward) => reward.programId == programId)
        .firstOrNull;

    // =========================================================
    // CONTROLADORES EXISTENTES
    // =========================================================

    final name = TextEditingController(
      text: program?.name ?? _defaultProgramName('Sellos'),
    );

    final rate = TextEditingController(text: '${program?.earningRate ?? 1}');

    final goal = TextEditingController(text: '${program?.goal ?? 10}');

    final stampMessage = TextEditingController(
      text:
          program?.stampNotificationMessage ??
          '¡Ya tienes {sellos} sellos! Sigue así.',
    );

    final rewardName = TextEditingController(
      text:
          program?.stampMilestones
              .where((item) => item.stamp == program.goal)
              .firstOrNull
              ?.reward ??
          existingReward?.name ??
          'Producto de cortesía',
    );

    final existingCost = existingReward == null
        ? program?.goal ?? 10
        : existingReward.pointsCost > 0
        ? existingReward.pointsCost
        : existingReward.stampsCost;

    final rewardCost = TextEditingController(text: '$existingCost');

    // =========================================================
    // SOLO FRONTEND POR AHORA
    // =========================================================

    final welcomeMessage = TextEditingController(
      text: program?.welcomeMessage ?? '¡Bienvenido! Nos alegra tenerte aquí.',
    );

    final completedMessage = TextEditingController(
      text:
          program?.stampMilestones
              .where((item) => item.stamp == program.goal)
              .firstOrNull
              ?.message ??
          program?.completionMessage ??
          '🎉 ¡Completaste tu tarjeta! Tu recompensa está lista.',
    );

    // =========================================================
    // TIPO
    // =========================================================

    var cardChoice = program == null
        ? 'Sellos'
        : program.cardKind == 'Tarjeta de regalo'
        ? 'Tarjeta de regalo'
        : program.cardKind == 'Membresía'
        ? 'Membresía'
        : program.type == ProgramType.points
        ? 'Puntos'
        : 'Sellos';

    // =========================================================
    // VENCIMIENTO
    // =========================================================

    DateTime? expiresAt = program?.expiresAt;

    final now = DateTime.now();

    final normalizedToday = DateTime(now.year, now.month, now.day);

    // Supabase devuelve fechas UTC. La rueda siempre trabaja en hora local y
    // debe reabrirse exactamente en la posición que guardó el comercio.
    final initialPickerDate = expiresAt?.toLocal() ?? now;

    final normalizedInitial = DateTime(
      initialPickerDate.year,
      initialPickerDate.month,
      initialPickerDate.day,
    );

    var initialDayIndex = normalizedInitial.difference(normalizedToday).inDays;

    if (initialDayIndex < 0) {
      initialDayIndex = 0;
    }

    if (initialDayIndex > 364) {
      initialDayIndex = 364;
    }

    DateTime pickerDate = DateTime(
      normalizedToday.add(Duration(days: initialDayIndex)).year,
      normalizedToday.add(Duration(days: initialDayIndex)).month,
      normalizedToday.add(Duration(days: initialDayIndex)).day,
      initialPickerDate.hour,
      initialPickerDate.minute,
    );

    bool useExpiration = expiresAt != null;

    final dateController = FixedExtentScrollController(
      initialItem: initialDayIndex,
    );

    final hourController = FixedExtentScrollController(
      initialItem: pickerDate.hour,
    );

    final minuteController = FixedExtentScrollController(
      initialItem: pickerDate.minute,
    );

    // =========================================================
    // NIVELES
    // =========================================================

    final tierDrafts = program != null && program.tiers.isNotEmpty
        ? program.tiers
              .map((tier) => _TierDraft(tier.name, '${tier.threshold}'))
              .toList()
        : [
            _TierDraft('Bronce', '0'),
            _TierDraft('Plata', '500'),
            _TierDraft('Oro', '1500'),
            _TierDraft('VIP', '3000'),
          ];

    final stampMilestoneDrafts = (program?.stampMilestones ?? const [])
        .where((item) => item.stamp != program?.goal)
        .map(
          (item) => _StampMilestoneDraft(
            id: item.id,
            stamp: '${item.stamp}',
            reward: item.reward,
            message: item.message,
          ),
        )
        .toList();

    // =========================================================
    // BOTTOM SHEET
    // =========================================================

    Widget editorContent(
      BuildContext sheetContext,
      ScrollController scrollController,
    ) {
      return StatefulBuilder(
        builder: (context, setDialogState) {
          const Color sheetBackground = Color(0xFFFCFCFB);

          const Color cardColor = FideliTheme.surfaceSoft;

          const Color primaryColor = FideliTheme.ink;

          const Color primaryText = Color(0xFF2D2829);

          const Color secondaryText = Color(0xFF8A8280);

          return Container(
            color: sheetBackground,
            child: Column(
              children: [
                // =================================================
                // HEADER ESTILO APPLE
                // =================================================
                Padding(
                  padding: const EdgeInsets.fromLTRB(22, 8, 22, 18),
                  child: Row(
                    children: [
                      // =============================================
                      // X
                      // =============================================
                      _TopCircleButton(
                        icon: Icons.close_rounded,
                        onTap: () {
                          Navigator.pop(sheetContext, false);
                        },
                      ),

                      // =============================================
                      // TÍTULO
                      // =============================================
                      Expanded(
                        child: Column(
                          children: [
                            Text(
                              program == null
                                  ? 'Nueva tarjeta'
                                  : 'Editar tarjeta',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontFamily: 'Poppins',
                                fontSize: 21,
                                fontWeight: FontWeight.w700,
                                letterSpacing: -.5,
                                color: primaryText,
                              ),
                            ),
                            const SizedBox(height: 2),
                            const Text(
                              'Configura solo lo necesario',
                              style: TextStyle(
                                fontSize: 11.5,
                                color: secondaryText,
                              ),
                            ),
                          ],
                        ),
                      ),

                      // =============================================
                      // CHECK
                      // =============================================
                      _TopCircleButton(
                        icon: Icons.check_rounded,
                        filled: true,
                        onTap: () {
                          if (useExpiration) {
                            expiresAt = pickerDate;
                          } else {
                            expiresAt = null;
                          }

                          Navigator.pop(sheetContext, true);
                        },
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1, color: FideliTheme.line),

                // =================================================
                // CONTENIDO
                // =================================================
                Expanded(
                  child: SingleChildScrollView(
                    controller: scrollController,
                    padding: const EdgeInsets.fromLTRB(22, 22, 22, 42),
                    child: Column(
                      children: [
                        // ===========================================
                        // PICKER FECHA / HORA / MINUTO
                        // ===========================================
                        Container(
                          height: 220,
                          decoration: BoxDecoration(
                            color: cardColor,
                            borderRadius: BorderRadius.circular(24),
                            border: Border.all(color: FideliTheme.line),
                          ),
                          child: Column(
                            children: [
                              // =====================================
                              // CABECERA DEL PICKER
                              // =====================================
                              Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  18,
                                  14,
                                  12,
                                  4,
                                ),
                                child: Row(
                                  children: [
                                    const Expanded(
                                      child: Text(
                                        'Vencimiento',
                                        style: TextStyle(
                                          fontFamily: 'Poppins',
                                          fontSize: 16,
                                          fontWeight: FontWeight.w600,
                                          color: primaryText,
                                        ),
                                      ),
                                    ),

                                    Switch.adaptive(
                                      value: useExpiration,
                                      activeTrackColor: primaryColor,
                                      onChanged: (value) {
                                        setDialogState(() {
                                          useExpiration = value;

                                          expiresAt = value ? pickerDate : null;
                                        });
                                      },
                                    ),
                                  ],
                                ),
                              ),

                              // =====================================
                              // RUEDAS
                              // =====================================
                              Expanded(
                                child: IgnorePointer(
                                  ignoring: !useExpiration,
                                  child: AnimatedOpacity(
                                    duration: const Duration(milliseconds: 200),
                                    opacity: useExpiration ? 1 : 0.32,
                                    child: Row(
                                      children: [
                                        // =============================
                                        // FECHA
                                        // =============================
                                        Expanded(
                                          flex: 5,
                                          child: CupertinoPicker.builder(
                                            scrollController: dateController,
                                            itemExtent: 42,
                                            useMagnifier: true,
                                            magnification: 1.07,
                                            selectionOverlay:
                                                CupertinoPickerDefaultSelectionOverlay(
                                                  background: primaryColor
                                                      .withValues(alpha: 0.07),
                                                  capStartEdge: true,
                                                  capEndEdge: false,
                                                ),
                                            childCount: 365,
                                            onSelectedItemChanged: (index) {
                                              final selected = normalizedToday
                                                  .add(Duration(days: index));

                                              setDialogState(() {
                                                pickerDate = DateTime(
                                                  selected.year,
                                                  selected.month,
                                                  selected.day,
                                                  pickerDate.hour,
                                                  pickerDate.minute,
                                                );

                                                if (useExpiration) {
                                                  expiresAt = pickerDate;
                                                }
                                              });
                                            },
                                            itemBuilder: (context, index) {
                                              final date = normalizedToday.add(
                                                Duration(days: index),
                                              );

                                              return Center(
                                                child: Text(
                                                  _prettyDate(date),
                                                  style: const TextStyle(
                                                    fontFamily: 'Poppins',
                                                    fontSize: 16,
                                                    color: primaryText,
                                                  ),
                                                ),
                                              );
                                            },
                                          ),
                                        ),

                                        const SizedBox(width: 4),

                                        // =============================
                                        // HORA
                                        // =============================
                                        Expanded(
                                          flex: 2,
                                          child: CupertinoPicker.builder(
                                            scrollController: hourController,
                                            itemExtent: 42,
                                            useMagnifier: true,
                                            magnification: 1.08,
                                            selectionOverlay:
                                                CupertinoPickerDefaultSelectionOverlay(
                                                  background: primaryColor
                                                      .withValues(alpha: 0.07),
                                                  capStartEdge: false,
                                                  capEndEdge: false,
                                                ),
                                            childCount: 24,
                                            onSelectedItemChanged: (hour) {
                                              setDialogState(() {
                                                pickerDate = DateTime(
                                                  pickerDate.year,
                                                  pickerDate.month,
                                                  pickerDate.day,
                                                  hour,
                                                  pickerDate.minute,
                                                );

                                                if (useExpiration) {
                                                  expiresAt = pickerDate;
                                                }
                                              });
                                            },
                                            itemBuilder: (context, index) {
                                              return Center(
                                                child: Text(
                                                  index.toString().padLeft(
                                                    2,
                                                    '0',
                                                  ),
                                                  style: const TextStyle(
                                                    fontFamily: 'Poppins',
                                                    fontSize: 18,
                                                    color: primaryText,
                                                  ),
                                                ),
                                              );
                                            },
                                          ),
                                        ),

                                        const Text(
                                          ':',
                                          style: TextStyle(
                                            fontFamily: 'Poppins',
                                            fontSize: 18,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),

                                        // =============================
                                        // MINUTOS
                                        // =============================
                                        Expanded(
                                          flex: 2,
                                          child: CupertinoPicker.builder(
                                            scrollController: minuteController,
                                            itemExtent: 42,
                                            useMagnifier: true,
                                            magnification: 1.08,
                                            selectionOverlay:
                                                CupertinoPickerDefaultSelectionOverlay(
                                                  background: primaryColor
                                                      .withValues(alpha: 0.07),
                                                  capStartEdge: false,
                                                  capEndEdge: true,
                                                ),
                                            childCount: 60,
                                            onSelectedItemChanged: (minute) {
                                              setDialogState(() {
                                                pickerDate = DateTime(
                                                  pickerDate.year,
                                                  pickerDate.month,
                                                  pickerDate.day,
                                                  pickerDate.hour,
                                                  minute,
                                                );

                                                if (useExpiration) {
                                                  expiresAt = pickerDate;
                                                }
                                              });
                                            },
                                            itemBuilder: (context, index) {
                                              return Center(
                                                child: Text(
                                                  index.toString().padLeft(
                                                    2,
                                                    '0',
                                                  ),
                                                  style: const TextStyle(
                                                    fontFamily: 'Poppins',
                                                    fontSize: 18,
                                                    color: primaryText,
                                                  ),
                                                ),
                                              );
                                            },
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 22),

                        // ===========================================
                        // DATOS DEL PROGRAMA
                        // ===========================================
                        const _SectionTitle(text: 'PROGRAMA'),

                        _AppleSection(
                          children: [
                            _AppleTextFieldRow(
                              label: 'Nombre',
                              controller: name,
                              hint: 'Nombre del programa',
                            ),

                            const _AppleDivider(),

                            _AppleDropdownRow(
                              label: 'Tipo',
                              value: cardChoice,
                              values: const [
                                'Sellos',
                                'Puntos',
                                'Membresía',
                                'Tarjeta de regalo',
                              ],
                              onChanged: (value) {
                                if (value == null) {
                                  return;
                                }

                                setDialogState(() {
                                  final previousChoice = cardChoice;
                                  final currentName = name.text.trim();
                                  if (program == null &&
                                      (currentName.isEmpty ||
                                          currentName ==
                                              _defaultProgramName(
                                                previousChoice,
                                              ))) {
                                    name.text = _defaultProgramName(value);
                                    name.selection = TextSelection.collapsed(
                                      offset: name.text.length,
                                    );
                                  }
                                  cardChoice = value;
                                });
                              },
                            ),

                            if (cardChoice != 'Membresía') ...[
                              const _AppleDivider(),

                              _AppleTextFieldRow(
                                label: switch (cardChoice) {
                                  'Sellos' => 'Meta de sellos',
                                  'Puntos' => 'Meta de puntos',
                                  'Tarjeta de regalo' => 'Saldo',
                                  _ => 'Accesos',
                                },
                                controller: goal,
                                keyboardType: TextInputType.number,
                                hint: '10',
                              ),
                            ],
                          ],
                        ),

                        const SizedBox(height: 22),
                        const _SectionTitle(text: 'MENSAJES'),
                        _AppleSection(
                          children: [
                            _AppleMessageField(
                              title: 'Mensaje de bienvenida',
                              subtitle:
                                  'Se mostrará cuando el cliente reciba su tarjeta.',
                              controller: welcomeMessage,
                            ),
                            if (cardChoice == 'Sellos' ||
                                cardChoice == 'Puntos') ...[
                              const _AppleDivider(),
                              _AppleMessageField(
                                title: cardChoice == 'Sellos'
                                    ? 'Mensaje al recibir un sello'
                                    : 'Mensaje de progreso',
                                subtitle: cardChoice == 'Sellos'
                                    ? 'Se usa cuando ese sello no tiene un premio especial.'
                                    : 'Mensaje mostrado cuando el cliente avance.',
                                controller: stampMessage,
                              ),
                            ],
                            if (cardChoice == 'Puntos') ...[
                              const _AppleDivider(),
                              _AppleMessageField(
                                title: 'Mensaje al completar',
                                subtitle:
                                    'Aparecerá cuando complete la meta definida.',
                                controller: completedMessage,
                              ),
                            ],
                          ],
                        ),

                        if (cardChoice == 'Sellos') ...[
                          const SizedBox(height: 22),
                          const _SectionTitle(text: 'PREMIOS POR SELLO'),
                          _AppleSection(
                            children: [
                              for (final entry
                                  in stampMilestoneDrafts.indexed) ...[
                                _StampMilestoneEditor(
                                  draft: entry.$2,
                                  onRemove: () {
                                    setDialogState(() {
                                      final removed = stampMilestoneDrafts
                                          .removeAt(entry.$1);
                                      removed.dispose();
                                    });
                                  },
                                ),
                                const _AppleDivider(),
                              ],
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 6,
                                ),
                                child: Align(
                                  alignment: Alignment.centerLeft,
                                  child: TextButton.icon(
                                    onPressed: () {
                                      setDialogState(() {
                                        stampMilestoneDrafts.add(
                                          _StampMilestoneDraft(
                                            id: newId('milestone'),
                                            stamp: '',
                                            reward: '',
                                            message: '',
                                          ),
                                        );
                                      });
                                    },
                                    icon: const Icon(Icons.add_rounded),
                                    label: const Text('Agregar premio'),
                                  ),
                                ),
                              ),
                              const _AppleDivider(),
                              _AppleTextFieldRow(
                                label: 'Premio final',
                                controller: rewardName,
                                hint: 'Ej. Café gratis',
                              ),
                              const _AppleDivider(),
                              _AppleMessageField(
                                title: 'Notificación final',
                                subtitle:
                                    'Se envía al completar todos los sellos.',
                                controller: completedMessage,
                              ),
                            ],
                          ),
                        ],

                        // ===========================================
                        // NIVELES
                        // ===========================================
                        if (cardChoice == 'Puntos') ...[
                          const SizedBox(height: 22),

                          const _SectionTitle(text: 'NIVELES'),

                          _AppleSection(
                            children: [
                              Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  18,
                                  14,
                                  18,
                                  8,
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'Niveles de este programa',
                                      style: TextStyle(
                                        fontFamily: 'Poppins',
                                        fontSize: 15,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),

                                    const SizedBox(height: 3),

                                    const Text(
                                      'Define el nombre y los puntos necesarios.',
                                      style: TextStyle(
                                        fontFamily: 'Poppins',
                                        fontSize: 11.5,
                                        color: secondaryText,
                                      ),
                                    ),

                                    const SizedBox(height: 12),

                                    for (final entry in tierDrafts.indexed)
                                      Padding(
                                        padding: const EdgeInsets.only(
                                          bottom: 10,
                                        ),
                                        child: Row(
                                          children: [
                                            Expanded(
                                              child: TextField(
                                                controller: entry.$2.name,
                                                decoration: InputDecoration(
                                                  hintText: 'Nivel',
                                                  filled: true,
                                                  fillColor: Colors.white,
                                                  border: OutlineInputBorder(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          15,
                                                        ),
                                                    borderSide:
                                                        const BorderSide(
                                                          color:
                                                              FideliTheme.line,
                                                        ),
                                                  ),
                                                  contentPadding:
                                                      const EdgeInsets.symmetric(
                                                        horizontal: 12,
                                                        vertical: 12,
                                                      ),
                                                ),
                                              ),
                                            ),

                                            const SizedBox(width: 8),

                                            SizedBox(
                                              width: 95,
                                              child: TextField(
                                                controller: entry.$2.threshold,
                                                keyboardType:
                                                    TextInputType.number,
                                                decoration: InputDecoration(
                                                  hintText: 'Puntos',
                                                  filled: true,
                                                  fillColor: Colors.white,
                                                  border: OutlineInputBorder(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          15,
                                                        ),
                                                    borderSide:
                                                        const BorderSide(
                                                          color:
                                                              FideliTheme.line,
                                                        ),
                                                  ),
                                                  contentPadding:
                                                      const EdgeInsets.symmetric(
                                                        horizontal: 12,
                                                        vertical: 12,
                                                      ),
                                                ),
                                              ),
                                            ),

                                            IconButton(
                                              onPressed: tierDrafts.length == 1
                                                  ? null
                                                  : () {
                                                      setDialogState(() {
                                                        final removed =
                                                            tierDrafts.removeAt(
                                                              entry.$1,
                                                            );

                                                        removed.dispose();
                                                      });
                                                    },
                                              icon: const Icon(
                                                Icons
                                                    .remove_circle_outline_rounded,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),

                                    TextButton.icon(
                                      onPressed: () {
                                        setDialogState(() {
                                          final previous =
                                              int.tryParse(
                                                tierDrafts.last.threshold.text,
                                              ) ??
                                              0;

                                          tierDrafts.add(
                                            _TierDraft(
                                              'Nuevo nivel',
                                              '${previous + 500}',
                                            ),
                                          );
                                        });
                                      },
                                      icon: const Icon(Icons.add_rounded),
                                      label: const Text('Agregar nivel'),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ],

                        // ===========================================
                        // RECOMPENSA
                        // ===========================================
                        if (cardChoice == 'Puntos') ...[
                          const SizedBox(height: 22),

                          const _SectionTitle(text: 'RECOMPENSA'),

                          _AppleSection(
                            children: [
                              _AppleTextFieldRow(
                                label: 'Premio',
                                controller: rewardName,
                                hint: 'Ej. Café gratis',
                              ),

                              const _AppleDivider(),

                              _AppleTextFieldRow(
                                label: 'Puntos necesarios',
                                controller: rewardCost,
                                keyboardType: TextInputType.number,
                                hint: '10',
                              ),
                            ],
                          ),
                        ],

                        // ===========================================
                        // ELIMINAR
                        // ===========================================
                        if (program != null) ...[
                          const SizedBox(height: 28),

                          SizedBox(
                            width: double.infinity,
                            height: 56,
                            child: TextButton.icon(
                              onPressed: () async {
                                final confirmed = await _confirmDeleteProgram(
                                  sheetContext,
                                  program,
                                );
                                if (!confirmed || !sheetContext.mounted) {
                                  return;
                                }
                                // Cierra y desmonta completamente el editor
                                // antes de retirar el programa del AppScope.
                                Navigator.pop(sheetContext, false);
                                await Future<void>.delayed(
                                  const Duration(milliseconds: 380),
                                );
                                if (pageContext.mounted) {
                                  await _deleteProgram(pageContext, program);
                                }
                              },
                              style: TextButton.styleFrom(
                                foregroundColor: Colors.red,
                                backgroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(24),
                                ),
                              ),
                              icon: const Icon(Icons.delete_outline_rounded),
                              label: const Text(
                                'Eliminar programa',
                                style: TextStyle(
                                  fontFamily: 'Poppins',
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                        ],

                        const SizedBox(height: 30),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      );
    }

    // Ambos flujos (crear y editar) utilizan exactamente la misma ruta.
    // La transición está coordinada con el teclado y mantiene el
    // formulario existente, sin cambiar el guardado ni la sincronización.
    final accepted = await _showSilkKeyboardSheet<bool>(
      context: context,
      builder: editorContent,
    );

    // =========================================================
    // GUARDAR
    // =========================================================

    if (accepted == true && context.mounted) {
      final type = switch (cardChoice) {
        'Puntos' || 'Tarjeta de regalo' => ProgramType.points,

        'Membresía' => ProgramType.membership,

        _ => ProgramType.stamps,
      };

      final cardKind = switch (cardChoice) {
        'Membresía' => 'Membresía',

        'Tarjeta de regalo' => 'Tarjeta de regalo',

        _ => 'Fidelización',
      };

      final designType = switch (cardChoice) {
        'Tarjeta de regalo' => 'gift',
        'Membresía' => 'membership',
        'Puntos' => 'points',
        _ => 'stamps',
      };
      final savedDesign = state.data.wallet.templateFor(designType);
      final parsedGoal = int.tryParse(goal.text) ?? 10;
      final safeGoal = parsedGoal < 1 ? 1 : parsedGoal;
      final milestoneByStamp = <int, StampMilestone>{};
      if (cardChoice == 'Sellos') {
        for (final draft in stampMilestoneDrafts) {
          final stamp = int.tryParse(draft.stamp.text) ?? 0;
          final reward = draft.reward.text.trim();
          final message = draft.message.text.trim();
          if (stamp < 1 || stamp >= safeGoal) continue;
          if (reward.isEmpty && message.isEmpty) continue;
          milestoneByStamp[stamp] = StampMilestone(
            id: draft.id.isEmpty ? newId('milestone') : draft.id,
            stamp: stamp,
            reward: reward,
            message: message.isEmpty ? '¡Ganaste $reward!' : message,
          );
        }
        milestoneByStamp[safeGoal] = StampMilestone(
          id:
              program?.stampMilestones
                  .where((item) => item.stamp == program.goal)
                  .firstOrNull
                  ?.id ??
              newId('milestone'),
          stamp: safeGoal,
          reward: rewardName.text.trim(),
          message: completedMessage.text.trim().isEmpty
              ? '🎉 ¡Completaste tu tarjeta! Tu recompensa está lista.'
              : completedMessage.text.trim(),
        );
      }
      final stampMilestones = milestoneByStamp.values.toList()
        ..sort((a, b) => a.stamp.compareTo(b.stamp));

      final savedProgram = LoyaltyProgram(
        id: programId,
        name: name.text.trim().isEmpty
            ? _defaultProgramName(cardChoice)
            : name.text.trim(),
        type: type,

        earningRate: int.tryParse(rate.text) ?? 1,

        goal: cardChoice == 'Membresía' ? 1 : safeGoal,

        cardKind: cardKind,
        colorHex: savedDesign.colorHex,
        backgroundImagePath: savedDesign.backgroundImagePath,
        stampIcon: savedDesign.stampIcon,
        walletLayout: savedDesign.walletLayout,

        stampNotificationMessage:
            cardChoice == 'Sellos' || cardChoice == 'Puntos'
            ? (stampMessage.text.trim().isEmpty
                  ? '¡Ya tienes {sellos} sellos! Sigue así.'
                  : stampMessage.text.trim())
            : '',

        welcomeMessage: welcomeMessage.text.trim().isEmpty
            ? '¡Bienvenido! Nos alegra tenerte aquí.'
            : welcomeMessage.text.trim(),

        completionMessage: cardChoice == 'Sellos' || cardChoice == 'Puntos'
            ? (completedMessage.text.trim().isEmpty
                  ? '🎉 ¡Completaste tu tarjeta! Tu recompensa está lista.'
                  : completedMessage.text.trim())
            : '',

        expiresAt: useExpiration ? pickerDate : null,

        tiers: cardChoice == 'Puntos'
            ? tierDrafts
                  .where((draft) => draft.name.text.trim().isNotEmpty)
                  .map((draft) {
                    final parsed = int.tryParse(draft.threshold.text) ?? 0;

                    return TierRule(
                      id: newId('tier'),
                      name: draft.name.text.trim(),
                      threshold: parsed < 0 ? 0 : parsed,
                    );
                  })
                  .toList()
            : const [],
        stampMilestones: stampMilestones,
      );

      final desiredRewards = <Reward>[];
      if (type == ProgramType.stamps) {
        for (final milestone in savedProgram.stampMilestones) {
          if (milestone.reward.isEmpty) continue;
          desiredRewards.add(
            Reward(
              id: milestone.id,
              programId: programId,
              name: milestone.reward,
              stampsCost: milestone.stamp,
            ),
          );
        }
      } else if (type == ProgramType.points && cardChoice == 'Puntos') {
        final parsedCost = int.tryParse(rewardCost.text) ?? savedProgram.goal;
        final safeCost = parsedCost < 1 ? 1 : parsedCost;
        if (rewardName.text.trim().isNotEmpty) {
          desiredRewards.add(
            Reward(
              id: existingReward?.id ?? '',
              programId: programId,
              name: rewardName.text.trim(),
              pointsCost: safeCost,
            ),
          );
        }
      }

      final changed =
          program == null ||
          _programEditSignature(program, existingRewards) !=
              _programEditSignature(savedProgram, desiredRewards);

      if (!changed) {
        if (context.mounted) {
          showMessage(context, 'No hay cambios para guardar');
        }
      } else {
        // =======================================================
        // CREAR / ACTUALIZAR
        // =======================================================

        if (program == null) {
          state.data.programs.add(savedProgram);
        } else {
          program
            ..name = savedProgram.name
            ..type = savedProgram.type
            ..earningRate = savedProgram.earningRate
            ..goal = savedProgram.goal
            ..cardKind = savedProgram.cardKind
            ..expiresAt = savedProgram.expiresAt
            ..tiers = savedProgram.tiers
            ..stampMilestones = savedProgram.stampMilestones
            ..welcomeMessage = savedProgram.welcomeMessage
            ..stampNotificationMessage = savedProgram.stampNotificationMessage
            ..completionMessage = savedProgram.completionMessage;
        }

        // =======================================================
        // RECOMPENSA
        // =======================================================

        if (type == ProgramType.stamps) {
          state.data.rewards.removeWhere(
            (reward) => reward.programId == programId,
          );
          for (final milestone in savedProgram.stampMilestones) {
            if (milestone.reward.isEmpty) continue;
            state.data.rewards.add(
              Reward(
                id: milestone.id,
                programId: programId,
                name: milestone.reward,
                stampsCost: milestone.stamp,
              ),
            );
          }
        } else if (type == ProgramType.points && cardChoice == 'Puntos') {
          final parsedCost = int.tryParse(rewardCost.text) ?? savedProgram.goal;

          final safeCost = parsedCost < 1 ? 1 : parsedCost;

          if (rewardName.text.trim().isEmpty) {
            if (existingReward != null) {
              state.data.rewards.remove(existingReward);
            }
          } else if (existingReward == null) {
            state.data.rewards.add(
              Reward(
                id: newId('reward'),
                programId: programId,
                name: rewardName.text.trim(),
                pointsCost: type == ProgramType.points ? safeCost : 0,
                stampsCost: type == ProgramType.stamps ? safeCost : 0,
              ),
            );
          } else {
            existingReward
              ..name = rewardName.text.trim()
              ..pointsCost = type == ProgramType.points ? safeCost : 0
              ..stampsCost = type == ProgramType.stamps ? safeCost : 0
              ..active = true;
          }
        } else {
          state.data.rewards.removeWhere(
            (reward) => reward.programId == programId,
          );
        }

        final programToSync = program ?? state.data.programs.last;

        await state.commitAndSync();

        final result = await _wallet.syncProgram(
          state.data.business,
          programToSync,
        );

        if (context.mounted) {
          showMessage(
            context,
            result.ok ? 'Programa guardado' : result.message,
          );
          if (program == null && result.ok) {
            await showProgramQrSheet(context, programToSync);
          }
        }
      }
    }

    // =========================================================
    // DISPOSE
    // =========================================================

    name.dispose();
    rate.dispose();
    goal.dispose();

    stampMessage.dispose();

    welcomeMessage.dispose();
    completedMessage.dispose();

    rewardName.dispose();
    rewardCost.dispose();

    dateController.dispose();
    hourController.dispose();
    minuteController.dispose();

    for (final draft in tierDrafts) {
      draft.dispose();
    }
    for (final draft in stampMilestoneDrafts) {
      draft.dispose();
    }
  }

  // =========================================================
  // ELIMINAR
  // =========================================================

  Future<bool> _confirmDeleteProgram(
    BuildContext context,
    LoyaltyProgram program,
  ) async {
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('¿Borrar ${program.name}?'),

        content: const Text(
          'La tarjeta dejará de estar disponible y las copias instaladas quedarán marcadas como vencidas/anuladas. Apple no permite borrarlas físicamente a distancia.',
        ),

        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),

          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Borrar tarjeta'),
          ),
        ],
      ),
    );

    return accepted == true;
  }

  Future<void> _deleteProgram(
    BuildContext context,
    LoyaltyProgram program,
  ) async {
    if (!context.mounted) return;
    final state = AppScope.of(context);
    late final WalletResult result;
    await state.runRemoteMutation(() async {
      final programIndex = state.data.programs.indexWhere(
        (item) => item.id == program.id,
      );
      final removedRewards = state.data.rewards
          .where((reward) => reward.programId == program.id)
          .toList();
      final rewardIds = state.data.rewards
          .where((reward) => reward.programId == program.id)
          .map((reward) => reward.id)
          .toSet();
      final removedBalances = <String, CardBalance>{};
      final previousUnlocked = <String, List<String>>{};
      final previousRedeemed = <String, List<String>>{};

      state.data.rewards.removeWhere(
        (reward) => reward.programId == program.id,
      );

      // La sincronización en tiempo real puede reemplazar las instancias de
      // los modelos mientras la petición de borrado está en curso. Se elimina
      // por identificador para que el programa no reaparezca por esa carrera.
      state.data.programs.removeWhere((item) => item.id == program.id);

      for (final customer in state.data.customers) {
        final balance = customer.cardBalances.remove(program.id);
        if (balance != null) removedBalances[customer.id] = balance;
        previousUnlocked[customer.id] = List<String>.from(
          customer.unlockedRewardIds,
        );
        previousRedeemed[customer.id] = List<String>.from(
          customer.redeemedRewardIds,
        );

        // Estas colecciones pueden venir de JSON como listas no expandibles
        // (o incluso de `const []`). Reemplazarlas evita el UnsupportedError
        // de removeWhere en Flutter web y garantiza que el borrado continúe.
        customer.unlockedRewardIds = customer.unlockedRewardIds
            .where((id) => !rewardIds.contains(id))
            .toList();
        customer.redeemedRewardIds = customer.redeemedRewardIds
            .where((id) => !rewardIds.contains(id))
            .toList();
      }
      await state.commitLocalOnly();

      result = await _wallet.expireProgram(state.data.business, program);
      if (result.ok) return;

      if (programIndex >= 0) {
        state.data.programs.insert(
          programIndex.clamp(0, state.data.programs.length).toInt(),
          program,
        );
      }
      state.data.rewards.addAll(removedRewards);
      for (final customer in state.data.customers) {
        final balance = removedBalances[customer.id];
        if (balance != null) customer.cardBalances[program.id] = balance;
        customer.unlockedRewardIds = previousUnlocked[customer.id] ?? const [];
        customer.redeemedRewardIds = previousRedeemed[customer.id] ?? const [];
      }
      await state.commitLocalOnly();
    });

    if (context.mounted) {
      showMessage(context, result.message);
    }
  }

  // =========================================================
  // RECOMPENSA
  // =========================================================

  String _rewardSummary(List<Reward> rewards, LoyaltyProgram program) {
    if (program.type != ProgramType.stamps &&
        program.type != ProgramType.points) {
      return '';
    }

    if (program.type == ProgramType.stamps &&
        program.stampMilestones.isNotEmpty) {
      final count = program.stampMilestones
          .where((item) => item.reward.isNotEmpty)
          .length;
      return count == 1
          ? '1 premio configurado\n'
          : '$count premios configurados\n';
    }

    final reward = rewards
        .where((item) => item.programId == program.id)
        .firstOrNull;

    if (reward == null) {
      return 'Sin recompensa definida\n';
    }

    final cost = program.type == ProgramType.stamps
        ? '${reward.stampsCost} sellos'
        : '${reward.pointsCost} puntos';

    return 'Recompensa: ${reward.name} · $cost\n';
  }

  String _programSummary(List<Reward> rewards, LoyaltyProgram program) {
    final expiry = program.expiresAt?.toLocal().toString().split(' ').first;
    if (program.cardKind == 'Tarjeta de regalo') {
      return expiry == null
          ? 'Tarjeta de regalo · Sin vencimiento'
          : program.isExpired
          ? 'Tarjeta de regalo · Venció $expiry'
          : 'Tarjeta de regalo · Vence $expiry';
    }
    return '${program.cardKind} · ${program.type.label} · meta ${program.goal}'
        '${program.type == ProgramType.points ? ' · ${program.tiers.length} niveles' : ''}\n'
        '${_rewardSummary(rewards, program)}'
        '${expiry == null
            ? 'Sin vencimiento'
            : program.isExpired
            ? 'Vencida'
            : 'Vence $expiry'}';
  }
}

class _OpenProgramCreatorOnce extends StatefulWidget {
  const _OpenProgramCreatorOnce({required this.onOpen, required this.child});

  final VoidCallback onOpen;
  final Widget child;

  @override
  State<_OpenProgramCreatorOnce> createState() =>
      _OpenProgramCreatorOnceState();
}

class _OpenProgramCreatorOnceState extends State<_OpenProgramCreatorOnce> {
  Animation<double>? _routeAnimation;
  VoidCallback? _routeListener;
  bool _opened = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _routeAnimation = ModalRoute.of(context)?.animation;
      if (_routeAnimation == null ||
          _routeAnimation!.status == AnimationStatus.completed) {
        _open();
        return;
      }
      _routeListener = () {
        if (_routeAnimation?.status != AnimationStatus.completed) return;
        _routeAnimation?.removeListener(_routeListener!);
        _routeListener = null;
        WidgetsBinding.instance.addPostFrameCallback((_) => _open());
      };
      _routeAnimation!.addListener(_routeListener!);
    });
  }

  void _open() {
    if (!mounted || _opened) return;
    _opened = true;
    widget.onOpen();
  }

  @override
  void dispose() {
    if (_routeListener != null) {
      _routeAnimation?.removeListener(_routeListener!);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _ProgramMetric extends StatelessWidget {
  const _ProgramMetric({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(minWidth: 164),
    padding: const EdgeInsets.symmetric(horizontal: 19, vertical: 15),
    decoration: BoxDecoration(
      color: FideliTheme.surfaceSoft,
      borderRadius: BorderRadius.circular(22),
      border: Border.all(color: FideliTheme.line),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          style: const TextStyle(
            fontFamily: 'Poppins',
            fontSize: 24,
            fontWeight: FontWeight.w700,
            color: FideliTheme.ink,
          ),
        ),
        Text(
          label,
          style: const TextStyle(
            fontFamily: 'Poppins',
            fontSize: 10.5,
            color: FideliTheme.muted,
          ),
        ),
      ],
    ),
  );
}

// ===========================================================
// TARJETA DE PROGRAMA
// ===========================================================

class _ProgramCard extends StatefulWidget {
  const _ProgramCard({
    required this.program,
    required this.details,
    required this.onTap,
    this.onQrTap,
    required this.onChanged,
  });

  final LoyaltyProgram program;

  final String details;

  final VoidCallback onTap;

  final VoidCallback? onQrTap;

  final Future<void> Function(bool)? onChanged;

  @override
  State<_ProgramCard> createState() => _ProgramCardState();
}

class _ProgramCardState extends State<_ProgramCard> {
  bool _saving = false;
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final program = widget.program;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: AnimatedScale(
        scale: _hovered ? 1.035 : 1,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutBack,
        child: Material(
          color: FideliTheme.surface,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(28),
            side: const BorderSide(color: FideliTheme.line),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: widget.onTap,
            borderRadius: BorderRadius.circular(28),
            hoverColor: Colors.transparent,
            focusColor: Colors.transparent,
            highlightColor: Colors.transparent,
            splashColor: Colors.white.withValues(alpha: .16),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 21, 16, 17),
              child: Column(
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              program.name,
                              style: const TextStyle(
                                fontFamily: 'Poppins',
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                              ),
                            ),

                            const SizedBox(height: 5),

                            Text(
                              widget.details,
                              style: const TextStyle(
                                fontFamily: 'Poppins',
                                fontSize: 12.5,
                                height: 1.45,
                                color: Color(0xFF756E6C),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 8),

                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      if (widget.onQrTap != null) ...[
                        TextButton.icon(
                          onPressed: widget.onQrTap,
                          icon: const Icon(Icons.qr_code_2_rounded, size: 21),
                          label: const Text('QR'),
                          style: TextButton.styleFrom(
                            backgroundColor: Colors.white.withValues(
                              alpha: .62,
                            ),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 15,
                              vertical: 12,
                            ),
                            shape: const StadiumBorder(),
                          ),
                        ),
                        const SizedBox(width: 6),
                      ],
                      IgnorePointer(
                        ignoring: _saving,
                        child: Switch.adaptive(
                          value: program.active && !program.isExpired,
                          activeTrackColor: FideliTheme.ink,
                          onChanged: widget.onChanged == null
                              ? null
                              : (value) async {
                                  setState(() => _saving = true);
                                  await widget.onChanged!(value);
                                  if (mounted) setState(() => _saving = false);
                                },
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ===========================================================
// BOTÓN CIRCULAR SUPERIOR
// ===========================================================

class _TopCircleButton extends StatelessWidget {
  const _TopCircleButton({
    required this.icon,
    required this.onTap,
    this.filled = false,
  });

  final IconData icon;
  final VoidCallback onTap;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: filled ? FideliTheme.ink : FideliTheme.surfaceSoft,

      shape: const CircleBorder(),

      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),

        child: SizedBox(
          width: 44,
          height: 44,

          child: Icon(
            icon,
            size: 24,

            color: filled ? Colors.white : const Color(0xFF4C4545),
          ),
        ),
      ),
    );
  }
}

// ===========================================================
// TÍTULO DE SECCIÓN
// ===========================================================

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,

      child: Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 9),

        child: Text(
          text,

          style: const TextStyle(
            fontFamily: 'Poppins',

            fontSize: 11,

            fontWeight: FontWeight.w700,

            color: Color(0xFF8A8280),

            letterSpacing: 1.15,
          ),
        ),
      ),
    );
  }
}

// ===========================================================
// BLOQUE APPLE
// ===========================================================

class _AppleSection extends StatelessWidget {
  const _AppleSection({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,

      decoration: BoxDecoration(
        color: FideliTheme.surfaceSoft,

        borderRadius: BorderRadius.circular(24),

        border: Border.all(color: FideliTheme.line),
      ),

      clipBehavior: Clip.antiAlias,

      child: Column(children: children),
    );
  }
}

// ===========================================================
// DIVISOR
// ===========================================================

class _AppleDivider extends StatelessWidget {
  const _AppleDivider();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 18),

      child: Divider(height: 1, thickness: 0.8, color: FideliTheme.line),
    );
  }
}

// ===========================================================
// FILA TEXTFIELD
// ===========================================================

class _AppleTextFieldRow extends StatelessWidget {
  const _AppleTextFieldRow({
    required this.label,
    required this.controller,
    required this.hint,
    this.keyboardType,
  });

  final String label;

  final TextEditingController controller;

  final String hint;

  final TextInputType? keyboardType;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 15, 18, 16),

      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontFamily: 'Poppins',
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: FideliTheme.inkSoft,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: controller,
            keyboardType: keyboardType,
            style: const TextStyle(fontFamily: 'Poppins', fontSize: 14),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: const TextStyle(color: Color(0xFFAAA7A4)),
              filled: true,
              fillColor: Colors.white,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 15,
                vertical: 14,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(color: FideliTheme.line),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(color: FideliTheme.line),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(
                  color: FideliTheme.ink,
                  width: 1.2,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ===========================================================
// DROPDOWN
// ===========================================================

class _AppleDropdownRow extends StatelessWidget {
  const _AppleDropdownRow({
    required this.label,
    required this.value,
    required this.values,
    required this.onChanged,
  });

  final String label;
  final String value;

  final List<String> values;

  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 15, 18, 16),

      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontFamily: 'Poppins',
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: FideliTheme.inkSoft,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 15),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: FideliTheme.line),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: value,
                isExpanded: true,
                borderRadius: BorderRadius.circular(18),
                icon: const Icon(
                  Icons.keyboard_arrow_down_rounded,
                  color: FideliTheme.muted,
                ),
                style: const TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 14,
                  color: FideliTheme.inkSoft,
                ),
                items: values
                    .map(
                      (item) =>
                          DropdownMenuItem(value: item, child: Text(item)),
                    )
                    .toList(),
                onChanged: onChanged,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ===========================================================
// MENSAJES
// ===========================================================

class _AppleMessageField extends StatelessWidget {
  const _AppleMessageField({
    required this.title,
    required this.subtitle,
    required this.controller,
  });

  final String title;

  final String subtitle;

  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 17),

      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,

        children: [
          Text(
            title,

            style: const TextStyle(
              fontFamily: 'Poppins',

              fontSize: 14,

              fontWeight: FontWeight.w600,

              color: Color(0xFF312B2D),
            ),
          ),

          const SizedBox(height: 4),

          Text(
            subtitle,

            style: const TextStyle(
              fontFamily: 'Poppins',

              fontSize: 11.5,
              height: 1.35,

              color: Color(0xFF99918F),
            ),
          ),

          const SizedBox(height: 10),

          TextField(
            controller: controller,

            minLines: 1,

            maxLines: 3,

            maxLength: 160,

            style: const TextStyle(fontFamily: 'Poppins', fontSize: 14),

            decoration: InputDecoration(
              counterText: '',

              filled: true,

              fillColor: Colors.white,

              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 12,
              ),

              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(color: FideliTheme.line),
              ),

              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(color: FideliTheme.line),
              ),

              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),

                borderSide: const BorderSide(
                  color: FideliTheme.ink,
                  width: 1.3,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ===========================================================
// FECHA BONITA
// ===========================================================

String _defaultProgramName(String cardChoice) => switch (cardChoice) {
  'Puntos' => 'Programa de puntos',
  'Membresía' => 'Membresía',
  'Tarjeta de regalo' => 'Tarjeta de regalo',
  _ => 'Tarjeta de sellos',
};

String _programEditSignature(LoyaltyProgram program, Iterable<Reward> rewards) {
  final milestones =
      program.stampMilestones
          .map(
            (item) => {
              'stamp': item.stamp,
              'reward': item.reward.trim(),
              'message': item.message.trim(),
            },
          )
          .toList()
        ..sort((a, b) => (a['stamp']! as int).compareTo(b['stamp']! as int));
  final rewardRows =
      rewards
          .map(
            (item) => {
              'name': item.name.trim(),
              'pointsCost': item.pointsCost,
              'stampsCost': item.stampsCost,
              'active': item.active,
            },
          )
          .toList()
        ..sort((a, b) {
          final costComparison =
              ((a['pointsCost']! as int) + (a['stampsCost']! as int)).compareTo(
                (b['pointsCost']! as int) + (b['stampsCost']! as int),
              );
          return costComparison != 0
              ? costComparison
              : (a['name']! as String).compareTo(b['name']! as String);
        });
  final expirationMinute = program.expiresAt == null
      ? null
      : program.expiresAt!.toUtc().millisecondsSinceEpoch ~/
            Duration.millisecondsPerMinute;

  return jsonEncode({
    'name': program.name.trim(),
    'type': program.type.name,
    'earningRate': program.earningRate,
    'goal': program.goal,
    'cardKind': program.cardKind,
    'welcomeMessage': program.welcomeMessage.trim(),
    'stampNotificationMessage': program.stampNotificationMessage.trim(),
    'completionMessage': program.completionMessage.trim(),
    'expiresAtMinute': expirationMinute,
    'tiers': program.tiers
        .map((item) => {'name': item.name.trim(), 'threshold': item.threshold})
        .toList(),
    'milestones': milestones,
    'rewards': rewardRows,
  });
}

String _prettyDate(DateTime date) {
  const months = [
    'Ene',
    'Feb',
    'Mar',
    'Abr',
    'May',
    'Jun',
    'Jul',
    'Ago',
    'Sep',
    'Oct',
    'Nov',
    'Dic',
  ];

  return '${date.day} ${months[date.month - 1]}';
}

// ===========================================================
// BORRADOR NIVEL
// ===========================================================

class _StampMilestoneDraft {
  _StampMilestoneDraft({
    required this.id,
    required String stamp,
    required String reward,
    required String message,
  }) : stamp = TextEditingController(text: stamp),
       reward = TextEditingController(text: reward),
       message = TextEditingController(text: message);

  final String id;
  final TextEditingController stamp;
  final TextEditingController reward;
  final TextEditingController message;

  void dispose() {
    stamp.dispose();
    reward.dispose();
    message.dispose();
  }
}

class _StampMilestoneEditor extends StatelessWidget {
  const _StampMilestoneEditor({required this.draft, required this.onRemove});

  final _StampMilestoneDraft draft;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    const fill = Colors.white;
    InputDecoration decoration(String hint) => InputDecoration(
      hintText: hint,
      filled: true,
      fillColor: fill,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(15),
        borderSide: const BorderSide(color: FideliTheme.line),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(15),
        borderSide: const BorderSide(color: FideliTheme.line),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(15),
        borderSide: const BorderSide(color: FideliTheme.ink, width: 1.2),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 14, 10, 14),
      child: Column(
        children: [
          Row(
            children: [
              SizedBox(
                width: 82,
                child: TextField(
                  controller: draft.stamp,
                  keyboardType: TextInputType.number,
                  decoration: decoration('Sello'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: draft.reward,
                  decoration: decoration('Premio'),
                ),
              ),
              IconButton(
                onPressed: onRemove,
                icon: const Icon(Icons.remove_circle_outline_rounded),
              ),
            ],
          ),
          const SizedBox(height: 9),
          TextField(
            controller: draft.message,
            minLines: 1,
            maxLines: 3,
            decoration: decoration('Notificación personalizada'),
          ),
        ],
      ),
    );
  }
}

class _TierDraft {
  _TierDraft(String name, String threshold)
    : name = TextEditingController(text: name),
      threshold = TextEditingController(text: threshold);

  final TextEditingController name;

  final TextEditingController threshold;

  void dispose() {
    name.dispose();

    threshold.dispose();
  }
}

// ============================================================================
// SILK-INSPIRED KEYBOARD SHEET · IMPLEMENTACIÓN NATIVA FLUTTER
// La ruta se anima verticalmente; el fondo aparece gradualmente y la tarjeta
// responde a las variaciones de altura del teclado sin tapar el contenido.
// ============================================================================
typedef _SilkSheetBuilder =
    Widget Function(BuildContext context, ScrollController scrollController);

Future<T?> _showSilkKeyboardSheet<T>({
  required BuildContext context,
  required _SilkSheetBuilder builder,
}) {
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: true,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: Colors.transparent,
    transitionDuration: const Duration(milliseconds: 480),
    pageBuilder: (dialogContext, animation, secondaryAnimation) {
      return _SilkKeyboardSheet(builder: builder);
    },
    transitionBuilder: (dialogContext, animation, secondaryAnimation, child) {
      final eased = CurvedAnimation(
        parent: animation,
        curve: const Cubic(0.20, 0.80, 0.20, 1.0),
        reverseCurve: Curves.easeInCubic,
      );
      return Stack(
        children: [
          IgnorePointer(
            child: FadeTransition(
              opacity: Tween<double>(begin: 0, end: 1).animate(eased),
              child: const ColoredBox(color: Color(0x660B0B12)),
            ),
          ),
          SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 1.05),
              end: Offset.zero,
            ).animate(eased),
            child: FadeTransition(
              opacity: Tween<double>(begin: 0.8, end: 1).animate(eased),
              child: child,
            ),
          ),
        ],
      );
    },
  );
}

class _SilkKeyboardSheet extends StatefulWidget {
  const _SilkKeyboardSheet({required this.builder});

  final _SilkSheetBuilder builder;

  @override
  State<_SilkKeyboardSheet> createState() => _SilkKeyboardSheetState();
}

class _SilkKeyboardSheetState extends State<_SilkKeyboardSheet> {
  final ScrollController _scrollController = ScrollController();
  double _dragOffset = 0;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _handleDragEnd(DragEndDetails details) {
    final velocity = details.primaryVelocity ?? 0;
    if (_dragOffset > 105 || velocity > 850) {
      Navigator.of(context).pop();
    } else {
      setState(() => _dragOffset = 0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final size = media.size;
    final keyboardHeight = media.viewInsets.bottom;
    final desktop = size.width >= 760;
    final horizontalMargin = desktop ? 26.0 : 0.0;
    final width = desktop
        ? (size.width - 52).clamp(0.0, 760.0).toDouble()
        : size.width;
    final availableHeight = size.height - keyboardHeight;
    final maxHeight = desktop
        ? (availableHeight - 48).clamp(0.0, 920.0).toDouble()
        : (availableHeight - media.padding.top - 10)
              .clamp(0.0, availableHeight)
              .toDouble();

    return Material(
      color: Colors.transparent,
      child: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => Navigator.of(context).maybePop(),
            ),
          ),
          AnimatedPadding(
            duration: const Duration(milliseconds: 250),
            curve: const Cubic(0.22, 0.85, 0.22, 1.0),
            padding: EdgeInsets.fromLTRB(
              horizontalMargin,
              0,
              horizontalMargin,
              keyboardHeight,
            ),
            child: Align(
              alignment: Alignment.bottomCenter,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeOutCubic,
                transform: Matrix4.translationValues(0, _dragOffset, 0),
                width: width,
                height: maxHeight,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(
                    top: const Radius.circular(32),
                    bottom: Radius.circular(desktop ? 32 : 0),
                  ),
                  border: Border.all(color: const Color(0x14000000)),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x25000000),
                      blurRadius: 55,
                      offset: Offset(0, 10),
                    ),
                  ],
                ),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  children: [
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onVerticalDragUpdate: (details) => setState(() {
                        _dragOffset = (_dragOffset + details.delta.dy).clamp(
                          0.0,
                          220.0,
                        );
                      }),
                      onVerticalDragEnd: _handleDragEnd,
                      child: SizedBox(
                        height: 24,
                        width: double.infinity,
                        child: Center(
                          child: Container(
                            width: 42,
                            height: 5,
                            decoration: BoxDecoration(
                              color: const Color(0xFFDAD9DD),
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                        ),
                      ),
                    ),
                    Expanded(child: widget.builder(context, _scrollController)),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
