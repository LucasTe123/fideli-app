import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image/image.dart' as image_lib;
import 'package:image_picker/image_picker.dart';

import '../models/app_data.dart';
import '../services/cloud_store.dart';
import '../services/wallet_service.dart';
import '../state/app_scope.dart';
import '../theme/fideli_theme.dart';
import '../widgets/common.dart';
import 'wallet_image_crop_screen.dart';

class BusinessScreen extends StatefulWidget {
  const BusinessScreen({super.key});

  @override
  State<BusinessScreen> createState() => _BusinessScreenState();
}

class _BusinessScreenState extends State<BusinessScreen> {
  late final TextEditingController _name;
  late final TextEditingController _category;
  bool _loaded = false;
  bool _uploadingIcon = false;
  bool _savingDetails = false;
  Uint8List? _iconBytes;
  late List<BusinessLocation> _locations;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loaded) return;
    final business = AppScope.of(context).data.business;
    _name = TextEditingController(text: business.name);
    _category = TextEditingController(text: business.category);
    _locations = business.locations
        .map((item) => BusinessLocation.fromJson(item.toJson()))
        .toList();
    _loaded = true;
    _loadIcon(business.walletIconPath);
  }

  Future<void> _loadIcon(String folder) async {
    final bytes = await CloudStore.instance?.downloadWalletIcon(folder);
    if (mounted && bytes != null) setState(() => _iconBytes = bytes);
  }

  Future<void> _pickWalletIcon() async {
    if (_uploadingIcon || _savingDetails) return;
    final cloud = CloudStore.instance;
    if (cloud == null) {
      showMessage(context, 'El servicio todavía no está disponible');
      return;
    }
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 1600,
      imageQuality: 100,
    );
    if (picked == null || !mounted) return;
    try {
      final sourceBytes = await picked.readAsBytes();
      if (!mounted) return;
      final decoded = image_lib.decodeImage(sourceBytes);
      if (decoded == null) throw const FormatException('Imagen no válida');
      final oriented = image_lib.bakeOrientation(decoded);
      final crop = await Navigator.of(context).push<WalletCropResult>(
        MaterialPageRoute(
          builder: (_) => WalletImageCropScreen(
            image: Uint8List.fromList(image_lib.encodePng(oriented, level: 4)),
            title: 'Ajustar icono',
            aspectRatio: 1,
            oneXWidth: 29,
            oneXHeight: 29,
            twoXWidth: 87,
            twoXHeight: 87,
            resolution: '1024 × 1024 px',
            compactGuide: true,
          ),
        ),
      );
      if (!mounted || crop == null) return;
      setState(() => _uploadingIcon = true);
      final preview = crop.twoX;
      final previewImage = image_lib.decodeImage(preview)!;
      final icon2x = image_lib.encodePng(
        image_lib.copyResize(previewImage, width: 58, height: 58),
        level: 6,
      );
      setState(() => _iconBytes = preview);
      final previousFolder = AppScope.of(context).data.business.walletIconPath;
      final folder = await cloud.uploadWalletIcon(
        icon: crop.oneX,
        icon2x: icon2x,
        icon3x: preview,
      );
      if (!mounted) return;
      final state = AppScope.of(context);
      state.data.business.walletIconPath = folder;
      await state.commit();
      final result = await WalletService().refreshBusinessPasses(
        state.data.business,
      );
      if (result.ok && previousFolder.isNotEmpty && previousFolder != folder) {
        unawaited(cloud.deleteWalletIconFolder(previousFolder));
      }
      if (!mounted) return;
      showMessage(context, result.ok ? 'Cambios aplicados' : result.message);
    } catch (_) {
      if (mounted) showMessage(context, 'No se pudo guardar el icono');
    } finally {
      if (mounted) setState(() => _uploadingIcon = false);
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _category.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_uploadingIcon || _savingDetails) return;
    setState(() => _savingDetails = true);
    final state = AppScope.of(context);
    try {
      state.data.business
        ..name = _name.text.trim()
        ..category = _category.text.trim()
        ..locations = _locations
            .take(10)
            .map((item) => BusinessLocation.fromJson(item.toJson()))
            .toList();
      await state.commitAndSync();
      await WalletService().refreshBusinessPasses(state.data.business);
      if (mounted) showMessage(context, 'Cambios aplicados');
    } finally {
      if (mounted) setState(() => _savingDetails = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 1050) {
          return PageBody(children: _editorChildren(includePreview: true));
        }
        return Padding(
          padding: const EdgeInsets.fromLTRB(28, 22, 28, 28),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: _BusinessPanel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Vista previa',
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -.4,
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Los cambios se muestran aquí mientras editas.',
                        style: TextStyle(color: FideliTheme.muted),
                      ),
                      const SizedBox(height: 22),
                      Expanded(
                        child: Align(
                          alignment: Alignment.topCenter,
                          child: _NotificationPreview(
                            businessName: _name.text.trim(),
                            iconBytes: _iconBytes,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 24),
              Expanded(
                child: ListView(
                  padding: EdgeInsets.zero,
                  children: _editorChildren(includePreview: false),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  List<Widget> _editorChildren({required bool includePreview}) => [
    _iconEditor(),
    if (_uploadingIcon) ...[
      const SizedBox(height: 8),
      const LinearProgressIndicator(minHeight: 2),
    ],
    if (includePreview) ...[
      const SizedBox(height: 18),
      _NotificationPreview(
        businessName: _name.text.trim(),
        iconBytes: _iconBytes,
      ),
    ],
    const SizedBox(height: 18),
    _detailsEditor(),
    const SizedBox(height: 18),
    _locationsEditor(),
    const SizedBox(height: 30),
  ];

  Widget _iconEditor() => _BusinessPanel(
    child: Row(
      children: [
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 320),
          switchInCurve: Curves.easeOutBack,
          child: Container(
            key: ValueKey(_iconBytes?.length ?? 0),
            width: 88,
            height: 88,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
            ),
            child: _iconBytes == null
                ? const Icon(
                    Icons.storefront_rounded,
                    size: 34,
                    color: FideliTheme.ink,
                  )
                : Image.memory(
                    _iconBytes!,
                    fit: BoxFit.cover,
                    filterQuality: FilterQuality.high,
                  ),
          ),
        ),
        const SizedBox(width: 18),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Icono del local',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -.3,
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                height: 42,
                child: FilledButton(
                  onPressed: _uploadingIcon || _savingDetails
                      ? null
                      : _pickWalletIcon,
                  style: FilledButton.styleFrom(
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(horizontal: 18),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(15),
                    ),
                  ),
                  child: Text(
                    _uploadingIcon ? 'Guardando…' : 'Cambiar',
                    style: const TextStyle(
                      fontFamily: 'Poppins',
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _detailsEditor() => _BusinessPanel(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Datos del negocio',
          style: TextStyle(
            fontFamily: 'Poppins',
            fontSize: 17,
            fontWeight: FontWeight.w700,
            letterSpacing: -.3,
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _name,
          onChanged: (_) => setState(() {}),
          decoration: _fieldDecoration('Nombre'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _category,
          decoration: _fieldDecoration('Categoría'),
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          height: 54,
          child: FilledButton(
            onPressed: _uploadingIcon || _savingDetails ? null : _save,
            style: FilledButton.styleFrom(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
            ),
            child: Text(
              _savingDetails ? 'Guardando…' : 'Guardar cambios',
              style: const TextStyle(
                fontFamily: 'Poppins',
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ],
    ),
  );

  Widget _locationsEditor() => _BusinessPanel(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'Ubicaciones',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -.3,
                ),
              ),
            ),
            if (_locations.length < 10)
              IconButton.filledTonal(
                tooltip: 'Agregar ubicación',
                onPressed: () => _editLocation(),
                icon: const Icon(Icons.add_location_alt_rounded),
              ),
          ],
        ),
        if (_locations.isEmpty) ...[
          const SizedBox(height: 10),
          const Text(
            'Agrega el local para que Wallet muestre la tarjeta cuando el cliente esté cerca.',
            style: TextStyle(color: Color(0xFF756E6C)),
          ),
        ],
        for (var index = 0; index < _locations.length; index++) ...[
          const SizedBox(height: 10),
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 4),
            leading: const CircleAvatar(
              backgroundColor: Color(0x149E483F),
              child: Icon(Icons.location_on_rounded, color: FideliTheme.ink),
            ),
            title: Text(
              _locations[index].name.isEmpty
                  ? 'Local ${index + 1}'
                  : _locations[index].name,
            ),
            subtitle: Text(
              _locations[index].address.isEmpty
                  ? '${_locations[index].latitude.toStringAsFixed(5)}, ${_locations[index].longitude.toStringAsFixed(5)}'
                  : _locations[index].address,
            ),
            onTap: () => _editLocation(index: index),
            trailing: IconButton(
              tooltip: 'Eliminar ubicación',
              onPressed: () => setState(() => _locations.removeAt(index)),
              icon: const Icon(Icons.delete_outline_rounded),
            ),
          ),
        ],
      ],
    ),
  );

  InputDecoration _fieldDecoration(String label) => InputDecoration(
    labelText: label,
    filled: true,
    fillColor: Colors.white,
    contentPadding: const EdgeInsets.symmetric(horizontal: 17, vertical: 17),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(17),
      borderSide: BorderSide.none,
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(17),
      borderSide: const BorderSide(color: Color(0x10000000)),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(17),
      borderSide: const BorderSide(color: FideliTheme.ink, width: 1.4),
    ),
  );

  Future<void> _editLocation({int? index}) async {
    final existing = index == null ? null : _locations[index];
    final name = TextEditingController(text: existing?.name ?? 'Local');
    final address = TextEditingController(text: existing?.address ?? '');
    final latitude = TextEditingController(
      text: existing == null ? '' : existing.latitude.toString(),
    );
    final longitude = TextEditingController(
      text: existing == null ? '' : existing.longitude.toString(),
    );
    final radius = TextEditingController(
      text: (existing?.radiusMeters ?? 180).toString(),
    );
    final message = TextEditingController(
      text:
          existing?.message ??
          'Estás cerca. Abre tu tarjeta para usarla en el local.',
    );
    var locating = false;
    final result = await showDialog<BusinessLocation>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(index == null ? 'Nueva ubicación' : 'Editar ubicación'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: name,
                  decoration: _fieldDecoration('Nombre del local'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: address,
                  decoration: _fieldDecoration('Dirección'),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: latitude,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                          signed: true,
                        ),
                        decoration: _fieldDecoration('Latitud'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: longitude,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                          signed: true,
                        ),
                        decoration: _fieldDecoration('Longitud'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: locating
                      ? null
                      : () async {
                          setDialogState(() => locating = true);
                          try {
                            if (!await Geolocator.isLocationServiceEnabled()) {
                              throw StateError(
                                'Activa la ubicación del dispositivo',
                              );
                            }
                            var permission = await Geolocator.checkPermission();
                            if (permission == LocationPermission.denied) {
                              permission = await Geolocator.requestPermission();
                            }
                            if (permission == LocationPermission.denied ||
                                permission ==
                                    LocationPermission.deniedForever) {
                              throw StateError('Permiso de ubicación denegado');
                            }
                            final position =
                                await Geolocator.getCurrentPosition(
                                  locationSettings: const LocationSettings(
                                    accuracy: LocationAccuracy.high,
                                  ),
                                );
                            latitude.text = position.latitude.toStringAsFixed(
                              7,
                            );
                            longitude.text = position.longitude.toStringAsFixed(
                              7,
                            );
                          } catch (error) {
                            if (dialogContext.mounted) {
                              showMessage(
                                dialogContext,
                                error.toString().replaceFirst(
                                  'Bad state: ',
                                  '',
                                ),
                              );
                            }
                          } finally {
                            if (dialogContext.mounted) {
                              setDialogState(() => locating = false);
                            }
                          }
                        },
                  icon: locating
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.my_location_rounded),
                  label: const Text('Usar mi ubicación actual'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: radius,
                  keyboardType: TextInputType.number,
                  decoration: _fieldDecoration('Radio en metros'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: message,
                  maxLength: 120,
                  decoration: _fieldDecoration('Mensaje de cercanía'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () {
                final lat = double.tryParse(latitude.text.trim());
                final lng = double.tryParse(longitude.text.trim());
                if (lat == null ||
                    lng == null ||
                    lat < -90 ||
                    lat > 90 ||
                    lng < -180 ||
                    lng > 180) {
                  showMessage(dialogContext, 'Revisa la latitud y longitud');
                  return;
                }
                Navigator.pop(
                  dialogContext,
                  BusinessLocation(
                    id: existing?.id ?? newId('location'),
                    name: name.text.trim(),
                    address: address.text.trim(),
                    latitude: lat,
                    longitude: lng,
                    radiusMeters: (int.tryParse(radius.text.trim()) ?? 180)
                        .clamp(50, 5000)
                        .toInt(),
                    message: message.text.trim(),
                  ),
                );
              },
              child: const Text('Guardar'),
            ),
          ],
        ),
      ),
    );
    name.dispose();
    address.dispose();
    latitude.dispose();
    longitude.dispose();
    radius.dispose();
    message.dispose();
    if (result == null || !mounted) return;
    setState(() {
      if (index == null) {
        _locations.add(result);
      } else {
        _locations[index] = result;
      }
    });
  }
}

