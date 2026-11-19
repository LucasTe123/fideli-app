import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../models/app_data.dart';
import '../services/cloud_store.dart';
import '../state/app_scope.dart';
import '../widgets/customer_avatar.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({
    super.key,
    required this.onProgramsPressed,
    required this.onCustomersPressed,
    required this.onRewardsPressed,
    required this.onCampaignsPressed,
    this.onStorefrontPressed,
    required this.onWalletPressed,
    this.onWhatsAppPressed,
    required this.onSignOut,
    this.selectedSection = 'Dashboard',
    this.animateEntrance = true,
  });

  final ValueChanged<Rect> onProgramsPressed;
  final ValueChanged<Rect> onCustomersPressed;
  final ValueChanged<Rect> onRewardsPressed;
  final ValueChanged<Rect> onCampaignsPressed;
  final Future<void> Function(Rect)? onStorefrontPressed;
  final ValueChanged<Rect> onWalletPressed;
  final ValueChanged<Rect>? onWhatsAppPressed;
  final Future<void> Function() onSignOut;
  final String selectedSection;
  final bool animateEntrance;

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen>
    with SingleTickerProviderStateMixin {
  static const _plum = Color(0xFF493354);
  static const _coral = Color(0xFFED5264);
  static const _gold = Color(0xFFF5B51B);
  static const _paper = Color(0xFFF8F8F7);
  static const _ink = Color(0xFF26242B);
  static const _muted = Color(0xFF77747C);

  late final AnimationController _entrance;
  Uint8List? _businessMark;
  String? _businessMarkKey;

  @override
  void initState() {
    super.initState();
    _entrance = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 750),
      value: widget.animateEntrance ? 0 : 1,
    );
    if (widget.animateEntrance) _entrance.forward();
  }

  @override
  void dispose() {
    _entrance.dispose();
    super.dispose();
  }

  void _loadBusinessMarkIfNeeded(AppData data) {
    final logoPath = data.business.walletLogoPath;
    final iconPath = data.business.walletIconPath;
    final key = '$logoPath|$iconPath';
    if (key == _businessMarkKey) return;
    _businessMarkKey = key;
    _businessMark = null;
    if (logoPath.isEmpty && iconPath.isEmpty) return;
    unawaited(() async {
      final mark = await CloudStore.instance?.downloadBusinessMark(
        logoPath: logoPath,
        iconPath: iconPath,
      );
      if (!mounted || _businessMarkKey != key) return;
      setState(() => _businessMark = mark);
    }());
  }

  @override
  Widget build(BuildContext context) {
    final data = AppScope.of(context).data;
    _loadBusinessMarkIfNeeded(data);
    final businessName = data.business.name.trim().isEmpty
        ? 'Tu negocio'
        : data.business.name.trim();
    return ColoredBox(
      color: _paper,
      child: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth >= 1320) {
              return _desktop(data, businessName);
            }
            return _compact(data, businessName);
          },
        ),
      ),
    );
  }

  Widget _desktop(AppData data, String businessName) {
    return Padding(
      padding: const EdgeInsets.all(18),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: _plum,
          borderRadius: BorderRadius.circular(60),
          border: Border.all(color: const Color(0xFFE8E6E9)),
          boxShadow: const [
            BoxShadow(
              color: Color(0x0C292236),
              blurRadius: 34,
              offset: Offset(0, 12),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(60),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: 206,
                child: _Sidebar(
                  businessName: businessName,
                  businessMark: _businessMark,
                  onSignOut: widget.onSignOut,
                  entries: _navigationEntries(),
                  selected: widget.selectedSection,
                ),
              ),
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(54),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(28, 28, 18, 26),
                          child: _mainContent(
                            data,
                            businessName,
                            compact: false,
                          ),
                        ),
                      ),
                      SizedBox(
                        width: 640,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(0, 18, 18, 18),
                          child: _PerformancePanel(data: data),
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

  Widget _compact(AppData data, String businessName) {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(18, 20, 18, 118),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _mainContent(data, businessName, compact: true),
          const SizedBox(height: 20),
          _PerformancePanel(data: data, compact: true),
          const SizedBox(height: 20),
          _CompactNavigation(
            entries: _navigationEntries(),
            selected: widget.selectedSection,
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: widget.onSignOut,
              icon: const Icon(Icons.logout_rounded, size: 18),
              label: const Text('Cerrar sesión'),
              style: TextButton.styleFrom(foregroundColor: _plum),
            ),
          ),
        ],
      ),
    );
  }

  Widget _mainContent(
    AppData data,
    String businessName, {
    required bool compact,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Entrance(
          controller: _entrance,
          index: 0,
          child: _MainHeader(businessName: businessName, compact: compact),
        ),
        SizedBox(height: compact ? 20 : 24),
        _Entrance(
          controller: _entrance,
          index: 1,
          child: _WelcomeBanner(
            customerCount: data.customers.length,
            compact: compact,
          ),
        ),
        SizedBox(height: compact ? 14 : 18),
        _Entrance(
          controller: _entrance,
          index: 2,
          child: _StoreProductsCarousel(
            compact: compact,
            onStorefrontPressed: widget.onStorefrontPressed,
          ),
        ),
      ],
    );
  }

  List<_NavigationEntry> _navigationEntries() {
    final now = DateTime.now();
    final birthdayCount = AppScope.of(context).data.customers
        .where(
          (customer) =>
              customer.birthDate?.month == now.month &&
              customer.birthDate?.day == now.day,
        )
        .length;
    return [
      _NavigationEntry(
        title: 'Programas',
        icon: Icons.loyalty_outlined,
        onPressed: widget.onProgramsPressed,
      ),
      _NavigationEntry(
        title: 'Clientes',
        icon: Icons.people_alt_outlined,
        onPressed: widget.onCustomersPressed,
      ),
      _NavigationEntry(
        title: 'Premios',
        icon: Icons.card_giftcard_rounded,
        onPressed: widget.onRewardsPressed,
        badgeCount: birthdayCount,
      ),
      _NavigationEntry(
        title: 'Campañas',
        icon: Icons.campaign_outlined,
        onPressed: widget.onCampaignsPressed,
      ),
      _NavigationEntry(
        title: 'Wallet Studio',
        icon: Icons.style_outlined,
        onPressed: widget.onWalletPressed,
      ),
      _NavigationEntry(
        title: 'WhatsApp',
        icon: Icons.chat_rounded,
        onPressed: widget.onWhatsAppPressed,
      ),
    ];
  }
}

