import 'package:flutter/material.dart';

import '../widgets/scanner_action_button.dart';
import 'business_screen.dart';
import 'campaigns_screen.dart';
import 'customers_screen.dart';
import 'dashboard_screen.dart';
import 'programs_screen.dart';
import 'scan_customer_screen.dart';
import 'share_club_screen.dart';
import 'storefront_screen.dart';
import 'wallet_studio_screen.dart';

class NavigationMenuScreen extends StatefulWidget {
  const NavigationMenuScreen({super.key, required this.onSignOut});

  final Future<void> Function() onSignOut;

  @override
  State<NavigationMenuScreen> createState() => _NavigationMenuScreenState();
}

class _NavigationMenuScreenState extends State<NavigationMenuScreen> {
  bool _dashboardEntrancePlayed = false;

  void _openFromCard({
    required Rect sourceRect,
    required String title,
    required Widget page,
  }) {
    if (!sourceRect.isFinite) return;
    Navigator.of(context).push(_CardRoute(title: title, page: page));
  }

  void _openScanner() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => Scaffold(
          appBar: AppBar(
            leading: IconButton(
              tooltip: 'Volver al Dashboard',
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.arrow_back_ios_new_rounded),
            ),
            title: const Text('Escanear cliente'),
            centerTitle: true,
          ),
          body: const ScanCustomerScreen(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final animateDashboard = !_dashboardEntrancePlayed;
    _dashboardEntrancePlayed = true;
    return Scaffold(
      body: DashboardScreen(
        animateEntrance: animateDashboard,
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
        onCampaignsPressed: (rect) => _openFromCard(
          sourceRect: rect,
          title: 'Campañas',
          page: const CampaignsScreen(),
        ),
        onBusinessPressed: (rect) => _openFromCard(
          sourceRect: rect,
          title: 'Mi negocio',
          page: const BusinessScreen(),
        ),
        onStorefrontPressed: (rect) => _openFromCard(
          sourceRect: rect,
          title: 'Tienda virtual',
          page: const StorefrontScreen(),
        ),
        onSharePressed: (rect) => _openFromCard(
          sourceRect: rect,
          title: 'Compartir cafetería',
          page: const ShareClubScreen(),
        ),
        onWalletPressed: (rect) => _openFromCard(
          sourceRect: rect,
          title: 'Wallet Studio',
          page: const WalletStudioScreen(),
        ),
        onScanPressed: (_) => _openScanner(),
        onNewProgramPressed: (rect) => _openFromCard(
          sourceRect: rect,
          title: 'Nueva tarjeta',
          page: const ProgramsScreen(openCreatorOnStart: true),
        ),
        onNewCampaignPressed: (rect) => _openFromCard(
          sourceRect: rect,
          title: 'Nueva campaña',
          page: const CampaignsScreen(openComposerOnStart: true),
        ),
      ),
      floatingActionButton: const ScannerActionButton(),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
    );
  }
}

class _CardRoute extends PageRouteBuilder<void> {
  _CardRoute({required String title, required Widget page})
    : super(
        opaque: true,
        transitionDuration: const Duration(milliseconds: 300),
        reverseTransitionDuration: const Duration(milliseconds: 230),
        pageBuilder: (context, animation, secondaryAnimation) => Scaffold(
          appBar: AppBar(
            leading: IconButton(
              tooltip: 'Volver al Dashboard',
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.arrow_back_ios_new_rounded),
            ),
            title: Text(title),
            centerTitle: true,
          ),
          body: page,
        ),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          final curved = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
            reverseCurve: Curves.easeInCubic,
          );
          return FadeTransition(
            opacity: curved,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(.025, .015),
                end: Offset.zero,
              ).animate(curved),
              child: child,
            ),
          );
        },
      );
}
