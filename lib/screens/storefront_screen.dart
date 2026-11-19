import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' show ImageFilter;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import '../widgets/store_image_drop.dart';
import '../state/app_scope.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show RealtimeChannel;
import 'package:url_launcher/url_launcher.dart';
import '../config/supabase_config.dart';
import '../services/cloud_store.dart';
import '../services/store_image.dart';

class StorefrontScreen extends StatelessWidget {
  const StorefrontScreen({super.key});
  @override
  Widget build(BuildContext context) => Theme(
    data: Theme.of(context).copyWith(
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xffed5264),
        primary: const Color(0xffed5264),
        onPrimary: Colors.white,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: const StadiumBorder(),
          backgroundColor: const Color(0xffed5264),
          foregroundColor: Colors.white,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          shape: const StadiumBorder(),
          foregroundColor: const Color(0xffed5264),
        ),
      ),
      scaffoldBackgroundColor: Colors.white,
      dialogTheme: DialogThemeData(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xfff5f4f7),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: Color(0xff171225)),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: const Color(0xff171225)),
      ),
      cardTheme: CardThemeData(
        color: const Color(0xfff5f4f7),
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      ),
    ),
    child: const _StorefrontContent(),
  );
}

class _StorefrontContent extends StatefulWidget {
  const _StorefrontContent();
  @override
  State<_StorefrontContent> createState() => _StorefrontScreenState();
}