class _StoreProductsCarousel extends StatefulWidget {
  const _StoreProductsCarousel({
    required this.compact,
    this.onStorefrontPressed,
  });

  final bool compact;
  final Future<void> Function(Rect)? onStorefrontPressed;

  @override
  State<_StoreProductsCarousel> createState() => _StoreProductsCarouselState();
}

class _StoreProductsCarouselState extends State<_StoreProductsCarousel> {
  final _pageController = PageController();
  final _cardKey = GlobalKey();
  List<Map<String, dynamic>> _products = [];
  bool _loading = true;
  String? _error;
  int _currentPage = 0;

  @override
  void initState() {
    super.initState();
    _loadProducts();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _loadProducts() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final cloud = CloudStore.instance;
      if (cloud == null) throw StateError('store unavailable');
      final products = await cloud.loadStoreProducts();
      if (!mounted) return;
      setState(() {
        _products = products
            .where((product) => product['active'] != false)
            .toList();
        _currentPage = 0;
        _loading = false;
      });
      if (_pageController.hasClients) _pageController.jumpToPage(0);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'No pudimos cargar tus productos.';
      });
    }
  }

  String _price(Map<String, dynamic> product) {
    final price = num.tryParse(product['price']?.toString() ?? '');
    return price == null ? '' : 'Bs ${price.toStringAsFixed(2)}';
  }

  void _goTo(int page) {
    if (_products.isEmpty) return;
    _pageController.animateToPage(
      page.clamp(0, _products.length - 1),
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _openStorefront() async {
    final callback = widget.onStorefrontPressed;
    final renderObject = _cardKey.currentContext?.findRenderObject();
    if (callback == null || renderObject is! RenderBox) return;
    await callback(renderObject.localToGlobal(Offset.zero) & renderObject.size);
    if (mounted) unawaited(_loadProducts());
  }

  @override
  Widget build(BuildContext context) {
    final compact = widget.compact;
    final size = compact ? 252.0 : 304.0;
    return Align(
      alignment: Alignment.centerLeft,
      child: SizedBox(
        key: _cardKey,
        width: size,
        height: size,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onStorefrontPressed == null
              ? null
              : () => unawaited(_openStorefront()),
          child: Container(
            padding: EdgeInsets.all(compact ? 14 : 17),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(compact ? 34 : 42),
              border: Border.all(color: const Color(0xFFECEAEC)),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x0C292236),
                  blurRadius: 24,
                  offset: Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Tu tienda virtual',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: _DashboardScreenState._ink,
                          fontSize: compact ? 16 : 19,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -.5,
                        ),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: compact ? 7 : 9),
                Expanded(child: _carouselBody(compact)),
                if (_products.length > 1) ...[
                  SizedBox(height: compact ? 0 : 2),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton(
                        tooltip: 'Producto anterior',
                        onPressed: () => _goTo(_currentPage - 1),
                        visualDensity: VisualDensity.compact,
                        color: _DashboardScreenState._plum,
                        icon: const Icon(Icons.arrow_back_ios_new_rounded),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '${_currentPage + 1} / ${_products.length}',
                        style: TextStyle(
                          color: _DashboardScreenState._muted,
                          fontSize: compact ? 10 : 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(width: 4),
                      IconButton(
                        tooltip: 'Producto siguiente',
                        onPressed: () => _goTo(_currentPage + 1),
                        visualDensity: VisualDensity.compact,
                        color: _DashboardScreenState._plum,
                        icon: const Icon(Icons.arrow_forward_ios_rounded),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _carouselBody(bool compact) {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(
          color: _DashboardScreenState._coral,
          strokeWidth: 3,
        ),
      );
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.cloud_off_rounded,
              color: _DashboardScreenState._muted,
              size: 40,
            ),
            const SizedBox(height: 10),
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: _DashboardScreenState._muted),
            ),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: _loadProducts,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Volver a intentar'),
            ),
          ],
        ),
      );
    }
    if (_products.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.storefront_outlined,
                color: _DashboardScreenState._plum.withValues(alpha: .6),
                size: compact ? 42 : 54,
              ),
              const SizedBox(height: 12),
              Text(
                'Tus productos aparecerán aquí',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: _DashboardScreenState._ink,
                  fontSize: compact ? 14 : 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                'Agrega productos desde Mi tienda para verlos en este carrusel.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: _DashboardScreenState._muted,
                  fontSize: compact ? 11 : 13,
                ),
              ),
            ],
          ),
        ),
      );
    }
    return PageView.builder(
      controller: _pageController,
      itemCount: _products.length,
      onPageChanged: (index) => setState(() => _currentPage = index),
      itemBuilder: (context, index) => _StoreProductSlide(
        product: _products[index],
        price: _price(_products[index]),
        compact: compact,
      ),
    );
  }
}

