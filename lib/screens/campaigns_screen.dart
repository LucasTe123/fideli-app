import 'package:flutter/material.dart';
import '../models/app_data.dart';
import '../services/cloud_store.dart';
import '../services/wallet_service.dart';
import '../state/app_scope.dart';
import '../theme/fideli_theme.dart';
import '../widgets/common.dart';

class CampaignsScreen extends StatefulWidget {
  const CampaignsScreen({
    super.key,
    this.openComposerOnStart = false,
    this.walletService,
    this.initialAudience,
    this.initialTargetCustomerId,
    this.initialTargetCustomerName,
    this.initialName,
    this.initialNotificationTitle,
    this.initialMessage,
  });

  final bool openComposerOnStart;
  final WalletService? walletService;
  final String? initialAudience;
  final String? initialTargetCustomerId;
  final String? initialTargetCustomerName;
  final String? initialName;
  final String? initialNotificationTitle;
  final String? initialMessage;

  @override
  State<CampaignsScreen> createState() => _CampaignsScreenState();
}

class _CampaignsScreenState extends State<CampaignsScreen> {
  final Set<String> _sending = {};
  final Set<String> _deleting = {};
  bool _editing = false;
  Animation<double>? _routeAnimation;
  VoidCallback? _routeListener;
  bool _openedInitialComposer = false;

