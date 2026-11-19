import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image/image.dart' as image_lib;
import 'package:image_picker/image_picker.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../models/app_data.dart';
import '../services/cloud_store.dart';
import '../services/wallet_service.dart';
import '../state/app_scope.dart';
import '../theme/fideli_theme.dart';
import '../widgets/common.dart';
import 'wallet_image_crop_screen.dart';

class WalletStudioScreen extends StatefulWidget {
  const WalletStudioScreen({super.key});

  @override
  State<WalletStudioScreen> createState() => _WalletStudioScreenState();
}

class _WalletStudioScreenState extends State<WalletStudioScreen>
    with SingleTickerProviderStateMixin {
  // =========================================================
  // COLOR FIJO DE LA INTERFAZ
  // =========================================================
  //
  // ESTE COLOR YA NO CAMBIA CUANDO CAMBIA LA TARJETA.
  //
  // Solo la tarjeta cambia de color.
  // Botones, iconos, badges, etc. usan siempre este color.
  // =========================================================

  static const Color _uiAccent = FideliTheme.ink;

  // =========================================================
  // ICONOS DE LOS SELLOS
  // =========================================================

  static const _stampIcons = {
    'coffee': 'Café',
    'pizza': 'Pizza',
    'haircut': 'Peluquería',
    'star': 'Estrella',
    'heart': 'Corazón',
    'paw': 'Mascotas',
    'check': 'Clásico',
    'gift': 'Regalo',
    'hamburger': 'Hamburguesa',
    'latte': 'Taza de café',
    'coffee_beans': 'Granos de café',
    'ice_cream': 'Helado',
    'hair_scissors': 'Tijeras',
    'salon_chair': 'Silla de peluquería',
    'pet_collar': 'Collar para mascota',
    'pet_bone': 'Hueso',
    'pet_bowl': 'Plato para mascota',
  };

  // =========================================================
  // ESTADO
  // =========================================================

  String _selectedDesign = 'stamps';

  bool _editing = false;
  bool _saving = false;
  final OverlayPortalController _editOverlayController =
      OverlayPortalController();
  Timer? _dismissEditOverlayTimer;
  final GlobalKey _previewCardKey = GlobalKey();
  Rect? _editSourceRect;

  String? _draftColor;
  String? _draftStampIcon;
  String? _draftWalletLayout;

  Uint8List? _draftBackground;
  Uint8List? _draftBackground2x;

  bool _removeDraftBackground = false;

  final Map<String, Uint8List> _backgrounds = {};
  final Set<String> _loadingBackgrounds = {};
  Uint8List? _walletLogo;
  String _loadedWalletLogoPath = '';
  bool _uploadingLogo = false;

  // =========================================================
  // COLOR PERSONALIZADO
  // =========================================================

  HSVColor _customColor = HSVColor.fromColor(const Color(0xFF9E483F));

  // =========================================================
  // ANIMACIÓN DE ENTRADA
  // =========================================================

  late final AnimationController _pageAnimation;

  @override
  void initState() {
    super.initState();

    _pageAnimation = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..forward();
  }

  @override
  void dispose() {
    _dismissEditOverlayTimer?.cancel();
    _pageAnimation.dispose();
    super.dispose();
  }

  Future<void> _loadWalletLogo(String path) async {
    if (path.isEmpty || path == _loadedWalletLogoPath) return;
    _loadedWalletLogoPath = path;
    final bytes = await CloudStore.instance?.downloadWalletLogo(path);
    if (mounted && bytes != null) setState(() => _walletLogo = bytes);
  }

  Future<void> _pickWalletLogo() async {
    if (_uploadingLogo || _saving) return;
    final cloud = CloudStore.instance;
    if (cloud == null) {
      showMessage(context, 'El servicio todavía no está disponible');
      return;
    }
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 2400,
      imageQuality: 100,
    );
    if (picked == null || !mounted) return;
    final sourceBytes = await picked.readAsBytes();
    if (!mounted) return;
    final decoded = image_lib.decodeImage(sourceBytes);
    if (decoded == null) {
      showMessage(context, 'No se pudo preparar el logo');
      return;
    }
    final source = image_lib.bakeOrientation(decoded);
    final crop = await Navigator.of(context).push<WalletCropResult>(
      MaterialPageRoute(
        builder: (_) => WalletImageCropScreen(
          image: Uint8List.fromList(image_lib.encodePng(source, level: 4)),
          title: 'Ajustar logo',
          aspectRatio: 16 / 5,
          oneXWidth: 160,
          oneXHeight: 50,
          twoXWidth: 480,
          twoXHeight: 150,
          resolution: '480 × 150 px',
          compactGuide: true,
        ),
      ),
    );
    if (!mounted || crop == null) return;
    setState(() => _uploadingLogo = true);
    try {
      final decodedLogo = image_lib.decodeImage(crop.twoX)!;
      final logo2x = image_lib.encodePng(
        image_lib.copyResize(decodedLogo, width: 320, height: 100),
        level: 6,
      );
      final state = AppScope.of(context);
      final previousFolder = state.data.business.walletLogoPath;
      final folder = await cloud.uploadWalletLogo(
        logo: crop.oneX,
        logo2x: logo2x,
        logo3x: crop.twoX,
      );
      if (!mounted) return;
      setState(() {
        _walletLogo = crop.twoX;
        _loadedWalletLogoPath = folder;
      });
      state.data.business.walletLogoPath = folder;
      await state.commit();
      final result = await WalletService().refreshBusinessPasses(
        state.data.business,
      );
      if (result.ok && previousFolder.isNotEmpty && previousFolder != folder) {
        unawaited(cloud.deleteWalletLogoFolder(previousFolder));
      }
      if (mounted) {
        showMessage(context, result.ok ? 'Cambios aplicados' : result.message);
      }
    } catch (_) {
      if (mounted) showMessage(context, 'No se pudo guardar el logo');
    } finally {
      if (mounted) setState(() => _uploadingLogo = false);
    }
  }

  // =========================================================
  // ANIMACIÓN DE APARICIÓN
  // =========================================================

  Widget _reveal(int index, Widget child) {
    final start = (index * 0.08).clamp(0.0, 0.65).toDouble();
    final end = (start + 0.38).clamp(0.0, 1.0).toDouble();

    final animation = CurvedAnimation(
      parent: _pageAnimation,
      curve: Interval(start, end, curve: Curves.easeOutCubic),
    );

    return FadeTransition(
      opacity: animation,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.055),
          end: Offset.zero,
        ).animate(animation),
        child: child,
      ),
    );
  }

  // =========================================================
  // CARGAR FONDO
  // =========================================================

  Future<void> _loadBackground(
    String designType,
    WalletCardTemplate template,
  ) async {
    if (template.backgroundImagePath.isEmpty ||
        _backgrounds.containsKey(designType) ||
        !_loadingBackgrounds.add(designType)) {
      return;
    }

    final bytes = await CloudStore.instance?.downloadCardBackground(
      template.backgroundImagePath,
    );

    _loadingBackgrounds.remove(designType);

    if (mounted && bytes != null) {
      setState(() => _backgrounds[designType] = bytes);
    }
  }

  // =========================================================
  // GUARDAR DISEÑO
  // =========================================================

  Future<void> _saveDesign(List<LoyaltyProgram> programs) async {
    final state = AppScope.of(context);

    setState(() => _saving = true);

    await state.commitAndSync();

    if (programs.isEmpty) {
      if (!mounted) return;
      setState(() => _saving = false);
      showMessage(context, 'Cambios aplicados');
      return;
    }

    final results = await Future.wait(
      programs.map(
        (program) => WalletService().syncProgram(
          state.data.business,
          program,
          notifyWallet: false,
        ),
      ),
    );

    final failed = results.where((item) => !item.ok).firstOrNull;

    final result =
        failed ??
        await WalletService().refreshBusinessPasses(state.data.business);

    if (!mounted) return;

    setState(() => _saving = false);

    showMessage(context, result.ok ? 'Cambios aplicados' : result.message);
  }

  // =========================================================
  // EMPEZAR A EDITAR
  // =========================================================

  void _startEditing(
    String currentColor,
    Uint8List? currentBackground,
    String currentStampIcon,
    String currentWalletLayout,
  ) {
    final parsedColor = _color(currentColor);
    _dismissEditOverlayTimer?.cancel();
    final previewBox =
        _previewCardKey.currentContext?.findRenderObject() as RenderBox?;
    _editSourceRect = previewBox != null && previewBox.hasSize
        ? previewBox.localToGlobal(Offset.zero) & previewBox.size
        : null;

    setState(() {
      _editing = true;

      _draftColor = currentColor;
      _draftStampIcon = currentStampIcon;
      _draftWalletLayout = currentWalletLayout;

      _draftBackground = currentBackground;
      _draftBackground2x = null;

      _removeDraftBackground = false;

      _customColor = HSVColor.fromColor(parsedColor);
    });
    _editOverlayController.show();
  }

  // =========================================================
  // CANCELAR
  // =========================================================

  void _cancelEditing() {
    setState(() {
      _editing = false;

      _draftColor = null;
      _draftStampIcon = null;
      _draftWalletLayout = null;

      _draftBackground = null;
      _draftBackground2x = null;

      _removeDraftBackground = false;
    });
    _dismissEditOverlayTimer?.cancel();
    _dismissEditOverlayTimer = Timer(const Duration(milliseconds: 520), () {
      _editOverlayController.hide();
      if (mounted) {
        setState(() {
          _dismissEditOverlayTimer = null;
          _editSourceRect = null;
        });
      }
    });
  }

  // =========================================================
  // ELEGIR FOTO
  // =========================================================

  Future<void> _pickBackground(String walletLayout) async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 2000,
      imageQuality: 100,
    );

    if (picked == null || !mounted) return;

    try {
      final decoded = image_lib.decodeImage(await picked.readAsBytes());

      if (decoded == null) {
        throw const FormatException('Imagen no válida');
      }

      final source = image_lib.bakeOrientation(decoded);

      if (!mounted) return;

      final result = await Navigator.of(context).push<WalletCropResult>(
        MaterialPageRoute(
          builder: (_) => WalletImageCropScreen(
            image: Uint8List.fromList(image_lib.encodePng(source, level: 4)),
            title: walletLayout == 'classic'
                ? 'Ajustar franja'
                : 'Ajustar imagen completa',
            aspectRatio: walletLayout == 'classic' ? 375 / 123 : 345 / 505,
            oneXWidth: walletLayout == 'classic' ? 375 : 345,
            oneXHeight: walletLayout == 'classic' ? 123 : 505,
            twoXWidth: walletLayout == 'classic' ? 750 : 690,
            twoXHeight: walletLayout == 'classic' ? 246 : 1010,
            resolution: walletLayout == 'classic'
                ? '1125 × 369 px'
                : '1035 × 1515 px',
            compactGuide: true,
          ),
        ),
      );

      if (!mounted || result == null) return;

      setState(() {
        _draftBackground = result.oneX;
        _draftBackground2x = result.twoX;

        _removeDraftBackground = false;
      });
    } catch (_) {
      if (!mounted) return;

      showMessage(context, 'No se pudo preparar la foto');
    }
  }

  // =========================================================
  // APLICAR CAMBIOS
  // =========================================================

  Future<void> _applyChanges(
    WalletCardTemplate template,
    List<LoyaltyProgram> programs,
  ) async {
    if (_saving) return;

    final cloud = CloudStore.instance;

    if (cloud == null) {
      showMessage(context, 'El servicio todavía no está disponible');

      return;
    }

    setState(() => _saving = true);

    try {
      String? uploadedFolder;

      if (_draftBackground2x != null) {
        uploadedFolder = await cloud.uploadCardBackground(
          programId: 'template-$_selectedDesign',
          image: _draftBackground!,
          image2x: _draftBackground2x!,
        );
      }

      template.colorHex = _draftColor ?? template.colorHex;
      template.stampIcon = _draftStampIcon ?? template.stampIcon;
      template.walletLayout = _draftWalletLayout ?? template.walletLayout;
      if (uploadedFolder != null) {
        template.backgroundImagePath = uploadedFolder;
        _backgrounds[_selectedDesign] = _draftBackground!;
      } else if (_removeDraftBackground) {
        template.backgroundImagePath = '';
        _backgrounds.remove(_selectedDesign);
      }

      for (final program in programs) {
        program
          ..colorHex = template.colorHex
          ..backgroundImagePath = template.backgroundImagePath
          ..stampIcon = template.stampIcon
          ..walletLayout = template.walletLayout;
      }

      await _saveDesign(programs);

      if (!mounted) return;

      _cancelEditing();
    } catch (_) {
      if (!mounted) return;

      setState(() => _saving = false);

      showMessage(context, 'No se pudieron aplicar los cambios');
    }
  }

  // =========================================================
  // CONVERTIR COLOR A HEX
  // =========================================================

  String _hexFromColor(Color color) {
    final value = color.toARGB32() & 0xFFFFFF;

    return '#${value.toRadixString(16).padLeft(6, '0').toUpperCase()}';
  }

  // =========================================================
  // BUILD
  // =========================================================

  @override
  Widget build(BuildContext context) {
    final data = AppScope.of(context).data;
    final viewportWidth = MediaQuery.sizeOf(context).width;
    final desktop = viewportWidth >= 900;
    unawaited(_loadWalletLogo(data.business.walletLogoPath));

    // =========================================================
    // FILTRAR SEGÚN EL TIPO ELEGIDO
    // =========================================================

    final programs = data.programs.where((program) {
      switch (_selectedDesign) {
        case 'gift':
          return program.cardKind == 'Tarjeta de regalo';

        case 'membership':
          return program.type == ProgramType.membership ||
              program.cardKind == 'Membresía';

        case 'points':
          return program.type == ProgramType.points &&
              program.cardKind != 'Tarjeta de regalo';

        case 'stamps':
        default:
          return program.type == ProgramType.stamps;
      }
    }).toList();

    // =========================================================
    // NOMBRE DE LA PREVISUALIZACIÓN
    // =========================================================

    final previewName = switch (_selectedDesign) {
      'gift' => 'Tarjeta de regalo',
      'membership' => 'Membresía del local',
      'points' => 'Tarjeta de puntos',
      _ => 'Tarjeta de sellos',
    };

    // =========================================================
    // TIPO DE PROGRAMA DE LA PREVISUALIZACIÓN
    // =========================================================

    final previewType = switch (_selectedDesign) {
      'gift' => ProgramType.points,
      'membership' => ProgramType.membership,
      'points' => ProgramType.points,
      _ => ProgramType.stamps,
    };

    final template = data.wallet.templateFor(_selectedDesign);
    final selected =
        programs.firstOrNull ??
        LoyaltyProgram(
          id: 'preview-$_selectedDesign',
          name: previewName,
          type: previewType,
          cardKind: switch (_selectedDesign) {
            'gift' => 'Tarjeta de regalo',
            'membership' => 'Membresía',
            _ => 'Fidelización',
          },
          colorHex: template.colorHex,
          backgroundImagePath: template.backgroundImagePath,
          stampIcon: template.stampIcon,
          walletLayout: template.walletLayout,
        );

    _loadBackground(_selectedDesign, template);

    // =========================================================
    // COLOR GUARDADO
    // =========================================================

    final selectedColor = template.colorHex.isEmpty
        ? data.business.colorHex
        : template.colorHex;

    // =========================================================
    // COLOR DE LA TARJETA
    // =========================================================

    final previewColor = _editing
        ? (_draftColor ?? selectedColor)
        : selectedColor;

    // =========================================================
    // FOTO
    // =========================================================

    final savedBackground = _backgrounds[_selectedDesign];

    final previewBackground = _editing
        ? (_removeDraftBackground
              ? null
              : (_draftBackground ?? savedBackground))
        : savedBackground;

    // =========================================================
    // ICONO ACTUAL
    // =========================================================

    final activeStampIcon = _editing
        ? (_draftStampIcon ?? template.stampIcon)
        : template.stampIcon;

    // =========================================================
    // LAYOUT ACTUAL
    // =========================================================

    final activeWalletLayout = _editing
        ? (_draftWalletLayout ?? template.walletLayout)
        : template.walletLayout;

    final desktopEditing = desktop && _editing;
    const desktopEditorWidth = 560.0;
    final studioWidth = desktopEditing
        ? viewportWidth.clamp(0.0, 1180.0).toDouble()
        : desktop
        ? viewportWidth.clamp(0.0, 760.0).toDouble()
        : viewportWidth;

    Widget rightPanel(Widget child) {
      if (!desktopEditing) return child;
      return Align(
        alignment: Alignment.topRight,
        child: SizedBox(width: desktopEditorWidth, child: child),
      );
    }

    final editorControls = AnimatedSwitcher(
      duration: const Duration(milliseconds: 500),

      switchInCurve: Curves.easeOutCubic,

      switchOutCurve: Curves.easeInCubic,

      transitionBuilder: (child, animation) {
        if (desktop) {
          final spring = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutBack,
            reverseCurve: Curves.easeInCubic,
          );
          return FadeTransition(
            opacity: animation,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(.28, 0),
                end: Offset.zero,
              ).animate(spring),
              child: ScaleTransition(
                alignment: Alignment.centerRight,
                scale: Tween<double>(begin: .94, end: 1).animate(spring),
                child: child,
              ),
            ),
          );
        }
        return FadeTransition(
          opacity: animation,
          child: SizeTransition(
            sizeFactor: animation,
            alignment: Alignment.topCenter,
            child: child,
          ),
        );
      },

      child: !_editing
          ? const SizedBox.shrink(key: ValueKey('editor-closed'))
          : Column(
              key: const ValueKey('editor-open'),

              children: [
                const SizedBox(height: 20),

                _StudioCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const _SectionHeader(title: 'Formato de tarjeta'),
                      const SizedBox(height: 16),
                      _WalletLayoutToggle(
                        value: activeWalletLayout,
                        enabled: !_saving,
                        onChanged: (value) {
                          setState(() => _draftWalletLayout = value);
                        },
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 18),

                _StudioCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const _SectionHeader(title: 'Logo superior'),
                      const SizedBox(height: 14),
                      AspectRatio(
                        aspectRatio: 16 / 5,
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(color: const Color(0x18000000)),
                          ),
                          child: _walletLogo == null
                              ? const SizedBox.shrink()
                              : Image.memory(
                                  _walletLogo!,
                                  fit: BoxFit.contain,
                                  filterQuality: FilterQuality.high,
                                ),
                        ),
                      ),
                      const SizedBox(height: 9),
                      const Center(
                        child: Text(
                          '480 × 150 px',
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 12,
                            color: Colors.black54,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: _PrimaryButton(
                          label: _uploadingLogo ? 'Guardando…' : 'Elegir logo',
                          icon: Icons.photo_library_outlined,
                          enabled: !_saving && !_uploadingLogo,
                          onPressed: _pickWalletLogo,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 18),

                if (_selectedDesign == 'stamps') ...[
                  // ===================================
                  // ICONO DE SELLOS
                  // ===================================
                  _StudioCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,

                      children: [
                        const _SectionHeader(title: 'Icono de los sellos'),

                        const SizedBox(height: 20),

                        _StampIconMenu(
                          icons: _stampIcons,
                          value: _draftStampIcon ?? template.stampIcon,
                          enabled: !_saving,
                          onChanged: (value) {
                            setState(() {
                              _draftStampIcon = value;
                            });
                          },
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 18),
                ],

                // =====================================
                // CREAR COLOR PERSONALIZADO
                // =====================================
                _StudioCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,

                    children: [
                      const _SectionHeader(title: 'Color de la tarjeta'),

                      const SizedBox(height: 20),

                      _CustomColorEditor(
                        color: _customColor,

                        onChanged: (newColor) {
                          setState(() {
                            _customColor = newColor;

                            // SOLO CAMBIA
                            // EL COLOR DE LA
                            // TARJETA.

                            _draftColor = _hexFromColor(newColor.toColor());
                          });
                        },
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 18),

                // =====================================
                // FOTO DE FONDO
                // =====================================
                _StudioCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,

                    children: [
                      const _SectionHeader(title: 'Foto de fondo'),

                      const SizedBox(height: 18),

                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 350),

                        child: previewBackground == null
                            ? Container(
                                key: const ValueKey('no-photo'),

                                width: double.infinity,

                                height: 105,

                                decoration: BoxDecoration(
                                  color: Colors.white,

                                  borderRadius: BorderRadius.circular(20),

                                  border: Border.all(
                                    color: const Color(0x0E000000),
                                  ),
                                ),

                                child: const Column(
                                  mainAxisAlignment: MainAxisAlignment.center,

                                  children: [
                                    Icon(
                                      Icons.image_outlined,

                                      color: Colors.black38,

                                      size: 32,
                                    ),

                                    SizedBox(height: 7),

                                    Text(
                                      'Sin imagen de fondo',

                                      style: TextStyle(
                                        fontFamily: 'Poppins',

                                        fontSize: 12,

                                        color: Colors.black45,
                                      ),
                                    ),
                                  ],
                                ),
                              )
                            : ClipRRect(
                                key: const ValueKey('has-photo'),

                                borderRadius: BorderRadius.circular(20),

                                child: SizedBox(
                                  width: double.infinity,

                                  height: 140,

                                  child: Image.memory(
                                    previewBackground,

                                    fit: BoxFit.cover,

                                    filterQuality: FilterQuality.high,
                                  ),
                                ),
                              ),
                      ),

                      const SizedBox(height: 16),

                      SizedBox(
                        width: double.infinity,

                        child: _PrimaryButton(
                          label: previewBackground == null
                              ? 'Elegir foto'
                              : 'Cambiar foto',

                          icon: Icons.photo_library_outlined,

                          enabled: !_saving,

                          onPressed: () => _pickBackground(
                            _draftWalletLayout ?? template.walletLayout,
                          ),
                        ),
                      ),

                      if (previewBackground != null) ...[
                        const SizedBox(height: 10),

                        SizedBox(
                          width: double.infinity,

                          child: OutlinedButton.icon(
                            onPressed: _saving
                                ? null
                                : () {
                                    setState(() {
                                      _draftBackground = null;

                                      _draftBackground2x = null;

                                      _removeDraftBackground = true;
                                    });
                                  },

                            icon: const Icon(Icons.hide_image_outlined),

                            label: const Text(
                              'Quitar foto',

                              style: TextStyle(
                                fontFamily: 'Poppins',

                                fontWeight: FontWeight.w600,
                              ),
                            ),

                            style: OutlinedButton.styleFrom(
                              foregroundColor: const Color(0xFF382725),

                              minimumSize: const Size(double.infinity, 52),

                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(17),
                              ),

                              side: const BorderSide(color: Color(0x18000000)),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),

                const SizedBox(height: 18),

                // =====================================
                // CANCELAR / APLICAR
                // =====================================
                _StudioCard(
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _saving ? null : _cancelEditing,

                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size(double.infinity, 54),

                            foregroundColor: const Color(0xFF382725),

                            side: const BorderSide(color: Color(0x18000000)),

                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(18),
                            ),
                          ),

                          child: const Text(
                            'Cancelar',

                            style: TextStyle(
                              fontFamily: 'Poppins',

                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(width: 12),

                      Expanded(
                        child: _PrimaryButton(
                          label: 'Aplicar',

                          icon: Icons.check_rounded,

                          enabled: !_saving,

                          onPressed: () {
                            _applyChanges(template, programs);
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );

    Widget previewPanel() => _reveal(
      1,
      _StudioCard(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                'Vista previa',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.4,
                ),
              ),
            ),
            const SizedBox(height: 20),
            _WalletLayoutToggle(
              value: activeWalletLayout,
              enabled: !_saving,
              onChanged: (value) {
                if (!_editing) {
                  _startEditing(
                    selectedColor,
                    savedBackground,
                    template.stampIcon,
                    template.walletLayout,
                  );
                }
                setState(() => _draftWalletLayout = value);
              },
            ),
            const SizedBox(height: 20),
            Center(
              child: AnimatedScale(
                duration: const Duration(milliseconds: 450),
                curve: Curves.easeOutBack,
                scale: _editing ? 1.015 : 1,
                child: AnimatedContainer(
                  key: _previewCardKey,
                  duration: const Duration(milliseconds: 450),
                  curve: Curves.easeOutCubic,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(30),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.09),
                        blurRadius: 28,
                        offset: const Offset(0, 14),
                      ),
                    ],
                  ),
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 350),
                    child: SizedBox(
                      key: ValueKey(
                        '$_selectedDesign-'
                        '$previewColor-'
                        '$activeStampIcon-'
                        '$activeWalletLayout-'
                        '${previewBackground != null}',
                      ),
                      width: desktop ? 308 : 350,
                      height: desktop ? 417 : 474,
                      child: FittedBox(
                        fit: BoxFit.contain,
                        child: _PassPreview(
                          businessName: data.business.name,
                          logo: _walletLogo,
                          color: _color(previewColor),
                          program: selected,
                          background: previewBackground,
                          stampIcon: activeStampIcon,
                          walletLayout: activeWalletLayout,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );

    Widget focusedCard(double width, double height) => RepaintBoundary(
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(30),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: .34),
              blurRadius: 42,
              spreadRadius: 2,
              offset: const Offset(0, 24),
            ),
            BoxShadow(
              color: _color(previewColor).withValues(alpha: .22),
              blurRadius: 34,
              spreadRadius: -4,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(30),
          child: SizedBox(
            width: width,
            height: height,
            child: FittedBox(
              fit: BoxFit.contain,
              child: _PassPreview(
                businessName: data.business.name,
                logo: _walletLogo,
                color: _color(previewColor),
                program: selected,
                background: previewBackground,
                stampIcon: activeStampIcon,
                walletLayout: activeWalletLayout,
              ),
            ),
          ),
        ),
      ),
    );

    // =========================================================
    // INTERFAZ
    // =========================================================

    return OverlayPortal(
      controller: _editOverlayController,
      overlayLocation: OverlayChildLocation.rootOverlay,
      overlayChildBuilder: (context) => Positioned.fill(
        child: _WalletEditOverlay(
          key: const ValueKey('wallet-edit-overlay'),
          sourceRect: _editSourceRect,
          closing: !_editing,
          card: focusedCard(360, 488),
          compactCard: focusedCard(190, 258),
          controls: editorControls,
          onDismiss: _saving ? () {} : _cancelEditing,
        ),
      ),
      child: Align(
        alignment: Alignment.topCenter,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 620),
          curve: Curves.easeOutBack,
          // Mantener ambos extremos de la animación en valores finitos evita
          // interpolar entre BoxConstraints acotadas e infinitas al redimensionar.
          width: studioWidth,
          child: Stack(
            children: [
              PageBody(
                maxContentWidth: desktopEditing ? 1180 : 760,
                children: [
                  // =====================================================
                  // SOLO EL SELECTOR
                  // =====================================================
                  rightPanel(
                    _reveal(
                      0,
                      _StudioCard(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          children: [
                            DropdownButtonFormField<String>(
                              initialValue: _selectedDesign,

                              borderRadius: BorderRadius.circular(22),

                              icon: const Icon(
                                Icons.keyboard_arrow_down_rounded,
                              ),

                              decoration: InputDecoration(
                                filled: true,

                                fillColor: Colors.white,

                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 18,
                                  vertical: 17,
                                ),

                                labelText: 'Tipo de tarjeta',

                                labelStyle: const TextStyle(
                                  fontFamily: 'Poppins',
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF5A4845),
                                ),

                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(18),
                                  borderSide: BorderSide.none,
                                ),

                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(18),
                                  borderSide: const BorderSide(
                                    color: Color(0x10000000),
                                  ),
                                ),

                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(18),
                                  borderSide: const BorderSide(
                                    color: _uiAccent,
                                    width: 1.5,
                                  ),
                                ),
                              ),

                              items: const [
                                DropdownMenuItem(
                                  value: 'stamps',
                                  child: Text(
                                    'Tarjeta de sellos',
                                    style: TextStyle(
                                      fontFamily: 'Poppins',
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),

                                DropdownMenuItem(
                                  value: 'points',
                                  child: Text(
                                    'Tarjeta de puntos',
                                    style: TextStyle(
                                      fontFamily: 'Poppins',
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),

                                DropdownMenuItem(
                                  value: 'gift',
                                  child: Text(
                                    'Tarjeta de regalo',
                                    style: TextStyle(
                                      fontFamily: 'Poppins',
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),

                                DropdownMenuItem(
                                  value: 'membership',
                                  child: Text(
                                    'Membresía',
                                    style: TextStyle(
                                      fontFamily: 'Poppins',
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],

                              onChanged: _editing || _saving
                                  ? null
                                  : (value) {
                                      if (value == null) {
                                        return;
                                      }

                                      setState(() {
                                        _selectedDesign = value;
                                      });
                                    },
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 14),

                  // =====================================================
                  // EDITAR / VISTA PREVIA
                  // =====================================================
                  rightPanel(
                    Align(
                      alignment: Alignment.centerRight,
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 320),

                        switchInCurve: Curves.easeOutCubic,

                        switchOutCurve: Curves.easeInCubic,

                        child: _editing
                            ? const _PreviewModeBadge(
                                key: ValueKey('preview-mode'),
                              )
                            : _PrimaryButton(
                                key: const ValueKey('edit-mode'),
                                label: 'Editar',
                                icon: Icons.edit_outlined,

                                enabled: !_saving,

                                onPressed: () {
                                  _startEditing(
                                    selectedColor,
                                    savedBackground,
                                    template.stampIcon,
                                    template.walletLayout,
                                  );
                                },
                              ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 32),

                  // =====================================================
                  // VISTA PREVIA
                  // =====================================================
                  if (!_editing) previewPanel(),

                  // =====================================================
                  // EDICIÓN
                  // =====================================================
                  if (!_editing) rightPanel(editorControls),

                  // =====================================================
                  // GUARDANDO
                  // =====================================================
                  rightPanel(
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 350),

                      child: !_saving
                          ? const SizedBox.shrink()
                          : const Padding(
                              key: ValueKey('saving'),

                              padding: EdgeInsets.only(top: 18),

                              child: _SavingCard(),
                            ),
                    ),
                  ),

                  const SizedBox(height: 30),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // =========================================================
  // HEX -> COLOR
  // =========================================================

  Color _color(String hex) {
    final value = int.tryParse(hex.replaceFirst('#', ''), radix: 16);

    return value == null ? _uiAccent : Color(0xFF000000 | value);
  }
}

// ===========================================================
// CAPA FLOTANTE DE EDICIÓN
// ===========================================================

class _WalletEditOverlay extends StatelessWidget {
  const _WalletEditOverlay({
    super.key,
    required this.sourceRect,
    required this.closing,
    required this.card,
    required this.compactCard,
    required this.controls,
    required this.onDismiss,
  });

  final Rect? sourceRect;
  final bool closing;
  final Widget card;
  final Widget compactCard;
  final Widget controls;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final safe = MediaQuery.paddingOf(context);
        final usable = Rect.fromLTWH(
          safe.left,
          safe.top,
          math.max(0.0, constraints.maxWidth - safe.horizontal),
          math.max(0.0, constraints.maxHeight - safe.vertical),
        );
        final wide = usable.width >= 960;

        late final Rect targetCardRect;
        late final Rect targetControlsRect;
        if (wide) {
          final cardWidth = math.min(390.0, usable.width * .31);
          final cardHeight = cardWidth * 488 / 360;
          final controlsWidth = math.min(720.0, usable.width * .48);
          final gap = math.min(44.0, usable.width * .035);
          final groupWidth = cardWidth + gap + controlsWidth;
          final left = usable.left + (usable.width - groupWidth) / 2;
          final top = usable.top + (usable.height - cardHeight) / 2;
          targetCardRect = Rect.fromLTWH(left, top, cardWidth, cardHeight);
          targetControlsRect = Rect.fromLTWH(
            left + cardWidth + gap,
            usable.top + usable.height * .06,
            controlsWidth,
            usable.height * .88,
          );
        } else {
          final cardWidth = math.min(190.0, usable.width - 32);
          final cardHeight = cardWidth * 488 / 360;
          targetCardRect = Rect.fromLTWH(
            usable.left + (usable.width - cardWidth) / 2,
            usable.top + 10,
            cardWidth,
            cardHeight,
          );
          final controlsTop = targetCardRect.bottom + 14;
          targetControlsRect = Rect.fromLTWH(
            usable.left + 12,
            controlsTop,
            usable.width - 24,
            math.max(100.0, usable.bottom - controlsTop - 10),
          );
        }

        final origin = sourceRect ?? targetCardRect;
        final destination = closing ? origin : targetCardRect;
        return Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onDismiss,
                child: TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: closing ? 0 : .64),
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeOutCubic,
                  builder: (context, opacity, child) =>
                      Opacity(opacity: opacity, child: child),
                  child: const ColoredBox(color: Color(0xFF100C14)),
                ),
              ),
            ),
            TweenAnimationBuilder<Rect>(
              tween: _RectFlightTween(
                begin: closing ? targetCardRect : origin,
                end: destination,
              ),
              duration: const Duration(milliseconds: 500),
              curve: Curves.easeOutBack,
              builder: (context, rect, child) => Positioned.fromRect(
                rect: rect,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {},
                  child: child,
                ),
              ),
              child: wide ? card : compactCard,
            ),
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: closing ? 0 : 1),
              duration: const Duration(milliseconds: 420),
              curve: Curves.easeOutBack,
              builder: (context, progress, child) => Positioned.fromRect(
                rect: targetControlsRect,
                child: Opacity(
                  // easeOutBack overshoots 1 briefly; Opacity only accepts
                  // values in [0, 1], while the slide can keep its spring.
                  opacity: progress.clamp(0.0, 1.0).toDouble(),
                  child: Transform.translate(
                    offset: Offset((1 - progress) * 90, 0),
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () {},
                      child: child,
                    ),
                  ),
                ),
              ),
              child: _floatingControls(controls, wide),
            ),
          ],
        );
      },
    );
  }

  Widget _floatingControls(Widget child, bool wide) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 720),
      decoration: BoxDecoration(
        color: const Color(0xFFF9F7FA),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: Colors.white.withValues(alpha: .8)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: .22),
            blurRadius: 28,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(18, wide ? 8 : 4, 18, 20),
        child: child,
      ),
    );
  }
}

