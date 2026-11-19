import 'package:flutter/material.dart';

import '../widgets/scanner_action_button.dart';
import 'business_screen.dart';
import 'campaigns_screen.dart';
import 'customers_screen.dart';
import 'dashboard_screen.dart';
import 'programs_screen.dart';
import 'rewards_screen.dart';
import 'storefront_screen.dart';
import 'wallet_studio_screen.dart';
import 'whatsapp_screen.dart';

class NavigationMenuScreen extends StatefulWidget {
  const NavigationMenuScreen({super.key, required this.onSignOut});

  final Future<void> Function() onSignOut;

  @override
  State<NavigationMenuScreen> createState() => _NavigationMenuScreenState();
}

class _NavigationMenuScreenState extends State<NavigationMenuScreen> {
  bool _dashboardEntrancePlayed = false;
  String _selectedSection = 'Dashboard';

  Future<void> _openFromCard({
    required Rect sourceRect,
    required String title,
    required Widget page,
  }) {
    if (!sourceRect.isFinite) return Future<void>.value();
    setState(() => _selectedSection = title);
    return Navigator.of(
      context,
    ).push(_CardRoute(title: title, page: page)).whenComplete(() {
      if (mounted) setState(() => _selectedSection = 'Dashboard');
    });
  }

  @override
  Widget build(BuildContext context) {
    final animateDashboard = !_dashboardEntrancePlayed;
    _dashboardEntrancePlayed = true;
    return Scaffold(
      body: DashboardScreen(
        animateEntrance: animateDashboard,
        selectedSection: _selectedSection,
        onSignOut: widget.onSignOut,
        onProgramsPressed: (rect) => _openFromCard(
          sourceRect: rect,
          title: 'Programas',
          page: const ProgramsScreen(),
        ),
        onCustomersPressed: (rect) => _openFromCard(
          sourceRect: rect,
          title: 'Clientes',
          page: const CustomersScreen(),
        ),
        onRewardsPressed: (rect) => _openFromCard(
          sourceRect: rect,
          title: 'Premios',
          page: const RewardsScreen(),
        ),
        onCampaignsPressed: (rect) => _openFromCard(
          sourceRect: rect,
          title: 'Campañas',
          page: const CampaignsScreen(),
        ),
        onStorefrontPressed: (rect) => _openFromCard(
          sourceRect: rect,
          title: 'Tienda virtual',
          page: const StorefrontScreen(),
        ),
        onWalletPressed: (rect) => _openFromCard(
          sourceRect: rect,
          title: 'Wallet Studio',
          page: const _WalletStudioHubScreen(),
        ),
        onWhatsAppPressed: (rect) => _openFromCard(
          sourceRect: rect,
          title: 'WhatsApp',
          page: const WhatsAppScreen(),
        ),
      ),
      floatingActionButton: const ScannerActionButton(),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
    );
  }
}

class _WalletStudioHubScreen extends StatelessWidget {
  const _WalletStudioHubScreen();

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          Material(
            color: Colors.white,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xFFF7F4F8),
                  borderRadius: BorderRadius.circular(22),
                ),
                child: TabBar(
                  dividerColor: Colors.transparent,
                  indicatorSize: TabBarIndicatorSize.tab,
                  indicator: BoxDecoration(
                    color: const Color(0xFF493354),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  labelColor: Colors.white,
                  unselectedLabelColor: const Color(0xFF493354),
                  labelStyle: const TextStyle(fontWeight: FontWeight.w700),
                  tabs: const [
                    Tab(
                      icon: Icon(Icons.wallet_rounded),
                      text: 'Wallet Studio',
                    ),
                    Tab(
                      icon: Icon(Icons.storefront_rounded),
                      text: 'Mi Negocio',
                    ),
                  ],
                ),
              ),
            ),
          ),
          const Expanded(
            child: TabBarView(
              children: [WalletStudioScreen(), BusinessScreen()],
            ),
          ),
        ],
      ),
    );
  }
}

class _CardRoute extends PageRouteBuilder<void> {
  _CardRoute({required String title, required Widget page})
    : super(
        opaque: false,
        barrierDismissible: true,
        barrierColor: const Color(0x260E0B12),
        barrierLabel: 'Cerrar apartado',
        transitionDuration: const Duration(milliseconds: 520),
        reverseTransitionDuration: const Duration(milliseconds: 360),
        pageBuilder: (context, animation, secondaryAnimation) =>
            _SlidingSectionPanel(title: title, page: page),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          final slide = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutBack,
            reverseCurve: Curves.easeInCubic,
          );
          final fade = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
            reverseCurve: Curves.easeInCubic,
          );
          return FadeTransition(
            opacity: fade,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(1, 0),
                end: Offset.zero,
              ).animate(slide),
              child: child,
            ),
          );
        },
      );
}

class _SlidingSectionPanel extends StatefulWidget {
  const _SlidingSectionPanel({required this.title, required this.page});

  final String title;
  final Widget page;

  @override
  State<_SlidingSectionPanel> createState() => _SlidingSectionPanelState();
}

class _SlidingSectionPanelState extends State<_SlidingSectionPanel> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final viewport = MediaQuery.sizeOf(context);
    final widthFactor = viewport.width >= 760 ? .52 : .9;
    final panelWidth = _expanded
        ? viewport.width
        : viewport.width * widthFactor;
    final radius = _expanded ? 0.0 : 36.0;

    return SafeArea(
      child: Align(
        alignment: Alignment.centerRight,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 460),
          curve: Curves.easeOutBack,
          width: panelWidth,
          height: double.infinity,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.horizontal(
              left: Radius.circular(radius),
            ),
            boxShadow: const [
              BoxShadow(
                color: Color(0x240E0B12),
                blurRadius: 28,
                offset: Offset(-10, 0),
              ),
            ],
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final panelMedia = MediaQuery.of(context).copyWith(
                size: Size(constraints.maxWidth, constraints.maxHeight),
              );
              return MediaQuery(
                data: panelMedia,
                child: Scaffold(
                  appBar: AppBar(
                    leading: IconButton(
                      tooltip: 'Volver al Dashboard',
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.arrow_back_ios_new_rounded),
                    ),
                    title: Text(widget.title),
                    centerTitle: true,
                    actions: [
                      if (widget.title == 'Tienda virtual')
                        IconButton(
                          tooltip: _expanded
                              ? 'Volver a media pantalla'
                              : 'Pantalla completa',
                          onPressed: () =>
                              setState(() => _expanded = !_expanded),
                          icon: Icon(
                            _expanded
                                ? Icons.fullscreen_exit_rounded
                                : Icons.fullscreen_rounded,
                          ),
                        ),
                    ],
                  ),
                  body: widget.page,
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
