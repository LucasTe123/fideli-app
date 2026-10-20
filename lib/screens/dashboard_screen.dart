import 'package:flutter/material.dart';

import '../services/cloud_store.dart';
import '../state/app_scope.dart';
import '../theme/fideli_theme.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({
    super.key,
    required this.onProgramsPressed,
    required this.onCustomersPressed,
    required this.onCampaignsPressed,
    required this.onBusinessPressed,
    this.onStorefrontPressed,
    required this.onSharePressed,
    required this.onWalletPressed,
    required this.onSignOut,
    this.onScanPressed,
    this.onNewProgramPressed,
    this.onNewCampaignPressed,
    this.animateEntrance = true,
  });

  final ValueChanged<Rect> onProgramsPressed;
  final ValueChanged<Rect> onCustomersPressed;
  final ValueChanged<Rect> onCampaignsPressed;
  final ValueChanged<Rect> onBusinessPressed;
  final ValueChanged<Rect>? onStorefrontPressed;
  final ValueChanged<Rect> onSharePressed;
  final ValueChanged<Rect> onWalletPressed;
  final ValueChanged<Rect>? onScanPressed;
  final ValueChanged<Rect>? onNewProgramPressed;
  final ValueChanged<Rect>? onNewCampaignPressed;
  final Future<void> Function() onSignOut;
  final bool animateEntrance;

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _entrance;

  @override
  void initState() {
    super.initState();
    _entrance = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 850),
      value: widget.animateEntrance ? 0 : 1,
    );
    if (widget.animateEntrance) _entrance.forward();
  }

  @override
  void dispose() {
    _entrance.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final name = AppScope.of(context).data.business.name.trim();
    final businessName = name.isEmpty ? 'Tu negocio' : name;
    return ColoredBox(
      color: FideliTheme.canvas,
      child: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth >= 1050) {
              return _desktop(businessName);
            }
            return _compact();
          },
        ),
      ),
    );
  }

  Widget _desktop(String businessName) {
    final modules = _modules();
    final quickActions = _quickActions();
    return Padding(
      padding: const EdgeInsets.all(22),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: FideliTheme.surface.withValues(alpha: .62),
          borderRadius: BorderRadius.circular(32),
          border: Border.all(color: FideliTheme.line),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(31),
          child: Row(
            children: [
              SizedBox(
                width: 230,
                child: DecoratedBox(
                  decoration: const BoxDecoration(
                    boxShadow: [
                      BoxShadow(
                        color: Color(0x2B101828),
                        blurRadius: 34,
                        spreadRadius: -7,
                        offset: Offset(12, 8),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: const BorderRadius.horizontal(
                      left: Radius.circular(31),
                    ),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            Colors.white.withValues(alpha: .48),
                            FideliTheme.skySoft.withValues(alpha: .27),
                            Colors.white.withValues(alpha: .34),
                          ],
                        ),
                        border: Border(
                          right: BorderSide(
                            color: Colors.white.withValues(alpha: .74),
                          ),
                        ),
                      ),
                      child: _DesktopSidebar(
                        businessName: businessName,
                        quickActions: quickActions,
                        onSignOut: widget.onSignOut,
                      ),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(42, 34, 42, 42),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: _Entrance(
                              controller: _entrance,
                              index: 0,
                              child: const _Header(),
                            ),
                          ),
                          _SessionAvatar(
                            compact: false,
                            onSignOut: widget.onSignOut,
                          ),
                        ],
                      ),
                      const SizedBox(height: 34),
                      Expanded(
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            final columns = constraints.maxWidth >= 1040
                                ? 3
                                : 2;
                            final rows = (modules.length / columns).ceil();
                            const gap = 22.0;
                            final width =
                                (constraints.maxWidth - gap * (columns - 1)) /
                                columns;
                            final height =
                                ((constraints.maxHeight - gap * (rows - 1)) /
                                        rows)
                                    .clamp(0.0, 306.0)
                                    .toDouble();
                            return Wrap(
                              spacing: gap,
                              runSpacing: gap,
                              children: [
                                for (
                                  var index = 0;
                                  index < modules.length;
                                  index++
                                )
                                  SizedBox(
                                    width: width,
                                    child: _Entrance(
                                      controller: _entrance,
                                      index: index + 1,
                                      child: _ModuleCard(
                                        module: modules[index],
                                        height: height,
                                      ),
                                    ),
                                  ),
                              ],
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _compact() {
    final modules = _modules();
    return Stack(
      children: [
        SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(18, 26, 18, 116),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(right: 58),
                child: _Entrance(
                  controller: _entrance,
                  index: 0,
                  child: const _Header(compact: true),
                ),
              ),
              const SizedBox(height: 28),
              LayoutBuilder(
                builder: (context, constraints) {
                  const gap = 12.0;
                  final width = (constraints.maxWidth - gap) / 2;
                  return Wrap(
                    spacing: gap,
                    runSpacing: gap,
                    children: [
                      for (var index = 0; index < modules.length; index++)
                        SizedBox(
                          width: width,
                          child: _Entrance(
                            controller: _entrance,
                            index: index + 1,
                            child: _ModuleCard(
                              module: modules[index],
                              height: index == 4 ? 220 : 238,
                              compact: true,
                            ),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
        Positioned(
          top: 22,
          right: 18,
          child: _SessionAvatar(compact: true, onSignOut: widget.onSignOut),
        ),
      ],
    );
  }

  List<_Module> _modules() => [
    _Module(
      id: 'programs',
      title: 'Programa\nde fidelidad',
      asset: 'assets/images/dashboard/dashboard_coffee.png',
      onPressed: widget.onProgramsPressed,
      backgroundColor: FideliTheme.surface,
    ),
    _Module(
      id: 'customers',
      title: 'Tus\nclientes',
      asset: 'assets/images/dashboard/dashboard_people.png',
      onPressed: widget.onCustomersPressed,
      backgroundColor: FideliTheme.skySoft,
    ),
    _Module(
      id: 'campaigns',
      title: 'Crear una\ncampaña',
      asset: 'assets/images/dashboard/dashboard_campaign.png',
      onPressed: widget.onCampaignsPressed,
      imageAlignment: Alignment.centerRight,
      backgroundColor: FideliTheme.graySoft,
    ),
    _Module(
      id: 'wallet',
      title: 'Wallet\nStudio',
      asset: 'assets/images/dashboard/dashboard_wallet.png',
      onPressed: widget.onWalletPressed,
      dark: true,
      backgroundColor: FideliTheme.ink,
    ),
    _Module(
      id: 'storefront',
      title: 'Tienda\nvirtual',
      asset: 'assets/images/dashboard/dashboard_campaign.png',
      onPressed: widget.onStorefrontPressed ?? widget.onBusinessPressed,
      backgroundColor: FideliTheme.graySoft,
    ),
    _Module(
      id: 'business',
      title: 'Mi\nnegocio',
      asset: 'assets/images/dashboard/dashboard_business.png',
      onPressed: widget.onBusinessPressed,
      imageAlignment: Alignment.centerRight,
      backgroundColor: FideliTheme.skyMuted,
    ),
  ];

  List<_QuickAction> _quickActions() => [
    _QuickAction(
      title: 'Crear tarjeta',
      description: 'Nuevo programa',
      onPressed: widget.onNewProgramPressed ?? widget.onProgramsPressed,
    ),
    _QuickAction(
      title: 'Escanear cliente',
      description: 'Registrar una visita',
      onPressed: widget.onScanPressed ?? widget.onCustomersPressed,
    ),
    _QuickAction(
      title: 'Enviar campaña',
      description: 'Preparar un mensaje',
      onPressed: widget.onNewCampaignPressed ?? widget.onCampaignsPressed,
    ),
    _QuickAction(
      title: 'Personalizar tarjeta',
      description: 'Color, imagen y estilo',
      onPressed: widget.onWalletPressed,
    ),
    _QuickAction(
      title: 'Compartir enlace',
      description: 'Invitar a un cliente',
      onPressed: widget.onSharePressed,
    ),
    _QuickAction(
      title: 'Cambiar logo y datos',
      description: 'Identidad del negocio',
      onPressed: widget.onBusinessPressed,
    ),
  ];
}

class _Header extends StatelessWidget {
  const _Header({this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          compact ? 'Tu espacio de fidelización' : 'Recursos de tu negocio',
          style: TextStyle(
            fontSize: compact ? 14 : 16,
            fontWeight: FontWeight.w500,
            color: FideliTheme.muted,
          ),
        ),
      ],
    );
  }
}

class _Module {
  const _Module({
    required this.id,
    required this.title,
    required this.asset,
    required this.onPressed,
    this.dark = false,
    this.imageAlignment = Alignment.center,
    this.backgroundColor = FideliTheme.surface,
  });

  final String id;
  final String title;
  final String asset;
  final ValueChanged<Rect> onPressed;
  final bool dark;
  final Alignment imageAlignment;
  final Color backgroundColor;
}

class _QuickAction {
  const _QuickAction({
    required this.title,
    required this.description,
    required this.onPressed,
  });

  final String title;
  final String description;
  final ValueChanged<Rect> onPressed;
}

class _ModuleCard extends StatefulWidget {
  const _ModuleCard({
    required this.module,
    required this.height,
    this.compact = false,
  });

  final _Module module;
  final double height;
  final bool compact;

  @override
  State<_ModuleCard> createState() => _ModuleCardState();
}

class _ModuleCardState extends State<_ModuleCard> {
  bool _hovered = false;
  bool _pressed = false;

  void _open() {
    final box = context.findRenderObject()! as RenderBox;
    widget.module.onPressed(box.localToGlobal(Offset.zero) & box.size);
  }

  @override
  Widget build(BuildContext context) {
    final module = widget.module;
    final foreground = module.dark ? Colors.white : FideliTheme.ink;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedSlide(
        offset: _hovered ? const Offset(0, -.025) : Offset.zero,
        duration: const Duration(milliseconds: 230),
        curve: Curves.easeOutCubic,
        child: AnimatedScale(
          scale: _pressed ? .985 : (_hovered ? 1.018 : 1),
          duration: const Duration(milliseconds: 230),
          curve: Curves.easeOutBack,
          child: AnimatedContainer(
            key: ValueKey('dashboard-module-${module.id}'),
            duration: const Duration(milliseconds: 230),
            height: widget.height,
            decoration: BoxDecoration(
              color: module.backgroundColor,
              borderRadius: BorderRadius.circular(widget.compact ? 24 : 28),
            ),
            child: Material(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(widget.compact ? 24 : 28),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: _open,
                onHighlightChanged: (value) => setState(() => _pressed = value),
                child: Stack(
                  children: [
                    Positioned(
                      left: widget.compact ? 12 : null,
                      right: widget.compact ? 12 : 14,
                      top: widget.compact ? 54 : null,
                      bottom: widget.compact ? null : 14,
                      width: widget.compact ? null : 218,
                      height: widget.compact ? 98 : 188,
                      child: Stack(
                        alignment: module.imageAlignment,
                        children: [
                          Align(
                            alignment: module.imageAlignment,
                            child: FractionallySizedBox(
                              widthFactor: widget.compact ? .78 : .96,
                              heightFactor: widget.compact ? .94 : 1,
                              child: Image.asset(
                                module.asset,
                                fit: BoxFit.contain,
                                alignment: module.imageAlignment,
                                color: module.dark
                                    ? Colors.white.withValues(alpha: .86)
                                    : null,
                                colorBlendMode: BlendMode.srcIn,
                                filterQuality: FilterQuality.medium,
                                errorBuilder: (_, error, stackTrace) =>
                                    const SizedBox.shrink(),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: EdgeInsets.all(widget.compact ? 16 : 22),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Spacer(),
                          Align(
                            alignment: Alignment.bottomLeft,
                            child: FractionallySizedBox(
                              widthFactor: widget.compact ? 1 : .58,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    module.title,
                                    style: TextStyle(
                                      color: foreground,
                                      fontFamily: 'Poppins',
                                      fontSize: widget.compact ? 19 : 25,
                                      height: .98,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: -.8,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DesktopSidebar extends StatelessWidget {
  const _DesktopSidebar({
    required this.businessName,
    required this.quickActions,
    required this.onSignOut,
  });

  final String businessName;
  final List<_QuickAction> quickActions;
  final Future<void> Function() onSignOut;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            label: 'Studio Fideli',
            image: true,
            child: SizedBox(
              width: 158,
              height: 97,
              child: Image(
                key: ValueKey('studio-fideli-sidebar-logo'),
                image: AssetImage(
                  'assets/images/dashboard/studio_fideli_logo.png',
                ),
                alignment: Alignment.centerLeft,
                fit: BoxFit.contain,
                filterQuality: FilterQuality.medium,
                excludeFromSemantics: true,
              ),
            ),
          ),
          const SizedBox(height: 24),
          for (final action in quickActions) _SidebarAction(action: action),
          const Spacer(),
          const Divider(),
          const SizedBox(height: 16),
          Text(
            businessName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 3),
          const Text(
            'Cuenta del comercio',
            style: TextStyle(color: FideliTheme.muted, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _SidebarAction extends StatefulWidget {
  const _SidebarAction({required this.action});

  final _QuickAction action;

  @override
  State<_SidebarAction> createState() => _SidebarActionState();
}

class _SidebarActionState extends State<_SidebarAction> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 190),
          curve: Curves.easeOutCubic,
          decoration: BoxDecoration(
            color: _hovered ? FideliTheme.surfaceSoft : Colors.transparent,
            borderRadius: BorderRadius.circular(17),
            border: Border.all(
              color: _hovered ? FideliTheme.line : Colors.transparent,
            ),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(17),
            onTap: () {
              final box = context.findRenderObject()! as RenderBox;
              widget.action.onPressed(
                box.localToGlobal(Offset.zero) & box.size,
              );
            },
            child: AnimatedPadding(
              duration: const Duration(milliseconds: 190),
              padding: EdgeInsets.fromLTRB(_hovered ? 14 : 10, 11, 10, 11),
              child: SizedBox(
                width: double.infinity,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.action.title,
                      style: const TextStyle(
                        color: FideliTheme.inkSoft,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      widget.action.description,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: FideliTheme.muted.withValues(alpha: .86),
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Entrance extends StatelessWidget {
  const _Entrance({
    required this.controller,
    required this.index,
    required this.child,
  });

  final AnimationController controller;
  final int index;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final start = (index * .065).clamp(0.0, .5);
    final animation = CurvedAnimation(
      parent: controller,
      curve: Interval(start, 1, curve: Curves.easeOutCubic),
    );
    return FadeTransition(
      opacity: animation,
      child: SlideTransition(
        position: Tween(
          begin: const Offset(0, .06),
          end: Offset.zero,
        ).animate(animation),
        child: child,
      ),
    );
  }
}

class _SessionAvatar extends StatefulWidget {
  const _SessionAvatar({required this.compact, required this.onSignOut});

  final bool compact;
  final Future<void> Function() onSignOut;

  @override
  State<_SessionAvatar> createState() => _SessionAvatarState();
}

class _SessionAvatarState extends State<_SessionAvatar>
    with SingleTickerProviderStateMixin {
  final LayerLink _layerLink = LayerLink();
  OverlayEntry? _overlay;
  late final AnimationController _controller;
  bool _signingOut = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 330),
      reverseDuration: const Duration(milliseconds: 190),
    );
  }

  String get _accountName {
    final user = CloudStore.instance?.currentUser;
    final metadata = user?.userMetadata;
    final storedName = (metadata?['full_name'] ?? metadata?['name'])
        ?.toString()
        .trim();
    if (storedName != null && storedName.isNotEmpty) return storedName;
    final emailName = (user?.email ?? '').split('@').first.trim();
    if (emailName.isEmpty) return 'Mi cuenta';
    return emailName[0].toUpperCase() + emailName.substring(1);
  }

  void _toggleMenu() => _overlay == null ? _openMenu() : _closeMenu();

  void _openMenu() {
    final overlay = Overlay.of(context);
    _overlay = OverlayEntry(
      builder: (_) {
        final businessName = AppScope.of(context).data.business.name.trim();
        final animation = CurvedAnimation(
          parent: _controller,
          curve: Curves.easeOutBack,
          reverseCurve: Curves.easeInCubic,
        );
        return Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: _closeMenu,
              ),
            ),
            CompositedTransformFollower(
              link: _layerLink,
              targetAnchor: Alignment.bottomRight,
              followerAnchor: Alignment.topRight,
              offset: const Offset(0, 10),
              showWhenUnlinked: false,
              child: AnimatedBuilder(
                animation: animation,
                builder: (context, child) => Opacity(
                  opacity: _controller.value.clamp(0, 1),
                  child: Transform.scale(
                    alignment: Alignment.topRight,
                    scale: .78 + .22 * animation.value,
                    child: child,
                  ),
                ),
                child: Material(
                  color: Colors.transparent,
                  child: Container(
                    width: 246,
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(color: FideliTheme.line),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x24000000),
                          blurRadius: 30,
                          offset: Offset(0, 13),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _accountName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          businessName.isEmpty ? 'Mi negocio' : businessName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: FideliTheme.muted,
                            fontSize: 13,
                          ),
                        ),
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 12),
                          child: Divider(height: 1),
                        ),
                        InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: _signingOut
                              ? null
                              : () async {
                                  _signingOut = true;
                                  await _closeMenu();
                                  if (!mounted) return;
                                  await widget.onSignOut();
                                },
                          child: const SizedBox(
                            width: double.infinity,
                            child: Padding(
                              padding: EdgeInsets.symmetric(vertical: 9),
                              child: Text(
                                'Cerrar sesión',
                                style: TextStyle(
                                  color: FideliTheme.danger,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
    overlay.insert(_overlay!);
    _controller.forward(from: 0);
  }

  Future<void> _closeMenu() async {
    if (_overlay == null) return;
    await _controller.reverse();
    _overlay?.remove();
    _overlay = null;
  }

  @override
  void dispose() {
    _overlay?.remove();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.compact ? 44.0 : 54.0;
    return CompositedTransformTarget(
      link: _layerLink,
      child: Tooltip(
        message: 'Mi cuenta',
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: _toggleMenu,
          child: Container(
            width: size,
            height: size,
            decoration: const BoxDecoration(
              color: FideliTheme.ink,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.person_rounded,
              color: Colors.white,
              size: widget.compact ? 22 : 27,
            ),
          ),
        ),
      ),
    );
  }
}