// ===========================================================
// TARJETA ESTILO APPLE
// ===========================================================

class _StudioCard extends StatelessWidget {
  const _StudioCard({
    required this.child,

    this.padding = const EdgeInsets.all(20),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    const radius = 27.0;

    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),

      // Nueve filtros de desenfoque simultáneos obligaban a Chrome a volver a
      // rasterizar toda la pantalla en cada interacción. La superficie conserva
      // el aspecto suave, pero ahora es una capa estática y económica.
      child: Container(
        width: double.infinity,

        padding: padding,

        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.94),

          borderRadius: BorderRadius.circular(radius),

          border: Border.all(color: Colors.white),

          boxShadow: const [
            BoxShadow(
              color: Color(0x09000000),

              blurRadius: 28,

              offset: Offset(0, 10),
            ),
          ],
        ),

        child: child,
      ),
    );
  }
}

// ===========================================================
// CABECERA DE APARTADOS
// ===========================================================

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: const TextStyle(
        fontFamily: 'Poppins',
        fontSize: 16,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.35,
        color: Color(0xFF382725),
      ),
    );
  }
}

// ===========================================================
// BADGE VISTA PREVIA
// ===========================================================

class _PreviewModeBadge extends StatelessWidget {
  const _PreviewModeBadge({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 10),

      decoration: BoxDecoration(
        color: FideliTheme.ink.withValues(alpha: 0.09),

        borderRadius: BorderRadius.circular(22),

        border: Border.all(color: FideliTheme.ink.withValues(alpha: 0.18)),
      ),

      child: const Row(
        mainAxisSize: MainAxisSize.min,

        children: [
          Icon(Icons.visibility_outlined, size: 18, color: FideliTheme.ink),

          SizedBox(width: 8),

          Text(
            'Vista previa',

            style: TextStyle(
              fontFamily: 'Poppins',

              fontSize: 13,

              fontWeight: FontWeight.w600,

              color: Color(0xFF382725),
            ),
          ),
        ],
      ),
    );
  }
}