class _StoreProductSlide extends StatelessWidget {
  const _StoreProductSlide({
    required this.product,
    required this.price,
    required this.compact,
  });

  final Map<String, dynamic> product;
  final String price;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final imageUrl = product['image_url']?.toString().trim() ?? '';
    final name = product['name']?.toString().trim() ?? 'Producto';
    return Padding(
      padding: EdgeInsets.only(bottom: compact ? 2 : 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(compact ? 24 : 32),
              child: imageUrl.isEmpty
                  ? _imagePlaceholder(compact)
                  : Image.network(
                      imageUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => _imagePlaceholder(compact),
                    ),
            ),
          ),
          SizedBox(height: compact ? 6 : 8),
          Row(
            children: [
              Expanded(
                child: Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: _DashboardScreenState._ink,
                    fontSize: compact ? 13 : 16,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -.3,
                  ),
                ),
              ),
              if (price.isNotEmpty) ...[
                const SizedBox(width: 8),
                Text(
                  price,
                  style: TextStyle(
                    color: _DashboardScreenState._plum,
                    fontSize: compact ? 12 : 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _imagePlaceholder(bool compact) => ColoredBox(
    color: const Color(0xFFFFF0F0),
    child: Center(
      child: Icon(
        Icons.shopping_bag_outlined,
        color: _DashboardScreenState._coral,
        size: compact ? 48 : 64,
      ),
    ),
  );
}

class _MainHeader extends StatelessWidget {
  const _MainHeader({required this.businessName, required this.compact});

  final String businessName;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final weekdays = [
      'lunes',
      'martes',
      'miércoles',
      'jueves',
      'viernes',
      'sábado',
      'domingo',
    ];
    final months = [
      'enero',
      'febrero',
      'marzo',
      'abril',
      'mayo',
      'junio',
      'julio',
      'agosto',
      'septiembre',
      'octubre',
      'noviembre',
      'diciembre',
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '¡Hola, $businessName!',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: _DashboardScreenState._ink,
            fontSize: compact ? 24 : 28,
            fontWeight: FontWeight.w800,
            letterSpacing: -1.2,
            height: 1.1,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          '${now.day} de ${months[now.month - 1]}, ${weekdays[now.weekday - 1]}',
          style: TextStyle(
            color: _DashboardScreenState._muted,
            fontSize: compact ? 12 : 13,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

class _WelcomeBanner extends StatelessWidget {
  const _WelcomeBanner({required this.customerCount, required this.compact});

  final int customerCount;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(
        compact ? 18 : 24,
        compact ? 18 : 22,
        compact ? 14 : 18,
        compact ? 18 : 22,
      ),
      decoration: BoxDecoration(
        color: _DashboardScreenState._coral,
        borderRadius: BorderRadius.circular(compact ? 34 : 48),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '¡Buen trabajo!',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: compact ? 19 : 22,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -.5,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  'Tu club ya conecta con $customerCount ${customerCount == 1 ? 'cliente' : 'clientes'}. Sigue creando buenas experiencias.',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: .92),
                    fontSize: compact ? 11 : 12,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(width: compact ? 10 : 18),
          Image.asset(
            'assets/images/dashboard/welcome_cart.png',
            width: compact ? 66 : 126,
            height: compact ? 58 : 100,
            fit: BoxFit.contain,
            excludeFromSemantics: true,
          ),
        ],
      ),
    );
  }
}

class _PerformancePanel extends StatefulWidget {
  const _PerformancePanel({required this.data, this.compact = false});

  final AppData data;
  final bool compact;

  @override
  State<_PerformancePanel> createState() => _PerformancePanelState();
}

class _PerformancePanelState extends State<_PerformancePanel> {
  late final PageController _pageController;
  int _page = 0;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _goTo(int page) {
    _pageController.animateToPage(
      page.clamp(0, 1),
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    final compact = widget.compact;
    final now = DateTime.now();
    final newCustomers =
        data.customers
            .where(
              (customer) =>
                  customer.joinedAt.year == now.year &&
                  customer.joinedAt.month == now.month,
            )
            .toList()
          ..sort((a, b) => b.joinedAt.compareTo(a.joinedAt));
    final activePrograms = data.programs
        .where((program) => program.active && !program.isExpired)
        .length;
    final weekStart = now.subtract(const Duration(days: 7));
    final weeklyActivities = data.activities
        .where((activity) => activity.createdAt.isAfter(weekStart))
        .length;
    final allActivityCount = data.activities.length;
    final panel = Container(
      width: double.infinity,
      padding: EdgeInsets.all(compact ? 18 : 26),
      decoration: BoxDecoration(
        color: _DashboardScreenState._gold,
        borderRadius: BorderRadius.circular(compact ? 42 : 64),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Rendimiento',
            style: TextStyle(
              color: _DashboardScreenState._ink,
              fontSize: compact ? 20 : 34,
              fontWeight: FontWeight.w800,
              letterSpacing: -.6,
            ),
          ),
          SizedBox(height: compact ? 12 : 18),
          _NewCustomersPage(customers: newCustomers, compact: compact),
          SizedBox(height: compact ? 12 : 18),
          Expanded(
            child: PageView(
              controller: _pageController,
              clipBehavior: Clip.hardEdge,
              onPageChanged: (page) => setState(() => _page = page),
              children: [
                _ProgressPage(
                  newCustomers: newCustomers.length,
                  totalCustomers: data.customers.length,
                  activePrograms: activePrograms,
                  totalPrograms: data.programs.length,
                  weeklyActivities: weeklyActivities,
                  allActivityCount: allActivityCount,
                  compact: compact,
                ),
                _RecentActivityPage(data: data, compact: compact),
              ],
            ),
          ),
          SizedBox(height: compact ? 2 : 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                tooltip: 'Anterior',
                onPressed: _page == 0 ? null : () => _goTo(_page - 1),
                visualDensity: VisualDensity.compact,
                color: _DashboardScreenState._plum,
                icon: const Icon(Icons.arrow_back_ios_new_rounded),
              ),
              const SizedBox(width: 5),
              for (var index = 0; index < 2; index++)
                AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  width: _page == index ? 20 : 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: _page == index
                        ? _DashboardScreenState._plum
                        : _DashboardScreenState._plum.withValues(alpha: .3),
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              const SizedBox(width: 5),
              IconButton(
                tooltip: 'Siguiente',
                onPressed: _page == 1 ? null : () => _goTo(_page + 1),
                visualDensity: VisualDensity.compact,
                color: _DashboardScreenState._plum,
                icon: const Icon(Icons.arrow_forward_ios_rounded),
              ),
            ],
          ),
        ],
      ),
    );