class _StorefrontScreenState extends State<_StorefrontContent>
    with WidgetsBindingObserver {
  final _cloud = CloudStore.instance;
  List<Map<String, dynamic>> _products = [];
  List<Map<String, dynamic>> _orders = [];
  Map<String, dynamic> _settings = {};
  Uint8List? _localLogo;
  bool _logoRequested = false;
  bool _loading = true;
  String? _error;
  String? _ordersError;
  Timer? _ordersTimer;
  RealtimeChannel? _ordersChannel;
  bool _refreshingOrders = false;
  String? _selectedOrderId;
  bool _savingOrder = false;
  String? _orderActionError;
  final _orderChanges = ValueNotifier<int>(0);
  final Set<String> _announcedOrders = {};
  bool _orderDialogOpen = false;

  void _ordersChanged() {
    _orderChanges.value++;
    if (!mounted || _orderDialogOpen) return;
    final pending = _queueOrders.where((o) => o['status'] == 'nuevo').toList();
    final fresh = pending.where(
      (o) => !_announcedOrders.contains(o['id'].toString()),
    );
    if (fresh.isEmpty) return;
    final id = fresh.first['id'].toString();
    _announcedOrders.addAll(pending.map((o) => o['id'].toString()));
    _orderDialogOpen = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _showOrderDialog(id, reserved: true);
      } else {
        _orderDialogOpen = false;
      }
    });
  }

  List<Map<String, dynamic>> get _queueOrders => [..._orders]
    ..sort((a, b) {
      final date = (a['created_at'] ?? '').toString().compareTo(
        (b['created_at'] ?? '').toString(),
      );
      return date != 0
          ? date
          : a['id'].toString().compareTo(b['id'].toString());
    });

  Future<void> _showOrderDialog(String id, {bool reserved = false}) async {
    if (!mounted || (_orderDialogOpen && !reserved)) return;
    _orderDialogOpen = true;
    _selectedOrderId = id;
    _orderActionError = null;
    _announcedOrders.add(id);
    try {
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        barrierColor: Colors.black.withValues(alpha: .28),
        builder: (dialogContext) => BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 7, sigmaY: 7),
          child: Dialog(
            elevation: 24,
            insetPadding: const EdgeInsets.symmetric(
              horizontal: 20,
              vertical: 24,
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: 620,
                maxHeight: MediaQuery.sizeOf(dialogContext).height * .86,
              ),
              child: ValueListenableBuilder<int>(
                valueListenable: _orderChanges,
                builder: (_, value, child) {
                  final order = _orders
                      .where((o) => o['id'] == _selectedOrderId)
                      .firstOrNull;
                  return SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(20, 12, 12, 0),
                          child: Row(
                            children: [
                              const Expanded(
                                child: Text(
                                  'Detalle del pedido',
                                  style: TextStyle(fontWeight: FontWeight.w700),
                                ),
                              ),
                              IconButton(
                                tooltip: 'Cerrar',
                                onPressed: _savingOrder
                                    ? null
                                    : () => Navigator.pop(dialogContext),
                                icon: const Icon(Icons.close),
                              ),
                            ],
                          ),
                        ),
                        if (order != null)
                          _orderCard(order)
                        else
                          const Padding(
                            padding: EdgeInsets.all(24),
                            child: Text('Este pedido ya no está disponible.'),
                          ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      );
    } finally {
      _orderDialogOpen = false;
      // Closing acknowledges the visible queue without repeatedly interrupting work.
      _announcedOrders.addAll(_orders.map((o) => o['id'].toString()));
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_logoRequested) {
      _logoRequested = true;
      final folder = AppScope.of(context).data.business.walletIconPath;
      _cloud?.downloadWalletIcon(folder).then((bytes) {
        if (mounted && bytes != null) setState(() => _localLogo = bytes);
      });
    }
  }

  Future<void> _refreshOrders() async {
    if (_refreshingOrders || _cloud == null) return;
    _refreshingOrders = true;
    try {
      final orders = await _cloud.loadStoreOrders();
      if (mounted) {
        setState(() {
          _orders = orders;
          _ordersError = null;
        });
        _ordersChanged();
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _ordersError =
              'No pudimos actualizar los pedidos. Vuelve a intentarlo.',
        );
      }
    } finally {
      _refreshingOrders = false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refreshOrders();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ordersTimer?.cancel();
    if (_ordersChannel != null) {
      _cloud?.stopWatchingStoreOrders(_ordersChannel!);
    }
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
    _ordersChannel = _cloud?.watchStoreOrders(_refreshOrders);
    _ordersTimer = Timer.periodic(
      const Duration(seconds: 15),
      (_) => _refreshOrders(),
    );
  }

  Future<void> _load() async {
    try {
      final results = await Future.wait<dynamic>([
        _cloud!.loadStoreProducts(),
        _cloud.loadStoreOrders(),
        _cloud.loadStoreSettings(),
      ]);
      if (!mounted) return;
      setState(() {
        _products = List<Map<String, dynamic>>.from(results[0]);
        _orders = List<Map<String, dynamic>>.from(results[1]);
        _settings = Map<String, dynamic>.from(results[2]);
        _loading = false;
        _error = null;
      });
      _ordersChanged();
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error =
              CloudStore.initializationError ??
              'No se pudo cargar la tienda. Comprueba tu conexión y vuelve a intentarlo.';
        });
      }
    }
  }

  String get _slug => _cloud?.publicSlug ?? '';
  String get _link {
    final cloud = _cloud;
    if (cloud == null || _slug.isEmpty) return '';
    return SupabaseConfig.publicStoreUriForBusiness(
      cloud.businessId,
      publicSlug: _slug,
    ).toString();
  }

  Future<void> _copyStorefrontLink() async {
    try {
      await Clipboard.setData(ClipboardData(text: _link));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Enlace copiado. ¡Compártelo con tus clientes!'),
          ),
        );
      }
    } catch (_) {
      _showError('No pudimos copiar el enlace. Vuelve a intentarlo.');
    }
  }

  void _showError(String message) {
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Future<void> _customize() async {
    Map<String, dynamic> settings;
    try {
      settings = await _cloud!.loadStoreSettings();
    } catch (_) {
      _showError('No pudimos cargar la personalización. Vuelve a intentarlo.');
      return;
    }
    if (!mounted) return;
    final color = TextEditingController(
      text: settings['button_color']?.toString() ?? '#171225',
    );
    Uint8List? logo;
    var busy = false;
    String? error;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, refresh) => AlertDialog(
          title: const Text('Personalizar tienda'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (logo == null &&
                    (settings['logo_url']?.toString().isNotEmpty ?? false))
                  ClipRRect(
                    borderRadius: BorderRadius.circular(22),
                    child: Image.network(
                      settings['logo_url'].toString(),
                      width: 96,
                      height: 96,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) =>
                          const Icon(Icons.storefront, size: 64),
                    ),
                  ),
                if (logo != null)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: Image.memory(
                      logo!,
                      width: 88,
                      height: 88,
                      fit: BoxFit.cover,
                    ),
                  ),
                OutlinedButton.icon(
                  onPressed: busy
                      ? null
                      : () async {
                          try {
                            final image = await pickStoreImage();
                            if (context.mounted) {
                              refresh(() => logo = image ?? logo);
                            }
                          } catch (_) {
                            if (context.mounted) {
                              refresh(
                                () => error =
                                    'No pudimos preparar la imagen. Prueba con otra foto.',
                              );
                            }
                          }
                        },
                  icon: const Icon(Icons.add_photo_alternate_outlined),
                  label: const Text('Subir icono de la tienda'),
                ),
                TextField(
                  controller: color,
                  decoration: const InputDecoration(
                    labelText: 'Color de botones',
                    hintText: '#171225',
                  ),
                ),
                Wrap(
                  spacing: 10,
                  children:
                      ['#171225', '#24755B', '#3457C0', '#6B47A5', '#9B621F']
                          .map(
                            (hex) => IconButton(
                              tooltip: hex,
                              onPressed: () => refresh(() => color.text = hex),
                              icon: Icon(
                                Icons.circle,
                                color: Color(
                                  int.parse('FF${hex.substring(1)}', radix: 16),
                                ),
                              ),
                            ),
                          )
                          .toList(),
                ),
                const Text(
                  'Fotos optimizadas automáticamente. Máximo 350 KB por imagen.',
                ),
                if (error != null) Text(error!),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: busy ? null : () => Navigator.pop(dialogContext),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: busy
                  ? null
                  : () async {
                      if (!RegExp(
                        r'^#[0-9a-fA-F]{6}$',
                      ).hasMatch(color.text.trim())) {
                        refresh(
                          () => error =
                              'Escribe un color válido, por ejemplo #24755B.',
                        );
                        return;
                      }
                      refresh(() {
                        busy = true;
                        error = null;
                      });
                      try {
                        final url = logo == null
                            ? settings['logo_url']?.toString() ?? ''
                            : await _cloud.uploadStoreImage('logo', logo!);
                        await _cloud.saveStoreSettings({
                          'logo_url': url,
                          'button_color': color.text.trim(),
                        });
                        if (dialogContext.mounted) Navigator.pop(dialogContext);
                      } catch (_) {
                        if (context.mounted) {
                          refresh(() {
                            busy = false;
                            error =
                                'No pudimos guardar los cambios. Vuelve a intentarlo.';
                          });
                        }
                      }
                    },
              child: Text(busy ? 'Guardando…' : 'Guardar'),
            ),
          ],
        ),
      ),
    );
    color.dispose();
    await _load();
  }

  Future<String?> _createStoreCategory() async {
    final input = TextEditingController();
    final value = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Nueva categoría'),
        content: TextField(
          controller: input,
          autofocus: true,
          maxLength: 40,
          decoration: const InputDecoration(labelText: 'Nombre'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, input.text.trim()),
            child: const Text('Crear'),
          ),
        ],
      ),
    );
    input.dispose();
    if (value == null || value.isEmpty) return null;
    final existing = <String>{
      'General',
      ...((_settings['categories'] as List?) ?? const []).map(
        (e) => e.toString(),
      ),
    };
    final match = existing
        .where((e) => e.toLowerCase() == value.toLowerCase())
        .firstOrNull;
    if (match != null) return match;
    final updated = {...existing, value}.toList()
      ..sort(
        (a, b) => a == 'General'
            ? -1
            : b == 'General'
            ? 1
            : a.toLowerCase().compareTo(b.toLowerCase()),
      );
    try {
      await _cloud!.saveStoreSettings({'categories': updated});
      if (mounted) {
        setState(() => _settings = {..._settings, 'categories': updated});
      }
      return value;
    } catch (_) {
      _showError('No pudimos guardar la categoría. Vuelve a intentarlo.');
      return null;
    }
  }

  Future<void> _editProduct([Map<String, dynamic>? current]) async {
    final name = TextEditingController(
      text: current?['name']?.toString() ?? '',
    );
    final description = TextEditingController(
      text: current?['description']?.toString() ?? '',
    );
    final category = TextEditingController(
      text: current?['category']?.toString() ?? 'General',
    );
    final imageUrl = TextEditingController(
      text: current?['image_url']?.toString() ?? '',
    );
    final price = TextEditingController(
      text: current?['price']?.toString() ?? '',
    );
    final categories =
        <String>{
          'General',
          ...((_settings['categories'] as List?) ?? const []).map(
            (e) => e.toString(),
          ),
          ..._products.map((p) => p['category']?.toString() ?? ''),
        }.where((e) => e.trim().isNotEmpty).toList()..sort(
          (a, b) => a == 'General'
              ? -1
              : b == 'General'
              ? 1
              : a.toLowerCase().compareTo(b.toLowerCase()),
        );
    if (!categories.contains(category.text)) category.text = 'General';
    Uint8List? productImage;
    var picking = false;

    final productId =
        current?['id']?.toString() ??
        'prod-${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}';
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, refresh) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(30),
          ),
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 20,
            vertical: 24,
          ),
          title: Text(
            current == null ? 'Nuevo producto' : 'Editar producto',
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
          ),
          content: SizedBox(
            width: 440,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: name,
                    autofocus: true,
                    decoration: const InputDecoration(labelText: 'Nombre'),
                  ),
                  TextField(
                    controller: description,
                    decoration: const InputDecoration(labelText: 'Descripción'),
                  ),
                  Container(
                    margin: const EdgeInsets.only(top: 12),
                    padding: const EdgeInsets.fromLTRB(14, 8, 8, 4),
                    decoration: BoxDecoration(
                      color: const Color(0xfff5f4f7),
                      borderRadius: BorderRadius.circular(22),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            initialValue: category.text,
                            decoration: const InputDecoration(
                              labelText: 'Categoría',
                              border: InputBorder.none,
                              filled: false,
                            ),
                            borderRadius: BorderRadius.circular(20),
                            items: categories
                                .map(
                                  (value) => DropdownMenuItem(
                                    value: value,
                                    child: Text(value),
                                  ),
                                )
                                .toList(),
                            onChanged: (value) {
                              if (value != null) {
                                refresh(() => category.text = value);
                              }
                            },
                          ),
                        ),
                        IconButton.filledTonal(
                          tooltip: 'Crear categoría',
                          onPressed: () async {
                            final created = await _createStoreCategory();
                            if (created != null && context.mounted) {
                              refresh(() {
                                categories.removeWhere(
                                  (item) =>
                                      item.toLowerCase() ==
                                      created.toLowerCase(),
                                );
                                categories.add(created);
                                categories.sort(
                                  (a, b) => a == 'General'
                                      ? -1
                                      : b == 'General'
                                      ? 1
                                      : a.toLowerCase().compareTo(
                                          b.toLowerCase(),
                                        ),
                                );
                                category.text = created;
                              });
                            }
                          },
                          icon: const Icon(Icons.add),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: StoreImageDropArea(
                      enabled: !picking,
                      onError: _showError,
                      onFile: (file) async {
                        refresh(() => picking = true);
                        try {
                          final bytes = await prepareStoreImage(file);
                          if (context.mounted) {
                            refresh(() => productImage = bytes);
                          }
                        } catch (_) {
                          _showError(
                            'No pudimos preparar la foto. Elige una imagen de menos de 10 MB.',
                          );
                        } finally {
                          if (context.mounted) refresh(() => picking = false);
                        }
                      },
                    ),
                  ),
                  if (productImage != null)
                    Image.memory(productImage!, height: 100, fit: BoxFit.cover),
                  OutlinedButton.icon(
                    onPressed: picking
                        ? null
                        : () async {
                            refresh(() => picking = true);
                            try {
                              final image = await pickStoreImage();
                              if (context.mounted) {
                                refresh(
                                  () => productImage = image ?? productImage,
                                );
                              }
                            } catch (_) {
                              _showError(
                                'No pudimos preparar la foto. Prueba con otra imagen.',
                              );
                            } finally {
                              if (context.mounted) {
                                refresh(() => picking = false);
                              }
                            }
                          },
                    icon: const Icon(Icons.add_photo_alternate_outlined),
                    label: Text(picking ? 'Preparando foto…' : 'Elegir foto'),
                  ),
                  TextField(
                    controller: imageUrl,
                    keyboardType: TextInputType.url,
                    decoration: const InputDecoration(
                      labelText: 'Enlace de la foto (opcional)',
                    ),
                  ),
                  TextField(
                    controller: price,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(labelText: 'Precio (Bs)'),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: picking ? null : () => Navigator.pop(context, true),
              child: const Text('Guardar'),
            ),
          ],
        ),
      ),
    );
    if (saved != true) return;
    final parsedPrice = double.tryParse(price.text.replaceAll(',', '.'));
    if (name.text.trim().isEmpty || parsedPrice == null || parsedPrice < 0) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Revisa el nombre y el precio.')),
        );
      }
      return;
    }
    try {
      if (productImage != null) {
        imageUrl.text = await _cloud!.uploadStoreImage(
          productId,
          productImage!,
        );
      }
      await _cloud!.saveStoreProduct({
        'id': productId,
        'name': name.text.trim(),
        'description': description.text.trim(),
        'category': category.text.trim().isEmpty
            ? 'General'
            : category.text.trim(),
        'image_url': imageUrl.text.trim(),
        'price': parsedPrice,
        'active': true,
      });
      await _load();
    } catch (_) {
      _showError('No pudimos guardar el producto. Vuelve a intentarlo.');
    }
  }

  Future<void> _setPhone() async {
    final phone = TextEditingController();
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('WhatsApp del local'),
        content: TextField(
          controller: phone,
          keyboardType: TextInputType.phone,
          decoration: const InputDecoration(
            hintText: '59170000000',
            labelText: 'Incluye el código de país',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
    if (result == true) {
      await _cloud!.updateStoreContact(phone.text);
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () {
                  setState(() => _loading = true);
                  _load();
                },
                icon: const Icon(Icons.refresh),
                label: const Text('Reintentar'),
              ),
            ],
          ),
        ),
      );
    }
    final name = AppScope.of(context).data.business.name;
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide =
            constraints.maxWidth >= 980 && constraints.maxHeight >= 620;
        final identity = _identityPanel(name);
        final links = _linksPanel();
        final products = _productPanel(wide);
        final orders = _orderPanel(wide);
        final header = Padding(
          padding: const EdgeInsets.only(bottom: 20),
          child: Row(
            children: [
              const Expanded(
                child: Text(
                  'Mi tienda',
                  style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
        );
        if (wide) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
            child: Column(
              children: [
                header,
                IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(child: identity),
                      const SizedBox(width: 24),
                      Expanded(child: links),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(child: products),
                      const SizedBox(width: 24),
                      Expanded(child: orders),
                    ],
                  ),
                ),
              ],
            ),
          );
        }
        return RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              header,
              identity,
              const SizedBox(height: 16),
              links,
              const SizedBox(height: 24),
              products,
              const SizedBox(height: 24),
              orders,
            ],
          ),
        );
      },
    );
  }

  Widget _surface(Widget child) => Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(28),
      border: Border.all(color: const Color(0xffeeedf2)),
    ),
    child: child,
  );

  Widget _identityPanel(String name) {
    final logo = _settings['logo_url']?.toString() ?? '';
    final fallback = Container(
      width: 100,
      height: 100,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: const Color(0xfff5f4f7),
        borderRadius: BorderRadius.circular(26),
      ),
      child: const Icon(
        Icons.storefront_outlined,
        size: 42,
        color: Color(0xff171225),
      ),
    );
    return _surface(
      Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(26),
            child: logo.isEmpty
                ? (_localLogo == null
                      ? fallback
                      : Image.memory(
                          _localLogo!,
                          width: 100,
                          height: 100,
                          fit: BoxFit.cover,
                        ))
                : Image.network(
                    logo,
                    width: 100,
                    height: 100,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => fallback,
                  ),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name.isEmpty ? 'Tu local' : name,
                  style: const TextStyle(
                    fontSize: 23,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Icono y apariencia de tu tienda',
                  style: TextStyle(color: Color(0xff77737e)),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: _customize,
                  icon: const Icon(Icons.palette_outlined, size: 18),
                  label: const Text('Personalizar tienda'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _linksPanel() => _surface(
    Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text(
          'Enlace de tu catálogo',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        SelectableText(
          _link.isEmpty ? 'Configura la dirección pública de tu local.' : _link,
          style: const TextStyle(color: Color(0xff77737e)),
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: _setPhone,
              icon: const Icon(Icons.phone_outlined, size: 18),
              label: const Text('WhatsApp'),
            ),
            OutlinedButton.icon(
              onPressed: _link.isEmpty
                  ? null
                  : () => launchUrl(
                      Uri.parse(_link),
                      mode: LaunchMode.externalApplication,
                    ),
              icon: const Icon(Icons.open_in_new, size: 18),
              label: const Text('Ver tienda'),
            ),
            FilledButton.icon(
              onPressed: _link.isEmpty ? null : _copyStorefrontLink,
              icon: const Icon(Icons.chat_outlined, size: 18),
              label: const Text('Compartir'),
            ),
          ],
        ),
      ],
    ),
  );

  Widget _section({
    required String title,
    required Widget action,
    required List<Widget> children,
    required bool scroll,
  }) {
    final list = ListView.separated(
      primary: false,
      shrinkWrap: !scroll,
      physics: scroll
          ? const AlwaysScrollableScrollPhysics()
          : const NeverScrollableScrollPhysics(),
      itemCount: children.length,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (_, i) => children[i],
    );
    return _surface(
      Column(
        mainAxisSize: scroll ? MainAxisSize.max : MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 21,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              action,
            ],
          ),
          const SizedBox(height: 16),
          if (scroll) Expanded(child: list) else list,
        ],
      ),
    );
  }

  Widget _productPanel(bool scroll) => _section(
    title: 'Productos (${_products.length})',
    scroll: scroll,
    action: FilledButton.icon(
      onPressed: _editProduct,
      icon: const Icon(Icons.add),
      label: const Text('Agregar producto'),
    ),
    children: _products.isEmpty
        ? [
            const Padding(
              padding: EdgeInsets.all(20),
              child: Text('Agrega tu primer producto para empezar.'),
            ),
          ]
        : _products.map((p) {
            final image = p['image_url']?.toString() ?? '';
            final placeholder = Container(
              width: 72,
              height: 72,
              color: const Color(0xffeeedf2),
              child: const Icon(Icons.image_outlined),
            );
            return Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xfff5f4f7),
                borderRadius: BorderRadius.circular(24),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: image.isEmpty
                        ? placeholder
                        : Image.network(
                            image,
                            width: 72,
                            height: 72,
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) => placeholder,
                          ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          p['name'].toString(),
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                          ),
                        ),
                        if ((p['description']?.toString() ?? '').isNotEmpty)
                          Text(
                            p['description'].toString(),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: Color(0xff77737e)),
                          ),
                        const SizedBox(height: 6),
                        Text(
                          'Bs ${num.tryParse(p['price'].toString())?.toStringAsFixed(2) ?? p['price']}',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        Wrap(
                          children: [
                            TextButton.icon(
                              onPressed: () => _editProduct(p),
                              icon: const Icon(Icons.edit_outlined, size: 17),
                              label: const Text('Editar'),
                            ),
                            IconButton(
                              tooltip: 'Eliminar producto',
                              onPressed: () async {
                                try {
                                  await _cloud!.deleteStoreProduct(
                                    p['id'].toString(),
                                  );
                                  await _load();
                                } catch (_) {
                                  _showError(
                                    'No pudimos eliminar el producto. Vuelve a intentarlo.',
                                  );
                                }
                              },
                              icon: const Icon(Icons.delete_outline, size: 19),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
  );

  String _orderDate(dynamic value) {
    final date = DateTime.tryParse(value?.toString() ?? '')?.toLocal();
    if (date == null) return '';
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(date.day)}/${two(date.month)} · ${two(date.hour)}:${two(date.minute)}';
  }

  Future<void> _setOrderStatus(
    Map<String, dynamic> order,
    String status,
  ) async {
    if (_savingOrder) return;
    setState(() {
      _savingOrder = true;
      _orderActionError = null;
    });
    _orderChanges.value++;
    try {
      await _cloud!.updateStoreOrderStatus(order['id'].toString(), status);
      if (mounted) setState(() => order['status'] = status);
      await _refreshOrders();
    } catch (_) {
      if (mounted) {
        _orderActionError =
            'No pudimos guardar el estado. Vuelve a intentarlo con el mismo botón.';
      }
    } finally {
      if (mounted) {
        setState(() => _savingOrder = false);
        _orderChanges.value++;
      }
    }
  }

  Widget _orderCard(Map<String, dynamic> order) {
    final status = order['status']?.toString() ?? 'nuevo';
    final statusName =
        {
          'nuevo': 'Pedido nuevo',
          'confirmado': 'Pedido confirmado',
          'cancelado': 'Pedido rechazado',
          'rechazado': 'Pedido rechazado',
          'entregado': 'Pedido entregado',
        }[status] ??
        status;
    final next = _queueOrders
        .where((o) => o['status'] == 'nuevo')
        .where((o) => o['id'] != _selectedOrderId)
        .firstOrNull;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xfff5f4f7),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_orderActionError != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                _orderActionError!,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          Text(
            statusName,
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 20),
          ),
          const SizedBox(height: 12),
          Text(
            order['customer_name']?.toString() ?? '',
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
          ),
          Text('${order['id']} · ${_orderDate(order['created_at'])}'),
          if ((order['customer_phone'] ?? '').toString().isNotEmpty)
            Text(order['customer_phone'].toString()),
          const SizedBox(height: 16),
          ...(order['items'] as List? ?? []).map((item) {
            String image = (item['image_url'] ?? '').toString();
            if (image.isEmpty) {
              for (final product in _products) {
                if (product['id'] == item['id']) {
                  image = (product['image_url'] ?? '').toString();
                }
              }
            }
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: image.isEmpty
                        ? const SizedBox(
                            width: 68,
                            height: 68,
                            child: Icon(Icons.restaurant_outlined),
                          )
                        : Image.network(
                            image,
                            width: 68,
                            height: 68,
                            fit: BoxFit.cover,
                            errorBuilder: (_, error, stack) => const SizedBox(
                              width: 68,
                              height: 68,
                              child: Icon(Icons.image_outlined),
                            ),
                          ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      '${item['quantity']} × ${item['name']}',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  Text(
                    'Bs ${num.tryParse(item['line_total'].toString())?.toStringAsFixed(2) ?? item['line_total']}',
                  ),
                ],
              ),
            );
          }),
          const Text(
            'Comentarios',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          Text(
            (order['customer_comment'] ?? '').toString().trim().isEmpty
                ? 'Sin comentarios'
                : order['customer_comment'].toString(),
          ),
          const SizedBox(height: 16),
          Text(
            'Total: Bs ${num.tryParse(order['total'].toString())?.toStringAsFixed(2) ?? order['total']}',
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 20),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              FilledButton.icon(
                onPressed: _savingOrder || status != 'nuevo'
                    ? null
                    : () => _setOrderStatus(order, 'confirmado'),
                icon: const Icon(Icons.check),
                label: const Text('Confirmar'),
              ),
              OutlinedButton.icon(
                onPressed: _savingOrder || status != 'nuevo'
                    ? null
                    : () => _setOrderStatus(order, 'cancelado'),
                icon: const Icon(Icons.close),
                label: const Text('Rechazar'),
              ),
              if (status == 'confirmado')
                OutlinedButton(
                  onPressed: _savingOrder
                      ? null
                      : () => _setOrderStatus(order, 'entregado'),
                  child: const Text('Marcar entregado'),
                ),
              FilledButton.tonalIcon(
                onPressed: _savingOrder || next == null
                    ? null
                    : () {
                        _selectedOrderId = next['id'].toString();
                        _orderActionError = null;
                        _announcedOrders.add(_selectedOrderId!);
                        _orderChanges.value++;
                      },
                icon: const Icon(Icons.arrow_forward),
                label: const Text('Siguiente'),
              ),
            ],
          ),
          if (_savingOrder)
            const Padding(
              padding: EdgeInsets.only(top: 12),
              child: LinearProgressIndicator(),
            ),
        ],
      ),
    );
  }

  Widget _orderPanel(bool scroll) => _section(
    title: 'Historial de pedidos (${_orders.length})',
    scroll: scroll,
    action: IconButton(
      onPressed: _refreshOrders,
      tooltip: 'Actualizar pedidos',
      icon: const Icon(Icons.refresh),
    ),
    children: [
      if (_ordersError != null)
        Row(
          children: [
            Expanded(child: Text(_ordersError!)),
            TextButton(
              onPressed: _refreshOrders,
              child: const Text('Reintentar'),
            ),
          ],
        ),
      if (_orders.isEmpty)
        const Padding(
          padding: EdgeInsets.all(20),
          child: Text('Aquí aparecerá el historial de tus pedidos.'),
        ),
      ..._queueOrders.reversed.map(
        (o) => ListTile(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          tileColor: const Color(0xfff5f4f7),
          leading: const CircleAvatar(
            backgroundColor: Colors.white,
            child: Icon(Icons.receipt_long_outlined, color: Color(0xff171225)),
          ),
          title: Text(
            '${o['customer_name']}',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          subtitle: Text(
            '${o['id']} · ${_orderDate(o['created_at'])}\n${{'nuevo': 'Nuevo', 'confirmado': 'Confirmado', 'cancelado': 'Rechazado', 'rechazado': 'Rechazado', 'entregado': 'Entregado'}[o['status']] ?? o['status']} · Bs ${num.tryParse(o['total'].toString())?.toStringAsFixed(2) ?? o['total']}',
          ),
          isThreeLine: true,
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _showOrderDialog(o['id'].toString()),
        ),
      ),
    ],
  );
}