// ===========================================================
// BOTÓN PRINCIPAL FIJO
// ===========================================================

class _PrimaryButton extends StatelessWidget {
  const _PrimaryButton({
    super.key,

    required this.label,
    required this.icon,
    required this.enabled,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      onPressed: enabled ? onPressed : null,

      icon: Icon(icon, size: 19),

      label: Text(
        label,

        style: const TextStyle(
          fontFamily: 'Poppins',

          fontSize: 13,

          fontWeight: FontWeight.w600,
        ),
      ),

      style: FilledButton.styleFrom(
        // COLOR FIJO.
        // YA NO DEPENDE DE LA TARJETA.
        backgroundColor: FideliTheme.ink,

        foregroundColor: Colors.white,

        disabledBackgroundColor: const Color(0x339E483F),

        minimumSize: const Size(120, 52),

        elevation: 0,

        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(17)),
      ),
    );
  }
}

// ===========================================================
// SELECTOR DE FORMATO ESTILO APPLE
// ===========================================================

class _WalletLayoutToggle extends StatelessWidget {
  const _WalletLayoutToggle({
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  final String value;
  final bool enabled;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final isPoster = value != 'classic';

    return LayoutBuilder(
      builder: (context, constraints) {
        const inset = 4.0;
        final segmentWidth = (constraints.maxWidth - inset * 2) / 2;

        return Container(
          height: 56,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Stack(
            children: [
              AnimatedPositioned(
                duration: const Duration(milliseconds: 420),
                curve: Curves.easeOutBack,
                left: inset + (isPoster ? 0 : segmentWidth),
                top: inset,
                width: segmentWidth,
                height: 48,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(15),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x16000000),
                        blurRadius: 12,
                        offset: Offset(0, 3),
                      ),
                    ],
                  ),
                ),
              ),
              Row(
                children: [
                  _LayoutSegment(
                    label: 'Imagen completa',
                    selected: isPoster,
                    enabled: enabled,
                    onTap: () => onChanged('poster'),
                  ),
                  _LayoutSegment(
                    label: 'Solo franja',
                    selected: !isPoster,
                    enabled: enabled,
                    onTap: () => onChanged('classic'),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class _LayoutSegment extends StatelessWidget {
  const _LayoutSegment({
    required this.label,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Semantics(
        button: true,
        selected: selected,
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(16),
          child: Center(
            child: AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 240),
              curve: Curves.easeOutCubic,
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 12.5,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: enabled
                    ? (selected
                          ? const Color(0xFF382725)
                          : const Color(0x99382725))
                    : const Color(0x55382725),
              ),
              child: Text(label, maxLines: 1, overflow: TextOverflow.fade),
            ),
          ),
        ),
      ),
    );
  }
}

// ===========================================================
// MENÚ EXPANDIBLE DE SELLOS
// ===========================================================

class _StampIconMenu extends StatefulWidget {
  const _StampIconMenu({
    required this.icons,
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  final Map<String, String> icons;
  final String value;
  final bool enabled;
  final ValueChanged<String> onChanged;

  @override
  State<_StampIconMenu> createState() => _StampIconMenuState();
}

class _StampIconMenuState extends State<_StampIconMenu>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  bool _open = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 520),
      reverseDuration: const Duration(milliseconds: 280),
    );
  }