    if (compact) {
      return SizedBox(height: 540, child: panel);
    }
    return SizedBox.expand(child: panel);
  }
}

class _NewCustomersPage extends StatelessWidget {
  const _NewCustomersPage({required this.customers, required this.compact});

  final List<Customer> customers;
  final bool compact;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          Expanded(
            child: Text(
              'Nuevos clientes (${customers.length})',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: _DashboardScreenState._ink,
                fontSize: compact ? 11 : 16,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          if (customers.isNotEmpty)
            Text(
              'este mes',
              style: TextStyle(
                color: _DashboardScreenState._ink.withValues(alpha: .64),
                fontSize: compact ? 9 : 13,
                fontWeight: FontWeight.w600,
              ),
            ),
        ],
      ),
      SizedBox(height: compact ? 12 : 16),
      if (customers.isEmpty)
        Text(
          'Los nuevos clientes aparecerán aquí.',
          style: TextStyle(
            color: _DashboardScreenState._ink,
            fontSize: compact ? 10 : 14,
          ),
        )
      else
        Wrap(
          spacing: compact ? 12 : 16,
          runSpacing: compact ? 10 : 14,
          children: [
            for (final customer in customers.take(compact ? 5 : 4))
              SizedBox(
                width: compact ? 50 : 84,
                child: Column(
                  children: [
                    CustomerAvatar(customer: customer, size: compact ? 40 : 68),
                    SizedBox(height: compact ? 4 : 7),
                    Text(
                      customer.name.split(' ').first,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: _DashboardScreenState._ink,
                        fontSize: compact ? 9 : 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
    ],
  );
}

class _ProgressPage extends StatelessWidget {
  const _ProgressPage({
    required this.newCustomers,
    required this.totalCustomers,
    required this.activePrograms,
    required this.totalPrograms,
    required this.weeklyActivities,
    required this.allActivityCount,
    required this.compact,
  });

  final int newCustomers;
  final int totalCustomers;
  final int activePrograms;
  final int totalPrograms;
  final int weeklyActivities;
  final int allActivityCount;
  final bool compact;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        'Tu progreso',
        style: TextStyle(
          color: _DashboardScreenState._ink,
          fontSize: compact ? 12 : 18,
          fontWeight: FontWeight.w800,
        ),
      ),
      SizedBox(height: compact ? 10 : 14),
      Expanded(
        child: Column(
          children: [
            _ProgressCard(
              title: 'Clientes este mes',
              value: '$newCustomers',
              footnote: 'de $totalCustomers registrados',
              icon: Icons.people_alt_outlined,
              compact: compact,
              progress: totalCustomers == 0 ? 0 : newCustomers / totalCustomers,
            ),
            SizedBox(height: compact ? 10 : 13),
            _ProgressCard(
              title: 'Programas activos',
              value: '$activePrograms',
              footnote: 'de $totalPrograms creados',
              icon: Icons.loyalty_outlined,
              compact: compact,
              progress: totalPrograms == 0 ? 0 : activePrograms / totalPrograms,
            ),
            SizedBox(height: compact ? 10 : 13),
            _ProgressCard(
              title: 'Actividad esta semana',
              value: '$weeklyActivities',
              footnote: 'de $allActivityCount registros',
              icon: Icons.trending_up_rounded,
              compact: compact,
              progress: allActivityCount == 0
                  ? 0
                  : weeklyActivities / allActivityCount,
            ),
          ],
        ),
      ),
    ],
  );
}

class _RecentActivityPage extends StatelessWidget {
  const _RecentActivityPage({required this.data, required this.compact});

