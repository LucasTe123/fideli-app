import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:image/image.dart' as image_lib;
import 'package:image_picker/image_picker.dart';
import 'package:lottie/lottie.dart';

import '../services/cloud_store.dart';
import '../state/app_scope.dart';
import '../widgets/common.dart';

class EscenaCafeScreen extends StatefulWidget {
  const EscenaCafeScreen({super.key, required this.onCompleted});

  final VoidCallback onCompleted;

  @override
  State<EscenaCafeScreen> createState() => _EscenaCafeScreenState();
}

class _EscenaCafeScreenState extends State<EscenaCafeScreen>
    with TickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _category = TextEditingController();

  Uint8List? _photo;
  bool _showForm = false;
  bool _transitioning = false;
  bool _saving = false;

  late final AnimationController _coffeeController;
  late final AnimationController _introController;
  late final AnimationController _field1Controller;
  late final AnimationController _field2Controller;
  late final AnimationController _field3Controller;
  late final AnimationController _buttonController;

  late final Animation<double> _coffeeAnimation;
  late final Animation<double> _introFade;
  late final Animation<Offset> _introSlide;
  late final Animation<Offset> _field1Slide;
  late final Animation<Offset> _field2Slide;
  late final Animation<Offset> _field3Slide;
  late final Animation<Offset> _buttonSlide;

  @override
  void initState() {
    super.initState();
    _coffeeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _introController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 550),
      reverseDuration: const Duration(milliseconds: 350),
    );
    _field1Controller = _fieldController();
    _field2Controller = _fieldController();
    _field3Controller = _fieldController();
    _buttonController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 550),
    );

    _coffeeAnimation = CurvedAnimation(
      parent: _coffeeController,
      curve: Curves.easeOutCubic,
    );
    _introFade = CurvedAnimation(
      parent: _introController,
      curve: Curves.easeOut,
      reverseCurve: Curves.easeIn,
    );
    _introSlide = _slide(
      _introController,
      const Offset(0, .15),
      Curves.easeOutCubic,
    );
    _field1Slide = _slide(_field1Controller, const Offset(-1.5, 0));
    _field2Slide = _slide(_field2Controller, const Offset(-1.5, 0));
    _field3Slide = _slide(_field3Controller, const Offset(-1.5, 0));
    _buttonSlide = _slide(
      _buttonController,
      const Offset(0, 2),
      Curves.easeOutBack,
    );

    WidgetsBinding.instance.addPostFrameCallback((_) => _startScene());
  }

  AnimationController _fieldController() => AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
  );

  Animation<Offset> _slide(
    AnimationController controller,
    Offset begin, [
    Curve curve = Curves.easeOutCubic,
  ]) => Tween<Offset>(
    begin: begin,
    end: Offset.zero,
  ).animate(CurvedAnimation(parent: controller, curve: curve));

  Future<void> _startScene() async {
    await _coffeeController.forward();
    if (!mounted) return;
    await Future<void>.delayed(const Duration(milliseconds: 120));
    if (mounted) await _introController.forward();
  }

  Future<void> _showBusinessForm() async {
    if (_transitioning) return;
    _transitioning = true;
    await _introController.reverse();
    if (!mounted) return;
    setState(() => _showForm = true);
    await Future<void>.delayed(const Duration(milliseconds: 100));
    for (final controller in [
      _field1Controller,
      _field2Controller,
      _field3Controller,
    ]) {
      await controller.forward();
      if (!mounted) return;
      await Future<void>.delayed(const Duration(milliseconds: 80));
    }
    await _buttonController.forward();
    _transitioning = false;
  }

  Future<void> _pickPhoto() async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 1800,
      imageQuality: 92,
    );
    if (picked == null || !mounted) return;
    final bytes = await picked.readAsBytes();
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    final width = frame.image.width;
    final height = frame.image.height;
    frame.image.dispose();
    codec.dispose();
    if (!mounted) return;

    final accepted = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => Dialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Vista previa',
                style: _poppins(fontSize: 22, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 18),
              ClipRRect(
                borderRadius: BorderRadius.circular(22),
                child: Image.memory(
                  bytes,
                  width: 220,
                  height: 220,
                  fit: BoxFit.cover,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                '$width × $height px',
                style: _poppins(fontSize: 18, fontWeight: FontWeight.w700),
              ),
              Text(
                width == height
                    ? '✓ Imagen cuadrada'
                    : 'La ajustaremos automáticamente al centro',
                textAlign: TextAlign.center,
                style: _poppins(
                  fontSize: 13,
                  color: width == height ? Colors.green : Colors.orange,
                ),
              ),
              const SizedBox(height: 22),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(dialogContext, false),
                      child: const Text('Cancelar'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: () => Navigator.pop(dialogContext, true),
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFFF8B218),
                        foregroundColor: Colors.black,
                      ),
                      child: const Text('Usar foto'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (accepted == true && mounted) setState(() => _photo = bytes);
  }

  Future<void> _continue() async {
    if (_saving || !_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final state = AppScope.of(context);
      if (_photo case final bytes?) {
        final decoded = image_lib.decodeImage(bytes);
        final cloud = CloudStore.instance;
        if (decoded != null && cloud != null) {
          final source = image_lib.bakeOrientation(decoded);
          final side = source.width < source.height
              ? source.width
              : source.height;
          final square = image_lib.copyCrop(
            source,
            x: (source.width - side) ~/ 2,
            y: (source.height - side) ~/ 2,
            width: side,
            height: side,
          );
          Uint8List iconAt(int size) => image_lib.encodePng(
            image_lib.copyResize(square, width: size, height: size),
            level: 6,
          );
          state.data.business.walletIconPath = await cloud.uploadWalletIcon(
            icon: iconAt(29),
            icon2x: iconAt(58),
            icon3x: iconAt(87),
          );
        }
      }
      await state.finishOnboarding(
        name: _name.text,
        category: _category.text,
        branch: 'Principal',
      );
      if (!mounted) return;
      widget.onCompleted();
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      showMessage(context, 'No se pudo guardar el local');
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _category.dispose();
    _coffeeController.dispose();
    _introController.dispose();
    _field1Controller.dispose();
    _field2Controller.dispose();
    _field3Controller.dispose();
    _buttonController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const background = Color(0xFF9E483F);
    const cream = Color(0xFFF8E5D2);
    const yellow = Color(0xFFF8B218);
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;

    return Scaffold(
      resizeToAvoidBottomInset: false,
      backgroundColor: background,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680, maxHeight: 900),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth;
                final height = constraints.maxHeight;
                final artSize = (width * 1.42).clamp(480.0, 650.0);
                final contentTop = keyboard > 0
                    ? height * .43 - keyboard * .2
                    : height * .57;
                return Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Positioned(
                      left: -(artSize * .12),
                      top: -(artSize * .08),
                      child: AnimatedBuilder(
                        animation: _coffeeAnimation,
                        child: SizedBox(
                          width: artSize,
                          height: artSize,
                          child: Lottie.asset(
                            'assets/animations/cafe.json',
                            repeat: true,
                            fit: BoxFit.contain,
                          ),
                        ),
                        builder: (context, child) {
                          final value = _coffeeAnimation.value;
                          return Opacity(
                            opacity: value,
                            child: Transform.scale(
                              scale: .97 + .03 * value,
                              child: ImageFiltered(
                                imageFilter: ui.ImageFilter.blur(
                                  sigmaX: 16 * (1 - value),
                                  sigmaY: 16 * (1 - value),
                                ),
                                child: child,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    Positioned(
                      left: width * .1,
                      top: 28,
                      child: Row(
                        children: [
                          _indicator(false),
                          const SizedBox(width: 10),
                          _indicator(true),
                          const SizedBox(width: 10),
                          _indicator(false),
                        ],
                      ),
                    ),
                    if (!_showForm)
                      Positioned(
                        left: 30,
                        right: 24,
                        top: contentTop,
                        child: SlideTransition(
                          position: _introSlide,
                          child: FadeTransition(
                            opacity: _introFade,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Cuéntanos sobre\ntu local',
                                  style: _poppins(
                                    color: Colors.white,
                                    fontSize: 31,
                                    fontWeight: FontWeight.w600,
                                    height: 1.05,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'queremos conocerte un poquito más',
                                  style: _script(
                                    color: cream,
                                    fontSize: 27,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 28),
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: _yellowButton(
                                    text: 'Continuar',
                                    color: yellow,
                                    onPressed: _showBusinessForm,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    if (_showForm)
                      Positioned(
                        left: 28,
                        right: 28,
                        top: contentTop - 18,
                        child: Form(
                          key: _formKey,
                          child: Column(
                            children: [
                              _animatedField(
                                controller: _field1Controller,
                                slide: _field1Slide,
                                child: _textField(
                                  controller: _name,
                                  hint: 'Nombre del local',
                                ),
                              ),
                              const SizedBox(height: 12),
                              _animatedField(
                                controller: _field2Controller,
                                slide: _field2Slide,
                                child: _textField(
                                  controller: _category,
                                  hint: 'Categoría del local',
                                ),
                              ),
                              const SizedBox(height: 12),
                              _animatedField(
                                controller: _field3Controller,
                                slide: _field3Slide,
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(35),
                                  onTap: _saving ? null : _pickPhoto,
                                  child: Container(
                                    height: 55,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 18,
                                    ),
                                    decoration: _fieldDecoration(),
                                    child: Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        if (_photo case final photo?) ...[
                                          ClipOval(
                                            child: Image.memory(
                                              photo,
                                              width: 38,
                                              height: 38,
                                              fit: BoxFit.cover,
                                            ),
                                          ),
                                          const SizedBox(width: 10),
                                          const Text('Foto seleccionada'),
                                        ] else ...[
                                          const Icon(
                                            Icons.add_photo_alternate_outlined,
                                            color: Color(0xFF55515A),
                                          ),
                                          const SizedBox(width: 10),
                                          Text(
                                            'Subir foto del local',
                                            style: _poppins(
                                              color: const Color(0xFF55515A),
                                              fontSize: 15,
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 20),
                              SlideTransition(
                                position: _buttonSlide,
                                child: FadeTransition(
                                  opacity: _buttonController,
                                  child: Align(
                                    alignment: Alignment.centerRight,
                                    child: _yellowButton(
                                      text: _saving
                                          ? 'Guardando…'
                                          : 'Continuar',
                                      color: yellow,
                                      onPressed: _saving ? null : _continue,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _animatedField({
    required AnimationController controller,
    required Animation<Offset> slide,
    required Widget child,
  }) => SlideTransition(
    position: slide,
    child: FadeTransition(opacity: controller, child: child),
  );

  Widget _textField({
    required TextEditingController controller,
    required String hint,
  }) => SizedBox(
    height: 55,
    child: TextFormField(
      controller: controller,
      style: _poppins(fontSize: 15),
      textInputAction: hint.startsWith('Nombre')
          ? TextInputAction.next
          : TextInputAction.done,
      validator: (value) =>
          value == null || value.trim().isEmpty ? 'Campo obligatorio' : null,
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: _poppins(color: const Color(0xFF55515A), fontSize: 15),
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: 20),
        border: _fieldBorder(),
        enabledBorder: _fieldBorder(),
        focusedBorder: _fieldBorder(width: 2),
        errorStyle: const TextStyle(height: 0, fontSize: 0),
      ),
    ),
  );

  static OutlineInputBorder _fieldBorder({double width = 1.5}) =>
      OutlineInputBorder(
        borderRadius: BorderRadius.circular(35),
        borderSide: BorderSide(color: const Color(0xFFE1D0C0), width: width),
      );

  static BoxDecoration _fieldDecoration() => BoxDecoration(
    color: Colors.white,
    borderRadius: BorderRadius.circular(35),
    border: Border.all(color: const Color(0xFFE1D0C0), width: 1.5),
  );

  static Widget _yellowButton({
    required String text,
    required Color color,
    required VoidCallback? onPressed,
  }) => SizedBox(
    width: 150,
    height: 58,
    child: ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.black,
        disabledBackgroundColor: color.withValues(alpha: .65),
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(35)),
      ),
      child: Text(
        text,
        style: _poppins(fontSize: 17, fontWeight: FontWeight.w600),
      ),
    ),
  );

  static Widget _indicator(bool active) => Container(
    width: active ? 28 : 9,
    height: 9,
    decoration: BoxDecoration(
      color: active ? const Color(0xFFF8E5D2) : const Color(0x80F8E5D2),
      borderRadius: BorderRadius.circular(20),
    ),
  );

  static TextStyle _poppins({
    Color? color,
    double? fontSize,
    FontWeight? fontWeight,
    double? height,
  }) => TextStyle(
    fontFamily: 'Avenir Next',
    color: color,
    fontSize: fontSize,
    fontWeight: fontWeight,
    height: height,
  );

  static TextStyle _script({
    Color? color,
    double? fontSize,
    FontWeight? fontWeight,
  }) => TextStyle(
    fontFamily: 'FideliScript',
    color: color,
    fontSize: fontSize,
    fontWeight: fontWeight,
  );
}