  @override
  void didUpdateWidget(covariant _StampIconMenu oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.enabled && _open) {
      _open = false;
      _controller.reverse();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _toggle() {
    if (!widget.enabled) return;
    setState(() => _open = !_open);
    if (_open) {
      _controller.forward();
    } else {
      _controller.reverse();
    }
  }

  void _select(String value) {
    widget.onChanged(value);
    setState(() => _open = false);
    _controller.reverse();
  }

  @override
  Widget build(BuildContext context) {
    final selectedLabel = widget.icons[widget.value] ?? 'Seleccionar';

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final reveal = Curves.easeInOutCubic.transform(_controller.value);
        final spring = Curves.easeOutBack
            .transform(_controller.value)
            .clamp(0.0, 1.0);

        return Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18 + 8 * spring),
            border: Border.all(
              color: Color.lerp(
                const Color(0x10000000),
                const Color(0x1F9E483F),
                reveal,
              )!,
            ),
            boxShadow: [
              BoxShadow(
                color: Color.fromRGBO(56, 39, 37, 0.04 + 0.06 * reveal),
                blurRadius: 8 + 20 * reveal,
                offset: Offset(0, 2 + 7 * reveal),
              ),
            ],
          ),
          child: Column(
            children: [
              Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: _toggle,
                  borderRadius: BorderRadius.circular(18 + 8 * spring),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                    child: Row(
                      children: [
                        _StampGlyph(
                          icon: widget.value,
                          color: FideliTheme.ink,
                          size: 26,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            selectedLabel,
                            style: const TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 13.5,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF382725),
                            ),
                          ),
                        ),
                        Transform.rotate(
                          angle: reveal * 3.141592653589793,
                          child: const Icon(
                            Icons.keyboard_arrow_down_rounded,
                            color: Color(0xFF6D5B58),
                            size: 24,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              ClipRect(
                child: Align(
                  alignment: Alignment.topCenter,
                  heightFactor: reveal,
                  child: Opacity(
                    opacity: reveal,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 14),
                      child: Column(
                        children: [
                          Divider(
                            height: 1,
                            color: Colors.black.withValues(alpha: 0.06),
                          ),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: widget.icons.entries.map((entry) {
                              return _StampOption(
                                icon: entry.key,
                                label: entry.value,
                                selected: widget.value == entry.key,
                                enabled: widget.enabled,
                                onPressed: () => _select(entry.key),
                              );
                            }).toList(),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ===========================================================
// OPCIÓN DE SELLO
// ===========================================================

class _StampOption extends StatefulWidget {
  const _StampOption({
    required this.icon,
    required this.label,
    required this.selected,
    required this.enabled,
    required this.onPressed,
  });

  final String icon;
  final String label;

  final bool selected;
  final bool enabled;

  final VoidCallback onPressed;

  @override
  State<_StampOption> createState() => _StampOptionState();
}

class _StampOptionState extends State<_StampOption> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return AnimatedScale(
      scale: _pressed
          ? 0.94
          : widget.selected
          ? 1.03
          : 1,

      duration: const Duration(milliseconds: 150),

      curve: Curves.easeOutCubic,

      child: GestureDetector(
        onTapDown: widget.enabled
            ? (_) {
                setState(() => _pressed = true);
              }
            : null,

        onTapCancel: widget.enabled
            ? () {
                setState(() => _pressed = false);
              }
            : null,

        onTapUp: widget.enabled
            ? (_) {
                setState(() => _pressed = false);

                widget.onPressed();
              }
            : null,

        child: AnimatedContainer(
          duration: const Duration(milliseconds: 240),

          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),

          decoration: BoxDecoration(
            color: Colors.white,

            borderRadius: BorderRadius.circular(17),

            border: Border.all(
              color: widget.selected
                  ? FideliTheme.ink
                  : const Color(0x0D000000),

              width: widget.selected ? 1.4 : 1,
            ),
          ),

          child: Row(
            mainAxisSize: MainAxisSize.min,

            children: [
              _StampGlyph(
                icon: widget.icon,
                size: 24,
                color: widget.selected ? FideliTheme.ink : Colors.black54,
              ),

              const SizedBox(width: 7),

              Text(
                widget.label,

                style: TextStyle(
                  fontFamily: 'Poppins',

                  fontSize: 11.5,

                  fontWeight: widget.selected
                      ? FontWeight.w600
                      : FontWeight.w500,

                  color: const Color(0xFF382725),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StampGlyph extends StatelessWidget {
  const _StampGlyph({
    required this.icon,
    required this.color,
    this.size = 32,
    this.inactive = false,
  });

  final String icon;
  final Color color;
  final double size;
  final bool inactive;

  static const _illustratedIcons = {
    'latte',
    'coffee_beans',
    'ice_cream',
    'hair_scissors',
    'salon_chair',
    'pet_collar',
    'pet_bone',
    'pet_bowl',
  };

  IconData get _data => switch (icon) {
    'pizza' => PhosphorIconsRegular.pizza,
    'haircut' => PhosphorIconsRegular.scissors,
    'star' => PhosphorIconsRegular.star,
    'heart' => PhosphorIconsRegular.heart,
    'paw' => PhosphorIconsRegular.pawPrint,
    'check' => PhosphorIconsRegular.checkCircle,
    'gift' => PhosphorIconsRegular.gift,
    'hamburger' => PhosphorIconsRegular.hamburger,
    _ => PhosphorIconsRegular.coffee,
  };

  @override
  Widget build(BuildContext context) {
    if (_illustratedIcons.contains(icon)) {
      return Image.asset(
        'assets/images/stamps/$icon${inactive ? '_inactive' : ''}.png',
        width: size,
        height: size,
        fit: BoxFit.contain,
        errorBuilder: (context, error, stackTrace) =>
            PhosphorIcon(_data, size: size, color: color),
      );
    }
    return PhosphorIcon(_data, size: size, color: color);
  }
}

// Kept as a fallback renderer for devices that cannot load the icon font.
// ignore: unused_element
class _StampGlyphPainter extends CustomPainter {
  const _StampGlyphPainter(this.icon, this.color);
  final String icon;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 48, size.height / 48);
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.6
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final fill = Paint()..color = color;

    switch (icon) {
      case 'pizza':
        canvas.drawPath(
          Path()
            ..moveTo(10, 35)
            ..lineTo(22, 8)
            ..lineTo(37, 34)
            ..close(),
          stroke..strokeWidth = 9,
        );
        canvas.drawCircle(const Offset(21, 21), 2.5, fill);
        canvas.drawCircle(const Offset(29, 27), 2.5, fill);
        break;
      case 'haircut':
        canvas.drawPath(
          Path()
            ..moveTo(12, 31)
            ..lineTo(34, 7)
            ..moveTo(33, 31)
            ..lineTo(11, 8),
          stroke..strokeWidth = 5,
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            const Rect.fromLTRB(5, 29, 15, 39),
            const Radius.circular(5),
          ),
          fill,
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            const Rect.fromLTRB(31, 29, 41, 39),
            const Radius.circular(5),
          ),
          fill,
        );
        break;
      case 'star':
        canvas.drawPath(
          Path()
            ..moveTo(22, 5)
            ..lineTo(27, 16)
            ..lineTo(39, 17)
            ..lineTo(30, 25)
            ..lineTo(33, 37)
            ..lineTo(22, 31)
            ..lineTo(11, 37)
            ..lineTo(14, 25)
            ..lineTo(5, 17)
            ..lineTo(17, 16)
            ..close(),
          stroke..strokeWidth = 8,
        );
        break;
      case 'heart':
        canvas.drawPath(
          Path()
            ..moveTo(22, 38)
            ..lineTo(8, 27)
            ..lineTo(6, 16)
            ..lineTo(11, 9)
            ..lineTo(18, 10)
            ..lineTo(22, 15)
            ..lineTo(26, 10)
            ..lineTo(34, 9)
            ..lineTo(39, 16)
            ..lineTo(36, 27)
            ..close(),
          stroke..strokeWidth = 9,
        );
        break;
      case 'paw':
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            const Rect.fromLTRB(12, 21, 32, 39),
            const Radius.circular(8),
          ),
          fill,
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            const Rect.fromLTRB(5, 12, 13, 22),
            const Radius.circular(4),
          ),
          fill,
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            const Rect.fromLTRB(14, 5, 22, 16),
            const Radius.circular(4),
          ),
          fill,
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            const Rect.fromLTRB(24, 5, 32, 16),
            const Radius.circular(4),
          ),
          fill,
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            const Rect.fromLTRB(34, 12, 42, 22),
            const Radius.circular(4),
          ),
          fill,
        );
        break;
      case 'check':
        canvas.drawCircle(const Offset(24, 24), 19, stroke);
        canvas.drawPath(
          Path()
            ..moveTo(13, 24)
            ..lineTo(21, 32)
            ..lineTo(36, 15),
          stroke..strokeWidth = 5,
        );
        break;
      default:
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            const Rect.fromLTRB(8, 15, 34, 35),
            const Radius.circular(4),
          ),
          fill,
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            const Rect.fromLTRB(31, 19, 42, 31),
            const Radius.circular(5),
          ),
          fill,
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            const Rect.fromLTRB(6, 36, 37, 40),
            const Radius.circular(2),
          ),
          fill,
        );
        canvas.drawPath(
          Path()
            ..moveTo(15, 12)
            ..lineTo(15, 4)
            ..moveTo(23, 12)
            ..lineTo(23, 4)
            ..moveTo(31, 12)
            ..lineTo(31, 4),
          stroke..strokeWidth = 4,
        );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _StampGlyphPainter old) =>
      old.icon != icon || old.color != color;
}

// ===========================================================
// CREADOR DE COLOR PERSONALIZADO
// ===========================================================

class _CustomColorEditor extends StatefulWidget {
  const _CustomColorEditor({required this.color, required this.onChanged});