  @override
  void initState() {
    super.initState();
    if (widget.openComposerOnStart) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _routeAnimation = ModalRoute.of(context)?.animation;
        if (_routeAnimation == null ||
            _routeAnimation!.status == AnimationStatus.completed) {
          _openInitialComposer();
          return;
        }
        _routeListener = () {
          if (_routeAnimation?.status != AnimationStatus.completed) return;
          _routeAnimation?.removeListener(_routeListener!);
          _routeListener = null;
          WidgetsBinding.instance.addPostFrameCallback(
            (_) => _openInitialComposer(),
          );
        };
        _routeAnimation!.addListener(_routeListener!);
      });
    }
  }

  void _openInitialComposer() {
    if (!mounted || _openedInitialComposer) return;
    _openedInitialComposer = true;
    _save(context);
  }

  @override
  void dispose() {
    if (_routeListener != null) {
      _routeAnimation?.removeListener(_routeListener!);
    }
    super.dispose();
  }

  // =========================================================
  // INTERFAZ PRINCIPAL
  // =========================================================
  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);

    // MISMO CONTENIDO ORIGINAL: solamente se adapta el diseño de la lista.
    return Scaffold(
      backgroundColor: FideliTheme.canvas,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _editing ? null : () => _save(context),
        label: const Text('Nueva campaña'),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final viewportWidth = constraints.maxWidth;
            final horizontalPadding = viewportWidth < 700 ? 16.0 : 32.0;
            final contentWidth = (viewportWidth - horizontalPadding * 2)
                .clamp(0.0, 1040.0)
                .toDouble();
            const spacing = 18.0;
            final columns = contentWidth >= 1060
                ? 3
                : contentWidth >= 720
                ? 2
                : 1;
            final cardWidth =
                (contentWidth - spacing * (columns - 1)) / columns;

            return SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                horizontalPadding,
                viewportWidth < 700 ? 18 : 32,
                horizontalPadding,
                24,
              ),
              child: Align(
                alignment: Alignment.topCenter,
                child: SizedBox(
                  width: contentWidth,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Campañas',
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 30,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -1.1,
                        ),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Mensajes claros para mantener cerca a tus clientes',
                        style: TextStyle(color: FideliTheme.muted),
                      ),
                      const SizedBox(height: 28),
                      if (state.data.campaigns.isNotEmpty)
                        Wrap(
                          spacing: spacing,
                          runSpacing: spacing,
                          children: [
                            for (final item in state.data.campaigns)
                              SizedBox(
                                width: cardWidth,
                                child: _buildCampaignCard(context, item),
                              ),
                          ],
                        )
                      else
                        const ListTile(title: Text('Aún no hay campañas.')),
                      const SizedBox(height: 80),
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

  Widget _buildCampaignCard(BuildContext context, Campaign item) {
    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      surfaceTintColor: Colors.white,
      color: FideliTheme.surfaceSoft,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(26),
        side: const BorderSide(color: FideliTheme.line),
      ),
      child: InkWell(
        onTap: (_sending.contains(item.id) || _deleting.contains(item.id))
            ? null
            : () => _save(context, campaign: item),
        borderRadius: BorderRadius.circular(26),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 12, 14),
          child: Column(
            children: [
              ListTile(
                contentPadding: const EdgeInsets.fromLTRB(8, 2, 0, 2),
                // =========================================
                // ICONO
                // =========================================
                // =========================================
                // NOMBRE
                // =========================================
                title: Text(
                  item.name,
                  style: const TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                // =========================================
                // DETALLE
                // =========================================
                subtitle: Text(
                  '${item.audience == 'Una persona' ? item.targetCustomerName ?? 'Una persona' : item.audience} · ${item.message}\n'
                  '${item.sentAt == null ? 'Borrador' : 'Enviada ${item.sentAt}'}',
                  style: const TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 12.5,
                    height: 1.42,
                    color: Color(0xFF756E6C),
                  ),
                ),
                isThreeLine: true,
                // =========================================
                // MENÚ
                // =========================================
                trailing: PopupMenuButton<String>(
                  icon: const Icon(Icons.more_horiz_rounded),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                  enabled:
                      !_sending.contains(item.id) &&
                      !_deleting.contains(item.id),
                  onSelected: (value) {
                    if (value == 'reuse') {
                      _save(context, campaign: item);
                    }
                    if (value == 'delete') {
                      _delete(context, item);
                    }
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(
                      value: 'reuse',
                      child: ListTile(
                        leading: Icon(Icons.edit_outlined),
                        title: Text('Editar o reutilizar'),
                      ),
                    ),
                    PopupMenuItem(
                      value: 'delete',
                      child: ListTile(
                        leading: Icon(Icons.delete_outline),
                        title: Text('Borrar definitivamente'),
                      ),
                    ),
                  ],
                ),
              ),
              // ===========================================
              // ENVIAR
              // ===========================================
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    shape: const StadiumBorder(),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 12,
                    ),
                  ),
                  onPressed: _sending.contains(item.id)
                      ? null
                      : () => _send(context, item),
                  icon: _sending.contains(item.id)
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(item.sentAt == null ? Icons.send : Icons.replay),
                  label: Text(
                    _sending.contains(item.id)
                        ? 'Enviando…'
                        : item.sentAt == null
                        ? 'Enviar'
                        : 'Enviar de nuevo',
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // =========================================================
  // ENVIAR CAMPAÑA
  // =========================================================
  Future<void> _send(
    BuildContext context,
    Campaign campaign, {
    Campaign? stateCampaign,
  }) async {
    // Capture exactly what is on screen before any asynchronous save, realtime
    // refresh or route animation can replace/mutate the campaign in AppState.
    // This guarantees that the first send uses the title the merchant just
    // typed, rather than the value from the previous database snapshot.
    final payload = Campaign.fromJson(campaign.toJson());
    final persistedCampaign = stateCampaign ?? campaign;
    if (payload.message.trim().isEmpty) {
      showMessage(
        context,
        'Escribe el texto de la notificación antes de enviar',
      );
      await _save(context, campaign: persistedCampaign);
      return;
    }
    if (!_sending.add(payload.id)) {
      return;
    }
    setState(() {});
    final state = AppScope.of(context);
    final requestId = '${payload.id}-${DateTime.now().microsecondsSinceEpoch}';
    try {
      final result = await (widget.walletService ?? WalletService())
          .sendCampaign(
            state.data.business,
            requestId: requestId,
            campaignId: payload.id,
            campaignName: payload.name,
            notificationTitle: payload.notificationTitle,
            message: payload.message,
            audience: payload.audience,
            targetCustomerId: payload.targetCustomerId,
            birthdayDate: payload.audience == 'Cumpleañeros de hoy'
                ? _localDateString(DateTime.now())
                : null,
            linkUrl: payload.linkUrl,
          );
      if (!context.mounted) {
        return;
      }
      if (result.ok) {
        persistedCampaign.sentAt = DateTime.now();
        await state.commitLocalOnly();
        final saveResult = await (widget.walletService ?? WalletService())
            .saveCampaign(state.data.business, persistedCampaign);
        if (!saveResult.ok && context.mounted) {
          showMessage(context, saveResult.message);
          return;
        }
      }
      if (context.mounted) {
        showMessage(context, result.message);
      }
    } finally {
      _sending.remove(payload.id);
      if (mounted) {
        setState(() {});
      }
    }
  }

  // =========================================================
  // CREAR / EDITAR CAMPAÑA
  // =========================================================
  Future<void> _save(BuildContext context, {Campaign? campaign}) async {
    if (_editing) {
      return;
    }
    setState(() => _editing = true);
    // =========================================================
    // CONTROLADORES
    // =========================================================
    final name = TextEditingController(
      text: campaign?.name ?? widget.initialName ?? '',
    );
    final notificationTitle = TextEditingController(
      text:
          campaign?.notificationTitle ?? widget.initialNotificationTitle ?? '',
    );
    final message = TextEditingController(
      text: campaign?.message ?? widget.initialMessage ?? '',
    );
    final link = TextEditingController(text: campaign?.linkUrl ?? '');
    final customerSearch = TextEditingController(
      text:
          campaign?.targetCustomerName ??
          widget.initialTargetCustomerName ??
          '',
    );
    // =========================================================
    // PÚBLICO
    // =========================================================
    var audience = campaign?.audience ?? widget.initialAudience ?? 'Todos';
    String? selectedCustomerId =
        campaign?.targetCustomerId ?? widget.initialTargetCustomerId;
    String? selectedCustomerName =
        campaign?.targetCustomerName ?? widget.initialTargetCustomerName;
    String? linkError;
    String? nameError;
    String? messageError;
    String? customerError;
    const audiences = [
      'Todos',
      'Nuevos',
      'Preocupantes',
      'Riesgo',
      'Cumpleañeros de hoy',
      'Una persona',
    ];
    audience = switch (audience) {
      'En riesgo' => 'Preocupantes',
      'Inactivos' => 'Riesgo',
      'Frecuentes' || 'Regulares' || 'Ocasionales' || 'Recuperados' => 'Todos',
      _ => audience,
    };
    if (!audiences.contains(audience)) {
      audience = 'Todos';
    }
    // =========================================================
    // VALIDAR Y CERRAR SHEET
    // =========================================================
    void finishSheet(
      String action,
      BuildContext sheetContext,
      StateSetter setSheetState,
    ) {
      if (name.text.trim().isEmpty) {
        setSheetState(() {
          nameError = 'Escribe un nombre para la campaña';
        });
        return;
      }
      if (action == 'send' && message.text.trim().isEmpty) {
        setSheetState(() {
          messageError = 'Escribe el texto que recibirá el cliente';
        });
        return;
      }
      if (audience == 'Una persona' && selectedCustomerId == null) {
        setSheetState(() {
          customerError = 'Selecciona un cliente';
        });
        return;
      }
      final normalized = _normalizeCampaignUrl(link.text);
      if (link.text.trim().isNotEmpty && normalized == null) {
        setSheetState(() {
          linkError = 'Link no válido';
        });
        return;
      }
      link.text = normalized ?? '';
      Navigator.pop(sheetContext, action);
    }

    try {
      // =======================================================
      // BOTTOM SHEET APPLE
      // =======================================================
      final action = await _showCampaignKeyboardSheet<String>(
        context: context,
        builder: (sheetContext, scrollController) {
          return StatefulBuilder(
            builder: (context, setSheetState) {
              const Color background = Colors.white;
              const Color primary = FideliTheme.ink;
              const Color primaryText = Color(0xFF2D2829);
              final customers = AppScope.of(context).data.customers;
              final customerQuery = customerSearch.text.trim().toLowerCase();
              final customerMatches = customers
                  .where(
                    (item) =>
                        customerQuery.isEmpty ||
                        item.name.toLowerCase().contains(customerQuery) ||
                        item.phone.toLowerCase().contains(customerQuery) ||
                        item.email.toLowerCase().contains(customerQuery),
                  )
                  .take(6)
                  .toList();
              return Container(
                color: background,
                child: Column(
                  children: [
                    // =========================================
                    // CABECERA
                    // X / TITULO / CHECK
                    // =========================================
                    Padding(
                      padding: const EdgeInsets.fromLTRB(18, 10, 18, 8),
                      child: Row(
                        children: [
                          // ===================================
                          // CERRAR
                          // ===================================
                          _CampaignTopButton(
                            icon: Icons.close_rounded,
                            onTap: () {
                              Navigator.pop(sheetContext);
                            },
                          ),
                          // ===================================
                          // TÍTULO
                          // ===================================
                          Expanded(
                            child: Text(
                              campaign == null
                                  ? 'Nueva campaña'
                                  : 'Reutilizar campaña',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontFamily: 'Poppins',
                                fontSize: 20,
                                fontWeight: FontWeight.w700,
                                color: primaryText,
                              ),
                            ),
                          ),
                          // ===================================
                          // GUARDAR BORRADOR
                          // ===================================
                          _CampaignTopButton(
                            icon: Icons.check_rounded,
                            filled: true,
                            tooltip: 'Guardar borrador',
                            onTap: () {
                              finishSheet('draft', sheetContext, setSheetState);
                            },
                          ),
                        ],
                      ),
                    ),
                    // =========================================
                    // CONTENIDO
                    // =========================================
                    Expanded(
                      child: SingleChildScrollView(
                        controller: scrollController,
                        padding: const EdgeInsets.fromLTRB(18, 10, 18, 34),
                        child: Column(
                          children: [
                            // =================================
                            // DATOS PRINCIPALES
                            // =================================
                            const _CampaignSectionTitle(text: 'CAMPAÑA'),
                            _CampaignAppleSection(
                              children: [
                                // =============================
                                // NOMBRE
                                // =============================
                                _CampaignTextFieldRow(
                                  label: 'Nombre',
                                  fieldKey: const ValueKey('campaign-name'),
                                  controller: name,
                                  hint: 'Ej. Promo septiembre',
                                  errorText: nameError,
                                  onChanged: (_) {
                                    if (nameError != null) {
                                      setSheetState(() {
                                        nameError = null;
                                      });
                                    }
                                  },
                                ),
                                const _CampaignAppleDivider(),
                                // =============================
                                // PÚBLICO
                                // =============================
                                _CampaignDropdownRow(
                                  label: 'Público',
                                  value: audience,
                                  values: audiences,
                                  onChanged: (value) {
                                    if (value == null) {
                                      return;
                                    }
                                    setSheetState(() {
                                      audience = value;
                                      customerError = null;
                                    });
                                  },
                                ),
                              ],
                            ),
                            if (audience == 'Una persona') ...[
                              const SizedBox(height: 12),
                              _CampaignAppleSection(
                                children: [
                                  Padding(
                                    padding: const EdgeInsets.fromLTRB(
                                      16,
                                      8,
                                      16,
                                      4,
                                    ),
                                    child: TextField(
                                      controller: customerSearch,
                                      autofocus: selectedCustomerId == null,
                                      onChanged: (_) => setSheetState(() {
                                        selectedCustomerId = null;
                                        selectedCustomerName = null;
                                        customerError = null;
                                      }),
                                      decoration: InputDecoration(
                                        hintText: 'Buscar cliente',
                                        prefixIcon: const Icon(
                                          Icons.search_rounded,
                                        ),
                                        border: InputBorder.none,
                                        errorText: customerError,
                                      ),
                                    ),
                                  ),
                                  if (customerMatches.isEmpty)
                                    const Padding(
                                      padding: EdgeInsets.all(18),
                                      child: Text('No se encontraron clientes'),
                                    )
                                  else
                                    for (final customer in customerMatches)
                                      ListTile(
                                        onTap: () => setSheetState(() {
                                          selectedCustomerId = customer.id;
                                          selectedCustomerName = customer.name;
                                          customerSearch.text = customer.name;
                                          customerSearch.selection =
                                              TextSelection.collapsed(
                                                offset: customer.name.length,
                                              );
                                          customerError = null;
                                        }),
                                        leading: CircleAvatar(
                                          backgroundColor: const Color(
                                            0x189E483F,
                                          ),
                                          child: Text(
                                            customer.name.isEmpty
                                                ? '?'
                                                : customer.name[0]
                                                      .toUpperCase(),
                                          ),
                                        ),
                                        title: Text(customer.name),
                                        subtitle:
                                            customer.phone.isEmpty &&
                                                customer.email.isEmpty
                                            ? null
                                            : Text(
                                                customer.phone.isNotEmpty
                                                    ? customer.phone
                                                    : customer.email,
                                              ),
                                        trailing:
                                            selectedCustomerId == customer.id
                                            ? const Icon(
                                                Icons.check_circle_rounded,
                                                color: primary,
                                              )
                                            : null,
                                      ),
                                ],
                              ),
                            ],
                            const SizedBox(height: 22),
                            // =================================
                            // MENSAJE
                            // =================================
                            const _CampaignSectionTitle(text: 'MENSAJE'),
                            _CampaignAppleSection(
                              children: [
                                _CampaignTextFieldRow(
                                  label: 'Título de la notificación',
                                  fieldKey: const ValueKey(
                                    'campaign-notification-title',
                                  ),
                                  controller: notificationTitle,
                                  hint:
                                      'Opcional · si está vacío se usa el nombre del negocio',
                                ),
                                const _CampaignAppleDivider(),
                                _CampaignLargeTextField(
                                  title: 'Texto de la notificación',
                                  subtitle:
                                      'Escribe el mensaje que recibirá el cliente en Wallet.',
                                  controller: message,
                                  hint: 'Ej. ☕ Hoy tenemos 2x1 en cappuccino',
                                  errorText: messageError,
                                  maxLines: 4,
                                  onChanged: (_) {
                                    if (messageError != null) {
                                      setSheetState(() {
                                        messageError = null;
                                      });
                                    }
                                  },
                                ),
                              ],
                            ),
                            const SizedBox(height: 22),
                            // =================================
                            // ENLACE
                            // =================================
                            const _CampaignSectionTitle(text: 'ENLACE'),
                            _CampaignAppleSection(
                              children: [
                                _CampaignLargeTextField(
                                  title: 'Destino opcional',
                                  subtitle:
                                      'Puede ser Instagram, una página web, reservas, WhatsApp u otro enlace.',
                                  controller: link,
                                  hint: 'https://instagram.com/...',
                                  keyboardType: TextInputType.url,
                                  errorText: linkError,
                                  maxLines: 2,
                                  onChanged: (_) {
                                    if (linkError != null) {
                                      setSheetState(() {
                                        linkError = null;
                                      });
                                    }
                                  },
                                ),
                              ],
                            ),
                            const SizedBox(height: 22),
                            // =================================
                            // GUARDAR Y ENVIAR
                            // =================================
                            SizedBox(
                              width: double.infinity,
                              height: 58,
                              child: FilledButton.icon(
                                onPressed: () {
                                  finishSheet(
                                    'send',
                                    sheetContext,
                                    setSheetState,
                                  );
                                },
                                style: FilledButton.styleFrom(
                                  backgroundColor: primary,
                                  foregroundColor: Colors.white,
                                  elevation: 0,
                                  shape: const StadiumBorder(),
                                ),
                                icon: const Icon(Icons.send_rounded, size: 21),
                                label: const Text(
                                  'Guardar y enviar',
                                  style: TextStyle(
                                    fontFamily: 'Poppins',
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 10),
                            // =================================
                            // GUARDAR SOLAMENTE
                            // =================================
                            TextButton.icon(
                              onPressed: () {
                                finishSheet(
                                  'draft',
                                  sheetContext,
                                  setSheetState,
                                );
                              },
                              icon: const Icon(Icons.drafts_outlined),
                              label: const Text(
                                'Guardar como borrador',
                                style: TextStyle(fontFamily: 'Poppins'),
                              ),
                            ),
                            const SizedBox(height: 20),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      );
      // showGeneralDialog resolves when pop is requested, before its 480 ms
      // reverse transition has completely detached the sheet from AppScope.
      // Do not mutate inherited app state while that overlay is deactivating.
      await Future<void>.delayed(const Duration(milliseconds: 520));
      // =======================================================
      // GUARDAR DATOS
      // =======================================================
      if (action != null && name.text.trim().isNotEmpty && context.mounted) {
        final state = AppScope.of(context);
        late final Campaign savedCampaign;
        final nextName = name.text.trim();
        final nextNotificationTitle = notificationTitle.text.trim();
        final nextMessage = message.text.trim();
        final nextTargetCustomerId = audience == 'Una persona'
            ? selectedCustomerId
            : null;
        final nextTargetCustomerName = audience == 'Una persona'
            ? selectedCustomerName
            : null;
        final nextLinkUrl = link.text.trim().isEmpty ? null : link.text.trim();
        final changed =
            campaign == null ||
            campaign.name != nextName ||
            campaign.notificationTitle != nextNotificationTitle ||
            campaign.message != nextMessage ||
            campaign.audience != audience ||
            campaign.targetCustomerId != nextTargetCustomerId ||
            campaign.targetCustomerName != nextTargetCustomerName ||
            campaign.linkUrl != nextLinkUrl;

        if (!changed) {
          if (action == 'send') {
            await _send(context, campaign);
          } else if (context.mounted) {
            showMessage(context, 'No hay cambios para guardar');
          }
          return;
        }
        // =====================================================
        // NUEVA
        // =====================================================
        if (campaign == null) {
          savedCampaign = Campaign(
            id: newId('campaign'),
            name: nextName,
            notificationTitle: nextNotificationTitle,
            message: nextMessage,
            audience: audience,
            targetCustomerId: nextTargetCustomerId,
            targetCustomerName: nextTargetCustomerName,
            linkUrl: nextLinkUrl,
          );
          state.data.campaigns.add(savedCampaign);
        }
        // =====================================================
        // REUTILIZAR
        // =====================================================
        else {
          campaign
            ..name = nextName
            ..notificationTitle = nextNotificationTitle
            ..message = nextMessage
            ..audience = audience
            ..targetCustomerId = nextTargetCustomerId
            ..targetCustomerName = nextTargetCustomerName
            ..linkUrl = nextLinkUrl
            ..sentAt = null;
          savedCampaign = campaign;
        }
        await state.commitLocalOnly();
        // =====================================================
        // ENVIAR
        // =====================================================
        if (action == 'send' && context.mounted) {
          // /api/campaigns/send persists and sends the same immutable payload
          // atomically. Do not wait for a separate save/realtime round-trip
          // first, because that allowed the previous title to win the race.
          final sendSnapshot = Campaign.fromJson(savedCampaign.toJson());
          await _send(context, sendSnapshot, stateCampaign: savedCampaign);
        }
        // =====================================================
        // SOLO GUARDAR
        // =====================================================
        else if (context.mounted) {
          WalletResult? saveResult;
          if (widget.walletService != null ||
              CloudStore.instance?.accessToken != null) {
            saveResult = await (widget.walletService ?? WalletService())
                .saveCampaign(state.data.business, savedCampaign);
            if (!saveResult.ok && context.mounted) {
              showMessage(context, saveResult.message);
              return;
            }
          }
          if (!context.mounted) return;
          showMessage(
            context,
            campaign == null
                ? 'Campaña guardada'
                : 'Campaña lista para reutilizar',
          );
        }
      }
    } finally {
      // =======================================================
      // DISPOSE
      // =======================================================
      name.dispose();
      notificationTitle.dispose();
      message.dispose();
      link.dispose();
      customerSearch.dispose();
      if (mounted) {
        setState(() => _editing = false);
      }
    }
  }

  // =========================================================
  // ELIMINAR CAMPAÑA
  // =========================================================
  Future<void> _delete(BuildContext context, Campaign campaign) async {
    if (_sending.contains(campaign.id) || _deleting.contains(campaign.id)) {
      return;
    }
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('¿Borrar ${campaign.name}?'),
        content: const Text('Se eliminará definitivamente.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Borrar'),
          ),
        ],
      ),
    );
    if (accepted != true || !context.mounted) {
      return;
    }
    _deleting.add(campaign.id);
    setState(() {});
    try {
      final state = AppScope.of(context);
      final index = state.data.campaigns.indexWhere(
        (item) => item.id == campaign.id,
      );
      final result = await state.runRemoteMutation(() async {
        state.data.campaigns.removeWhere((item) => item.id == campaign.id);
        await state.commitLocalOnly();
        final deleteResult = await (widget.walletService ?? WalletService())
            .deleteCampaign(state.data.business, campaign.id);
        if (!deleteResult.ok && index >= 0) {
          state.data.campaigns.insert(
            index.clamp(0, state.data.campaigns.length).toInt(),
            campaign,
          );
          await state.commitLocalOnly();
        }
        return deleteResult;
      });
      if (!context.mounted) {
        return;
      }
      showMessage(context, result.message);
    } finally {
      _deleting.remove(campaign.id);
      if (mounted) {
        setState(() {});
      }
    }
  }
}

// ===========================================================
// BOTÓN CIRCULAR SUPERIOR
// ===========================================================
class _CampaignTopButton extends StatelessWidget {
  const _CampaignTopButton({
    required this.icon,
    required this.onTap,
    this.filled = false,
    this.tooltip,
  });
  final IconData icon;
  final VoidCallback onTap;
  final bool filled;
  final String? tooltip;
  @override
  Widget build(BuildContext context) {
    final button = Material(
      color: filled ? FideliTheme.ink : Colors.white,
      elevation: filled ? 1.2 : 2,
      shadowColor: const Color(0x23000000),
      shape: const CircleBorder(),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: SizedBox(
          width: 48,
          height: 48,
          child: Icon(
            icon,
            size: 28,
            color: filled ? Colors.white : const Color(0xFF4C4545),
          ),
        ),
      ),
    );
    if (tooltip == null) {
      return button;
    }
    return Tooltip(message: tooltip!, child: button);
  }
}

// ===========================================================
// TÍTULO SECCIÓN
// ===========================================================
class _CampaignSectionTitle extends StatelessWidget {
  const _CampaignSectionTitle({required this.text});
  final String text;
  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.only(left: 8, bottom: 8),
        child: Text(
          text,
          style: const TextStyle(
            fontFamily: 'Poppins',
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: Color(0xFF8A8280),
            letterSpacing: 0.5,
          ),
        ),
      ),
    );
  }
}

// ===========================================================
// SECCIÓN APPLE
// ===========================================================
class _CampaignAppleSection extends StatelessWidget {
  const _CampaignAppleSection({required this.children});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: const Color(0x14000000), width: 0.8),
        boxShadow: const [
          BoxShadow(
            color: Color(0x13000000),
            blurRadius: 24,
            offset: Offset(0, 7),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(children: children),
    );
  }
}

// ===========================================================
// DIVISOR
// ===========================================================
class _CampaignAppleDivider extends StatelessWidget {
  const _CampaignAppleDivider();
  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.only(left: 18),
      child: Divider(height: 1, thickness: 0.8, color: Color(0xFFE8E2DF)),
    );
  }
}

// ===========================================================
// CAMPO EN FILA
// ===========================================================
class _CampaignTextFieldRow extends StatelessWidget {
  const _CampaignTextFieldRow({
    required this.label,
    required this.controller,
    required this.hint,
    this.fieldKey,
    this.errorText,
    this.onChanged,
  });
  final String label;
  final TextEditingController controller;
  final String hint;
  final Key? fieldKey;
  final String? errorText;
  final ValueChanged<String>? onChanged;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 6, 18, 6),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: Color(0xFF312B2D),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                flex: 2,
                child: TextField(
                  key: fieldKey,
                  controller: controller,
                  textAlign: TextAlign.right,
                  onChanged: onChanged,
                  style: const TextStyle(fontFamily: 'Poppins', fontSize: 15),
                  decoration: InputDecoration(
                    hintText: hint,
                    hintStyle: const TextStyle(color: Color(0xFFAAA4A2)),
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                  ),
                ),
              ),
            ],
          ),
          if (errorText != null)
            Align(
              alignment: Alignment.centerRight,
              child: Text(
                errorText!,
                style: const TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 11,
                  color: Colors.red,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ===========================================================
// DROPDOWN EN FILA
// ===========================================================
class _CampaignDropdownRow extends StatelessWidget {
  const _CampaignDropdownRow({
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
      padding: const EdgeInsets.fromLTRB(18, 4, 12, 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                fontFamily: 'Poppins',
                fontSize: 15,
                fontWeight: FontWeight.w500,
                color: Color(0xFF312B2D),
              ),
            ),
          ),
          DropdownButton<String>(
            value: value,
            underline: const SizedBox(),
            borderRadius: BorderRadius.circular(18),
            icon: const Icon(
              Icons.chevron_right_rounded,
              color: Color(0xFF9A9492),
            ),
            style: const TextStyle(
              fontFamily: 'Poppins',
              fontSize: 15,
              color: Color(0xFF716A68),
            ),
            items: values
                .map(
                  (item) =>
                      DropdownMenuItem<String>(value: item, child: Text(item)),
                )
                .toList(),
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

// ===========================================================
// CAMPO GRANDE
// ===========================================================
class _CampaignLargeTextField extends StatelessWidget {
  const _CampaignLargeTextField({
    required this.title,
    required this.subtitle,
    required this.controller,
    required this.hint,
    this.maxLines = 3,
    this.keyboardType,
    this.errorText,
    this.onChanged,
  });
  final String title;
  final String subtitle;
  final TextEditingController controller;
  final String hint;
  final int maxLines;
  final TextInputType? keyboardType;
  final String? errorText;
  final ValueChanged<String>? onChanged;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontFamily: 'Poppins',
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: Color(0xFF312B2D),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: const TextStyle(
              fontFamily: 'Poppins',
              fontSize: 11.5,
              height: 1.4,
              color: Color(0xFF99918F),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: controller,
            keyboardType: keyboardType,
            autocorrect: keyboardType != TextInputType.url,
            textCapitalization: keyboardType == TextInputType.url
                ? TextCapitalization.none
                : TextCapitalization.sentences,
            minLines: 1,
            maxLines: maxLines,
            onChanged: onChanged,
            style: const TextStyle(fontFamily: 'Poppins', fontSize: 14),
            decoration: InputDecoration(
              hintText: hint,
              errorText: errorText,
              filled: true,
              fillColor: Colors.white,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 13,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(
                  color: Color(0xFFE9E5E3),
                  width: 1,
                ),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(
                  color: Color(0xFFE9E5E3),
                  width: 1,
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(
                  color: FideliTheme.ink,
                  width: 1.3,
                ),
              ),
              errorBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(color: Colors.red, width: 1),
              ),
              focusedErrorBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(color: Colors.red, width: 1.3),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ===========================================================
// NORMALIZAR URL
// ===========================================================
String? _normalizeCampaignUrl(String value) {
  final raw = value.trim();
  if (raw.isEmpty) {
    return null;
  }
  final candidate = raw.contains('://') ? raw : 'https://$raw';
  final uri = Uri.tryParse(candidate);
  if (uri == null ||
      (uri.scheme != 'https' && uri.scheme != 'http') ||
      uri.host.isEmpty) {
    return null;
  }
  return uri.toString();
}

String _localDateString(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

// ============================================================================
// SILK-INSPIRED KEYBOARD SHEET · IMPLEMENTACIÓN NATIVA FLUTTER
// La ruta se anima verticalmente; el fondo aparece gradualmente y la tarjeta
// responde a las variaciones de altura del teclado sin tapar el contenido.
// ============================================================================
typedef _CampaignSheetBuilder =
    Widget Function(BuildContext context, ScrollController scrollController);

Future<T?> _showCampaignKeyboardSheet<T>({
  required BuildContext context,
  required _CampaignSheetBuilder builder,
}) {
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: true,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: Colors.transparent,
    transitionDuration: const Duration(milliseconds: 480),
    pageBuilder: (dialogContext, animation, secondaryAnimation) {
      return _CampaignKeyboardSheet(builder: builder);
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

class _CampaignKeyboardSheet extends StatefulWidget {
  const _CampaignKeyboardSheet({required this.builder});

  final _CampaignSheetBuilder builder;

  @override
  State<_CampaignKeyboardSheet> createState() => _CampaignKeyboardSheetState();
}

class _CampaignKeyboardSheetState extends State<_CampaignKeyboardSheet> {
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
            duration: const Duration(milliseconds: 330),
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