  final AppData data;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final activities = [...data.activities]
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final visibleActivities = activities.take(compact ? 4 : 6).toList();
    final customersById = {
      for (final customer in data.customers) customer.id: customer,
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Actividad reciente',
          style: TextStyle(
            color: _DashboardScreenState._ink,
            fontSize: compact ? 12 : 18,
            fontWeight: FontWeight.w800,
          ),
        ),
        SizedBox(height: compact ? 8 : 12),
        if (visibleActivities.isEmpty)
          Expanded(
            child: Center(
              child: Text(
                'Tu actividad reciente aparecerá aquí.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: _DashboardScreenState._ink.withValues(alpha: .72),
                  fontSize: compact ? 11 : 14,
                ),
              ),
            ),
          )
        else
          Expanded(
            child: ListView.separated(
              padding: EdgeInsets.zero,
              physics: const ClampingScrollPhysics(),
              itemCount: visibleActivities.length,
              separatorBuilder: (_, _) => SizedBox(height: compact ? 7 : 10),
              itemBuilder: (context, index) {
                final activity = visibleActivities[index];
                final customer = customersById[activity.customerId];
                return SizedBox(
                  height: compact ? 62 : 84,
                  child: Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: compact ? 10 : 16,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(compact ? 20 : 28),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x0A292236),
                          blurRadius: 10,
                          offset: Offset(0, 3),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        if (customer != null)
                          CustomerAvatar(
                            customer: customer,
                            size: compact ? 34 : 48,
                          )
                        else
                          CircleAvatar(
                            radius: compact ? 17 : 24,
                            backgroundColor: const Color(0xFFF7F4F8),
                            child: Icon(
                              Icons.person_outline_rounded,
                              size: compact ? 18 : 24,
                              color: _DashboardScreenState._plum,
                            ),
                          ),
                        SizedBox(width: compact ? 8 : 12),
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                customer?.name ?? 'Cliente',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: _DashboardScreenState._ink,
                                  fontSize: compact ? 10 : 14,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              Text(
                                activity.description,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: _DashboardScreenState._muted,
                                  fontSize: compact ? 9 : 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          _activityDate(activity.createdAt),
                          style: TextStyle(
                            color: _DashboardScreenState._muted,
                            fontSize: compact ? 8 : 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
      ],
    );
  }

  String _activityDate(DateTime date) {
    final local = date.toLocal();
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '${local.day}/${local.month} · $hour:$minute';
  }
}

class _ProgressCard extends StatelessWidget {
  const _ProgressCard({
    required this.title,
    required this.value,
    required this.footnote,
    required this.icon,
    required this.compact,
    required this.progress,
  });

  final String title;
  final String value;
  final String footnote;
  final IconData icon;
  final bool compact;
  final double progress;

  @override
  Widget build(BuildContext context) {
    final ratio = progress.isFinite ? progress.clamp(0.0, 1.0) : 0.0;
    return Container(
      padding: EdgeInsets.fromLTRB(
        compact ? 14 : 22,
        compact ? 12 : 20,
        compact ? 14 : 22,
        compact ? 11 : 19,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(compact ? 26 : 40),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: _DashboardScreenState._ink,
                    fontSize: compact ? 10 : 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Text(
                value,
                style: TextStyle(
                  color: _DashboardScreenState._ink,
                  fontSize: compact ? 12 : 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          SizedBox(height: compact ? 8 : 13),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: ratio.toDouble(),
              minHeight: compact ? 5 : 9,
              backgroundColor: const Color(0xFFF5F0E2),
              color: _DashboardScreenState._gold,
            ),
          ),
          SizedBox(height: compact ? 8 : 12),
          Row(
            children: [
              Icon(
                icon,
                size: compact ? 12 : 17,
                color: _DashboardScreenState._muted,
              ),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  footnote,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: _DashboardScreenState._muted,
                    fontSize: compact ? 9 : 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({
    required this.businessName,
    required this.businessMark,
    required this.onSignOut,
    required this.entries,
    required this.selected,
  });

  final String businessName;
  final Uint8List? businessMark;
  final Future<void> Function() onSignOut;
  final List<_NavigationEntry> entries;
  final String selected;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: _DashboardScreenState._plum,
      padding: const EdgeInsets.fromLTRB(18, 28, 14, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: ClipOval(
              child: SizedBox.square(
                dimension: 72,
                child: businessMark == null
                    ? ColoredBox(
                        color: _DashboardScreenState._coral,
                        child: Center(
                          child: Text(
                            businessName.isEmpty
                                ? 'F'
                                : businessName[0].toUpperCase(),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 31,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      )
                    : Image.memory(
                        businessMark!,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => ColoredBox(
                          color: _DashboardScreenState._coral,
                          child: Center(
                            child: Text(
                              businessName.isEmpty
                                  ? 'F'
                                  : businessName[0].toUpperCase(),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 31,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ),
                      ),
              ),
            ),
          ),
          const SizedBox(height: 26),
          for (final entry in entries)
            _SidebarItem(entry: entry, selected: entry.title == selected),
          const Spacer(),
          _SidebarItem(
            entry: _NavigationEntry(
              title: 'Cerrar sesión',
              icon: Icons.logout_rounded,
              onSignOut: onSignOut,
            ),
            selected: false,
          ),
        ],
      ),
    );
  }
}

class _NotificationBadge extends StatelessWidget {
  const _NotificationBadge({required this.count, this.compact = false});

  final int count;
  final bool compact;

  @override
  Widget build(BuildContext context) => Container(
    constraints: BoxConstraints(minWidth: compact ? 18 : 21),
    height: compact ? 18 : 21,
    padding: const EdgeInsets.symmetric(horizontal: 5),
    alignment: Alignment.center,
    decoration: const BoxDecoration(
      color: _DashboardScreenState._coral,
      shape: BoxShape.rectangle,
      borderRadius: BorderRadius.all(Radius.circular(99)),
    ),
    child: Text(
      count > 99 ? '99+' : '$count',
      style: TextStyle(
        color: Colors.white,
        fontSize: compact ? 10 : 11,
        fontWeight: FontWeight.w800,
        height: 1,
      ),
    ),
  );
}

class _NavigationEntry {
  const _NavigationEntry({
    required this.title,
    required this.icon,
    this.onPressed,
    this.onSignOut,
    this.badgeCount = 0,
  });

  final String title;
  final IconData icon;
  final ValueChanged<Rect>? onPressed;
  final Future<void> Function()? onSignOut;
  final int badgeCount;
}

class _SidebarItem extends StatefulWidget {
  const _SidebarItem({required this.entry, required this.selected});

  final _NavigationEntry entry;
  final bool selected;

  @override
  State<_SidebarItem> createState() => _SidebarItemState();
}

class _SidebarItemState extends State<_SidebarItem> {
  bool _busy = false;

  Future<void> _activate() async {
    final signOut = widget.entry.onSignOut;
    if (signOut != null) {
      if (_busy) return;
      setState(() => _busy = true);
      await signOut();
      if (mounted) setState(() => _busy = false);
      return;
    }
    final callback = widget.entry.onPressed;
    if (callback == null) return;
    final box = context.findRenderObject()! as RenderBox;
    callback(box.localToGlobal(Offset.zero) & box.size);
  }

  @override
  Widget build(BuildContext context) {
    final selected = widget.selected;
    final color = selected ? _DashboardScreenState._gold : Colors.white;
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Material(
        color: selected
            ? Colors.white.withValues(alpha: .1)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(26),
        child: InkWell(
          borderRadius: BorderRadius.circular(26),
          onTap: _activate,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
            child: Row(
              children: [
                Icon(widget.entry.icon, size: 20, color: color),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    widget.entry.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: color,
                      fontSize: 14,
                      fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                    ),
                  ),
                ),
                if (widget.entry.badgeCount > 0) ...[
                  const SizedBox(width: 8),
                  _NotificationBadge(count: widget.entry.badgeCount),
                ],
                if (_busy)
                  const SizedBox.square(
                    dimension: 13,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.5,
                      color: Colors.white,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CompactNavigation extends StatelessWidget {
  const _CompactNavigation({required this.entries, required this.selected});

  final List<_NavigationEntry> entries;
  final String selected;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Accesos',
          style: TextStyle(
            color: _DashboardScreenState._ink,
            fontSize: 17,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final entry in entries)
              _CompactNavChip(entry: entry, selected: entry.title == selected),
          ],
        ),
      ],
    );
  }
}

class _CompactNavChip extends StatelessWidget {
  const _CompactNavChip({required this.entry, required this.selected});

  final _NavigationEntry entry;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Builder(
      builder: (chipContext) => ActionChip(
        avatar: Icon(
          entry.icon,
          size: 16,
          color: selected ? Colors.white : _DashboardScreenState._plum,
        ),
        labelStyle: TextStyle(
          color: selected ? Colors.white : _DashboardScreenState._ink,
          fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
        ),
        backgroundColor: selected ? _DashboardScreenState._plum : Colors.white,
        side: BorderSide(
          color: selected
              ? _DashboardScreenState._plum
              : const Color(0xFFE8E6E9),
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        label: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(entry.title),
            if (entry.badgeCount > 0) ...[
              const SizedBox(width: 6),
              _NotificationBadge(count: entry.badgeCount, compact: true),
            ],
          ],
        ),
        onPressed: () {
          final box = chipContext.findRenderObject()! as RenderBox;
          entry.onPressed?.call(box.localToGlobal(Offset.zero) & box.size);
        },
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
    final start = (index * .08).clamp(0.0, .48);
    final animation = CurvedAnimation(
      parent: controller,
      curve: Interval(start, 1, curve: Curves.easeOutCubic),
    );
    return FadeTransition(
      opacity: animation,
      child: SlideTransition(
        position: Tween(
          begin: const Offset(0, .04),
          end: Offset.zero,
        ).animate(animation),
        child: child,
      ),
    );
  }
}