  final HSVColor color;

  final ValueChanged<HSVColor> onChanged;

  @override
  State<_CustomColorEditor> createState() => _CustomColorEditorState();
}

class _CustomColorEditorState extends State<_CustomColorEditor> {
  late final TextEditingController _hexController;

  @override
  void initState() {
    super.initState();

    _hexController = TextEditingController(text: _hex(widget.color.toColor()));
  }

  @override
  void didUpdateWidget(covariant _CustomColorEditor oldWidget) {
    super.didUpdateWidget(oldWidget);

    final newHex = _hex(widget.color.toColor());

    if (_hexController.text.toUpperCase() != newHex) {
      _hexController.text = newHex;
    }
  }

  @override
  void dispose() {
    _hexController.dispose();
    super.dispose();
  }

  String _hex(Color color) {
    final value = color.toARGB32() & 0xFFFFFF;

    return '#${value.toRadixString(16).padLeft(6, '0').toUpperCase()}';
  }

  void _fromHex(String value) {
    var clean = value.trim();

    clean = clean.replaceFirst('#', '');

    if (clean.length != 6) {
      return;
    }

    final parsed = int.tryParse(clean, radix: 16);

    if (parsed == null) {
      return;
    }

    final color = Color(0xFF000000 | parsed);

    widget.onChanged(HSVColor.fromColor(color));
  }