class PublicStorefrontScreen extends StatefulWidget {
  const PublicStorefrontScreen({super.key, required this.slug});
  final String slug;
  @override
  State<PublicStorefrontScreen> createState() => _PublicStorefrontScreenState();
}

class _PublicStorefrontScreenState extends State<PublicStorefrontScreen> {
  Map<String, dynamic>? _store;
  final Map<String, int> _cart = {};
  bool _loading = true;
  String? _error;
  bool _submitting = false;
  Map<String, dynamic>? _receipt;
  String? _requestId;
  String? _selectedCategory;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!CloudStore.configured || CloudStore.instance == null) {
      if (mounted) {
        setState(() {
          _error = 'No se pudo conectar con la tienda. Revisa tu conexión.';
          _loading = false;
        });
      }
      return;
    }
    try {
      final s = await CloudStore.instance!.loadPublicStore(widget.slug);
      if (mounted) {
        setState(() {
          _store = s;
          _loading = false;
          _error = s == null
              ? 'No encontramos esta tienda. Revisa el enlace.'
              : null;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _error =
              'No se pudo abrir el catálogo. Comprueba tu conexión e inténtalo otra vez.';
          _loading = false;
        });
      }
    }
  }

  Future<void> _checkout() async {
    final name = TextEditingController();
    final phone = TextEditingController();
    final comment = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Tus datos'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: name,
              decoration: const InputDecoration(labelText: 'Nombre'),
            ),
            TextField(
              controller: phone,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: 'Teléfono'),
            ),
            TextField(
              controller: comment,
              maxLength: 1000,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Comentarios (opcional)',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Volver'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Confirmar'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    if (name.text.trim().length < 2) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Escribe tu nombre para continuar.')),
        );
      }
      return;
    }
    setState(() => _submitting = true);
    try {
      final order = await CloudStore.instance!.createPublicStoreOrder(
        requestId: _requestId ??= newStoreOrderRequestId(),
        slug: widget.slug,
        name: name.text,
        phone: phone.text,
        comment: comment.text,
        items: _cart.entries
            .map((e) => {'id': e.key, 'quantity': e.value})
            .toList(),
      );
      final lines = (order['items'] as List)
          .map((e) => '${e['quantity']} × ${e['name']} — Bs ${e['line_total']}')
          .join('\n');
      final message =
          'Pedido ${order['id']} · ${order['business_name']}\n$lines\nTotal verificado: Bs ${order['total']}\nCliente: ${name.text}\nComentarios: ${order['customer_comment'] ?? ''}';
      final digits = order['whatsapp_phone'].toString().replaceAll(
        RegExp(r'\D'),
        '',
      );
      final uri = Uri.parse(
        'https://wa.me/$digits',
      ).replace(queryParameters: {'text': message});
      if (mounted) setState(() => _receipt = order);
      if (digits.length >= 8) {
        try {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        } catch (_) {
          /* Receipt remains available. */
        }
      }
    } catch (error) {
      final message = error is StateError
          ? error.message
          : 'No se pudo registrar el pedido. Comprueba tu conexión e inténtalo otra vez.';
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(message)));
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_error != null || _store == null) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _error ?? 'Catálogo no encontrado.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () {
                    setState(() {
                      _loading = true;
                      _error = null;
                    });
                    _load();
                  },
                  icon: const Icon(Icons.refresh),
                  label: const Text('Reintentar'),
                ),
              ],
            ),
          ),
        ),
      );
    }
    if (_receipt != null) {
      final receipt = _receipt!;
      return Scaffold(
        appBar: AppBar(title: const Text('Comprobante de pedido')),
        body: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text(
              receipt['business_name'].toString(),
              style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
            ),
            Text('Pedido ${receipt['id']}'),
            Text('Cliente: ${receipt['customer_name'] ?? ''}'),
            if ((receipt['customer_comment'] ?? '').toString().isNotEmpty)
              Text('Comentarios: ${receipt['customer_comment']}'),
            Text(receipt['created_at']?.toString() ?? ''),
            const Divider(height: 32),
            ...(receipt['items'] as List).map(
              (item) => ListTile(
                title: Text('${item['quantity']} × ${item['name']}'),
                subtitle: Text('Bs ${item['price']} por unidad'),
                trailing: Text('Bs ${item['line_total']}'),
              ),
            ),
            const Divider(),
            Text(
              'Total Bs ${receipt['total']}',
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: () => setState(() {
                _receipt = null;
                _requestId = null;
                _cart.clear();
              }),
              child: const Text('Ver catálogo'),
            ),
          ],
        ),
      );
    }
    final products = (_store!['products'] as List? ?? const []).cast<Map>();
    final categories =
        products
            .map(
              (product) =>
                  (product['category']?.toString().trim().isNotEmpty ?? false)
                  ? product['category'].toString().trim()
                  : 'General',
            )
            .toSet()
            .toList()
          ..sort();
    final visibleProducts = _selectedCategory == null
        ? products
        : products.where((product) {
            final category = product['category']?.toString().trim();
            return (category == null || category.isEmpty
                    ? 'General'
                    : category) ==
                _selectedCategory;
          }).toList();
    final total = products.fold<double>(
      0,
      (sum, p) =>
          sum +
          ((double.tryParse(p['price'].toString()) ?? 0) *
              (_cart[p['id'].toString()] ?? 0)),
    );
    return Scaffold(
      appBar: AppBar(title: Text(_store!['name'].toString())),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (categories.isNotEmpty)
            SizedBox(
              height: 48,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  ChoiceChip(
                    label: const Text('Todo'),
                    selected: _selectedCategory == null,
                    onSelected: (_) => setState(() => _selectedCategory = null),
                  ),
                  const SizedBox(width: 8),
                  for (final category in categories) ...[
                    ChoiceChip(
                      label: Text(category),
                      selected: _selectedCategory == category,
                      onSelected: (_) =>
                          setState(() => _selectedCategory = category),
                    ),
                    const SizedBox(width: 8),
                  ],
                ],
              ),
            ),
          for (final p in visibleProducts)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Row(
                  children: [
                    _productImage(p['image_url']?.toString() ?? ''),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            p['name'].toString(),
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          if ((p['description']?.toString() ?? '').isNotEmpty)
                            Text(
                              p['description'].toString(),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          Text(
                            'Bs ${p['price']}',
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    if ((_cart[p['id'].toString()] ?? 0) > 0)
                      Text(
                        '${_cart[p['id'].toString()]}  ',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    OutlinedButton.icon(
                      onPressed: (_cart[p['id'].toString()] ?? 0) >= 99
                          ? null
                          : () => setState(() {
                              final id = p['id'].toString();
                              _cart[id] = (_cart[id] ?? 0) + 1;
                            }),
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('Agregar'),
                    ),
                    if ((_cart[p['id'].toString()] ?? 0) > 0)
                      IconButton(
                        tooltip: 'Quitar uno',
                        onPressed: () => setState(() {
                          final id = p['id'].toString();
                          _cart[id] = ((_cart[id] ?? 0) - 1).clamp(0, 99);
                        }),
                        icon: const Icon(Icons.remove_circle_outline),
                      ),
                  ],
                ),
              ),
            ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton(
            onPressed: total > 0 && !_submitting ? _checkout : null,
            child: Text(
              _submitting
                  ? 'Registrando pedido…'
                  : 'Continuar · Bs ${total.toStringAsFixed(2)}',
            ),
          ),
        ),
      ),
    );
  }

  Widget _productImage(String rawUrl) {
    final uri = Uri.tryParse(rawUrl);
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) {
      return Container(
        width: 76,
        height: 76,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Icon(Icons.fastfood_outlined),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Image.network(
        uri.toString(),
        width: 76,
        height: 76,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => Container(
          width: 76,
          height: 76,
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          child: const Icon(Icons.fastfood_outlined),
        ),
      ),
    );
  }
}