class _BusinessPanel extends StatelessWidget {
  const _BusinessPanel({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: FideliTheme.line),
      ),
      child: child,
    );
  }
}

class _NotificationPreview extends StatelessWidget {
  const _NotificationPreview({required this.businessName, this.iconBytes});

  final String businessName;
  final Uint8List? iconBytes;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: AspectRatio(
        aspectRatio: 1616 / 973,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            return Stack(
              fit: StackFit.expand,
              children: [
                Image.asset(
                  'assets/images/business/notification_preview_template.jpg',
                  fit: BoxFit.cover,
                  filterQuality: FilterQuality.high,
                ),
                Positioned(
                  left: width * .057,
                  top: width * .140,
                  width: width * .114,
                  height: width * .114,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(width * .022),
                    child: ColoredBox(
                      color: Colors.white,
                      child: iconBytes == null
                          ? const Icon(Icons.storefront_rounded)
                          : Image.memory(
                              iconBytes!,
                              fit: BoxFit.cover,
                              filterQuality: FilterQuality.high,
                            ),
                    ),
                  ),
                ),
                Positioned(
                  left: width * .188,
                  right: width * .18,
                  top: width * .136,
                  child: Text(
                    businessName.isEmpty ? 'Tu negocio' : businessName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white,
                      fontFamily: 'Poppins',
                      fontSize: width * .043,
                      fontWeight: FontWeight.w600,
                      shadows: const [
                        Shadow(color: Color(0x55000000), blurRadius: 8),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