  @override
  Widget build(BuildContext context) {
    final current = widget.color.toColor();

    return Column(
      children: [
        _ColorPalette(color: widget.color, onChanged: widget.onChanged),
        const SizedBox(height: 18),
        Row(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 260),
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: current,
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: _hexController,
                textCapitalization: TextCapitalization.characters,
                onChanged: _fromHex,
                decoration: InputDecoration(
                  labelText: 'HEX',
                  hintText: '#9E483F',
                  filled: true,
                  fillColor: Colors.white,
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
                    borderSide: const BorderSide(
                      color: FideliTheme.ink,
                      width: 1.5,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _ColorPalette extends StatelessWidget {
  const _ColorPalette({required this.color, required this.onChanged});

  final HSVColor color;
  final ValueChanged<HSVColor> onChanged;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        void updatePalette(Offset point) {
          final saturation = (point.dx / width).clamp(0.0, 1.0);
          final value = 1 - (point.dy / 190).clamp(0.0, 1.0);
          onChanged(color.withSaturation(saturation).withValue(value));
        }

        void updateHue(Offset point) {
          onChanged(color.withHue((point.dx / width).clamp(0.0, 1.0) * 360));
        }

        return Column(
          children: [
            GestureDetector(
              onPanDown: (event) => updatePalette(event.localPosition),
              onPanUpdate: (event) => updatePalette(event.localPosition),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: SizedBox(
                  width: width,
                  height: 190,
                  child: CustomPaint(
                    painter: _SaturationValuePainter(color.hue),
                    foregroundPainter: _PaletteIndicatorPainter(
                      Offset(color.saturation * width, (1 - color.value) * 190),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            GestureDetector(
              onPanDown: (event) => updateHue(event.localPosition),
              onPanUpdate: (event) => updateHue(event.localPosition),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: SizedBox(
                  width: width,
                  height: 22,
                  child: CustomPaint(
                    painter: const _HuePainter(),
                    foregroundPainter: _HueIndicatorPainter(
                      color.hue / 360 * width,
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _SaturationValuePainter extends CustomPainter {
  const _SaturationValuePainter(this.hue);
  final double hue;
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          colors: [Colors.white, HSVColor.fromAHSV(1, hue, 1, 1).toColor()],
        ).createShader(rect),
    );
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.transparent, Colors.black],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(covariant _SaturationValuePainter old) => old.hue != hue;
}

class _HuePainter extends CustomPainter {
  const _HuePainter();
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          colors: [
            Colors.red,
            Colors.yellow,
            Colors.green,
            Colors.cyan,
            Colors.blue,
            Colors.purple,
            Colors.red,
          ],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _PaletteIndicatorPainter extends CustomPainter {
  const _PaletteIndicatorPainter(this.point);
  final Offset point;
  @override
  void paint(Canvas canvas, Size size) {
    final safe = Offset(
      point.dx.clamp(8, size.width - 8),
      point.dy.clamp(8, size.height - 8),
    );
    canvas.drawCircle(
      safe,
      8,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );
    canvas.drawCircle(
      safe,
      9.5,
      Paint()
        ..color = Colors.black26
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(covariant _PaletteIndicatorPainter old) =>
      old.point != point;
}

class _HueIndicatorPainter extends CustomPainter {
  const _HueIndicatorPainter(this.x);
  final double x;
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromCenter(
      center: Offset(x.clamp(5, size.width - 5), size.height / 2),
      width: 6,
      height: size.height,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(4)),
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(covariant _HueIndicatorPainter old) => old.x != x;
}

// ===========================================================
// GUARDANDO
// ===========================================================

class _SavingCard extends StatelessWidget {
  const _SavingCard();

  @override
  Widget build(BuildContext context) {
    return _StudioCard(
      child: Row(
        children: [
          const SizedBox(
            width: 28,
            height: 28,

            child: CircularProgressIndicator(
              strokeWidth: 2.5,

              color: FideliTheme.ink,
            ),
          ),

          const SizedBox(width: 15),

          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,

              children: [
                Text(
                  'Actualizando tarjeta…',

                  style: TextStyle(
                    fontFamily: 'Poppins',

                    fontSize: 14,

                    fontWeight: FontWeight.w600,
                  ),
                ),

                SizedBox(height: 3),

                Text(
                  'Sincronizando el nuevo diseño con Wallet.',

                  style: TextStyle(
                    fontFamily: 'Poppins',

                    fontSize: 11.5,

                    color: Colors.black45,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ===========================================================
// PREVIEW DE WALLET
// ===========================================================

class _PassPreview extends StatelessWidget {
  const _PassPreview({
    required this.businessName,
    required this.color,
    required this.program,
    this.logo,

    this.background,

    this.stampIcon = 'coffee',

    this.walletLayout = 'poster',
  });

  final String businessName;

  // ESTE ES EL ÚNICO COLOR VARIABLE
  // DE LA INTERFAZ.

  final Color color;

  final LoyaltyProgram program;
  final Uint8List? logo;

  final Uint8List? background;

  final String stampIcon;
  final String walletLayout;
  @override
  Widget build(BuildContext context) {
    final isGift = program.cardKind == 'Tarjeta de regalo';

    final isMembership = program.type == ProgramType.membership;

    final usesPoints = program.type == ProgramType.points && !isGift;

    final isStampCard = !isGift && !isMembership && !usesPoints;

    final classicStrip = walletLayout == 'classic';

    final fullImage = !classicStrip && background != null;

    return Container(
      width: 350,
      height: 474,
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 16),

      decoration: BoxDecoration(
        // ESTE COLOR SÍ CAMBIA
        color: color,

        borderRadius: BorderRadius.circular(22),

        image: fullImage
            ? DecorationImage(
                image: MemoryImage(background!),

                fit: BoxFit.cover,

                colorFilter: const ColorFilter.mode(
                  Colors.black45,
                  BlendMode.darken,
                ),
              )
            : null,
      ),

      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,

        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: logo == null
                    ? Row(
                        children: [
                          const Icon(
                            Icons.storefront_rounded,
                            color: Colors.white,
                            size: 30,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              businessName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontFamily: 'Poppins',
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      )
                    : Align(
                        alignment: Alignment.centerLeft,
                        child: Image.memory(
                          logo!,
                          height: 42,
                          fit: BoxFit.contain,
                          filterQuality: FilterQuality.high,
                        ),
                      ),
              ),
              if (!isMembership && !isGift) ...[
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      usesPoints ? 'PUNTOS' : 'SELLOS',
                      style: const TextStyle(
                        fontFamily: 'Poppins',
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      usesPoints ? '240' : '1/${program.goal}',
                      style: const TextStyle(
                        fontFamily: 'Poppins',
                        color: Colors.white,
                        fontSize: 19,
                        height: 1.05,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
          const SizedBox(height: 14),
          if (classicStrip && isStampCard)
            Expanded(
              child: _ClassicStampPreview(
                background: background,
                stampIcon: stampIcon,
                goal: program.goal,
                color: color,
              ),
            )
          else if (classicStrip)
            Expanded(
              child: _ClassicCardPreview(
                background: background,
                color: color,
                child: _content(isGift, isMembership, usesPoints),
              ),
            )
          else
            Expanded(
              child: _Artwork(
                background: fullImage ? null : background,
                child: _content(isGift, isMembership, usesPoints),
              ),
            ),
        ],
      ),
    );
  }

  Widget _content(bool isGift, bool isMembership, bool usesPoints) {
    // =======================================================
    // REGALO
    // =======================================================

    if (isGift) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.card_giftcard_rounded, color: Colors.white, size: 46),
              SizedBox(width: 14),
              Expanded(child: _PassValue('SALDO', 'Bs 150,00', large: true)),
            ],
          ),
          const Spacer(),
          const Center(child: _WalletQrPreview()),
          const Spacer(),
        ],
      );
    }

    // =======================================================
    // MEMBRESÍA
    // =======================================================

    if (isMembership) {
      final expiration = program.expiresAt == null
          ? 'Sin vencimiento'
          : '${program.expiresAt!.day}/'
                '${program.expiresAt!.month}/'
                '${program.expiresAt!.year}';

      final status = program.active && !program.isExpired
          ? 'ACTIVA'
          : 'INACTIVA';

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: _PassValue('MEMBRESÍA', status, large: true)),
            ],
          ),
          const SizedBox(height: 18),
          _PassValue('VENCIMIENTO', expiration),
          const Spacer(),
          const Center(child: _WalletQrPreview()),
          const Spacer(),
        ],
      );
    }

    // =======================================================
    // PUNTOS
    // =======================================================

    if (usesPoints) {
      final progress = program.goal <= 0
          ? 0.0
          : (240 / program.goal).clamp(0.0, 1.0).toDouble();

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,

        children: [
          const Row(
            children: [
              Icon(Icons.stars_rounded, color: Colors.white, size: 38),

              SizedBox(width: 10),

              Expanded(child: _PassValue('TUS PUNTOS', '240', large: true)),

              Icon(Icons.qr_code_2, color: Colors.white, size: 46),
            ],
          ),

          const SizedBox(height: 15),

          ClipRRect(
            borderRadius: BorderRadius.circular(20),

            child: LinearProgressIndicator(
              value: progress,

              minHeight: 7,

              backgroundColor: Colors.white.withValues(alpha: 0.20),

              valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
            ),
          ),

          const SizedBox(height: 7),

          Text(
            'Meta: ${program.goal} puntos',

            style: TextStyle(
              fontFamily: 'Poppins',

              color: Colors.white.withValues(alpha: 0.70),

              fontSize: 11,
            ),
          ),
        ],
      );
    }

    // =======================================================
    // SELLOS
    // =======================================================

    final filled = program.goal <= 1 ? 1 : (program.goal / 2).ceil();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,

      children: [
        Wrap(
          alignment: WrapAlignment.spaceAround,
          spacing: 10,
          runSpacing: 12,

          children: List.generate(program.goal.clamp(1, 12), (index) {
            final active = index < filled;

            return AnimatedContainer(
              duration: const Duration(milliseconds: 280),

              width: 48,
              height: 48,
              child: _StampGlyph(
                icon: stampIcon,
                color: Colors.white.withValues(alpha: active ? 1 : 0.45),
                size: 43,
                inactive: !active,
              ),
            );
          }),
        ),

        const Spacer(),
        Center(
          child: Container(
            padding: const EdgeInsets.all(8),
            color: Colors.white,
            child: QrImageView(
              data: 'FIDELI-PREVIEW',
              size: 112,
              padding: EdgeInsets.zero,
            ),
          ),
        ),
        const Spacer(),
        const _PassValue('CLIENTE', 'Nombre del cliente'),
      ],
    );
  }
}

class _WalletQrPreview extends StatelessWidget {
  const _WalletQrPreview();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(7),
      color: Colors.white,
      child: QrImageView(
        data: 'FIDELI-PREVIEW',
        size: 126,
        padding: EdgeInsets.zero,
      ),
    );
  }
}

class _ClassicCardPreview extends StatelessWidget {
  const _ClassicCardPreview({
    required this.background,
    required this.color,
    required this.child,
  });

  final Uint8List? background;
  final Color color;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      key: const ValueKey('classic-card-layout'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: AspectRatio(
            aspectRatio: 375 / 123,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: background == null
                    ? Color.lerp(color, Colors.white, .14)
                    : null,
                image: background == null
                    ? null
                    : DecorationImage(
                        image: MemoryImage(background!),
                        fit: BoxFit.cover,
                        colorFilter: const ColorFilter.mode(
                          Colors.black26,
                          BlendMode.darken,
                        ),
                      ),
                border: Border.all(color: Colors.white.withValues(alpha: .14)),
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: child,
          ),
        ),
      ],
    );
  }
}

class _ClassicStampPreview extends StatelessWidget {
  const _ClassicStampPreview({
    required this.background,
    required this.stampIcon,
    required this.goal,
    required this.color,
  });

  final Uint8List? background;
  final String stampIcon;
  final int goal;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final visibleGoal = goal.clamp(1, 10);
    final filled = visibleGoal <= 1 ? 1 : (visibleGoal / 2).ceil();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AspectRatio(
          aspectRatio: 375 / 123,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              color: background == null ? color.withValues(alpha: .82) : null,
              image: background == null
                  ? null
                  : DecorationImage(
                      image: MemoryImage(background!),
                      fit: BoxFit.cover,
                      colorFilter: const ColorFilter.mode(
                        Colors.black26,
                        BlendMode.darken,
                      ),
                    ),
            ),
            child: Wrap(
              alignment: WrapAlignment.spaceAround,
              runAlignment: WrapAlignment.spaceAround,
              spacing: 8,
              runSpacing: 5,
              children: List.generate(visibleGoal, (index) {
                return _StampGlyph(
                  icon: stampIcon,
                  color: Colors.white.withValues(
                    alpha: index < filled ? 1 : .48,
                  ),
                  size: 35,
                  inactive: index >= filled,
                );
              }),
            ),
          ),
        ),
        const SizedBox(height: 14),
        const Row(
          children: [
            Expanded(child: _PassValue('CLIENTE', 'Nombre del cliente')),
            _PassValue('VISITAS', '8'),
          ],
        ),
        const Spacer(),
        Center(
          child: Container(
            padding: const EdgeInsets.all(8),
            color: Colors.white,
            child: QrImageView(
              data: 'FIDELI-PREVIEW',
              size: 132,
              padding: EdgeInsets.zero,
            ),
          ),
        ),
        const Spacer(),
      ],
    );
  }
}

// ===========================================================
// CONTENEDOR INTERIOR
// ===========================================================

class _Artwork extends StatelessWidget {
  const _Artwork({required this.background, required this.child});

  final Uint8List? background;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: double.infinity,
      padding: const EdgeInsets.all(12),

      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),

        image: background == null
            ? null
            : DecorationImage(
                image: MemoryImage(background!),

                fit: BoxFit.cover,

                colorFilter: const ColorFilter.mode(
                  Colors.black45,
                  BlendMode.darken,
                ),
              ),

        color: background == null ? Colors.black.withValues(alpha: 0.12) : null,

        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),

      child: child,
    );
  }
}

// ===========================================================
// VALORES
// ===========================================================

class _RectFlightTween extends Tween<Rect> {
  _RectFlightTween({required Rect begin, required Rect end})
    : super(begin: begin, end: end);

  @override
  Rect lerp(double t) => Rect.lerp(begin!, end!, t)!;
}

class _PassValue extends StatelessWidget {
  const _PassValue(this.label, this.value, {this.large = false});

  final String label;
  final String value;

  final bool large;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,

      children: [
        Text(
          label,

          style: TextStyle(
            fontFamily: 'Poppins',

            color: Colors.white.withValues(alpha: 0.68),

            fontSize: 9.5,

            fontWeight: FontWeight.w500,

            letterSpacing: 0.4,
          ),
        ),

        const SizedBox(height: 2),

        Text(
          value,

          style: TextStyle(
            fontFamily: 'Poppins',

            color: Colors.white,

            fontSize: large ? 21 : 15,

            fontWeight: large ? FontWeight.w700 : FontWeight.w500,

            letterSpacing: large ? -0.4 : 0,
          ),
        ),
      ],
    );
  }
}
