import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';

import '../models/app_data.dart';
import '../services/cloud_store.dart';
import '../state/app_scope.dart';

/// Presentación y acceso visual de Fideli.
///
/// Mantiene separadas las cuentas de los restaurantes y los clientes Wallet.
class AuthFlowScreen extends StatefulWidget {
  const AuthFlowScreen({
    super.key,
    required this.onAuthenticated,
    this.hasSavedSession = false,
    this.savedBusiness,
    this.savedBusinessMark,
  });

  final Future<void> Function() onAuthenticated;
  final bool hasSavedSession;
  final BusinessProfile? savedBusiness;
  final Uint8List? savedBusinessMark;

  @override
  State<AuthFlowScreen> createState() => _AuthFlowScreenState();
}

class _AuthFlowScreenState extends State<AuthFlowScreen>
    with TickerProviderStateMixin {
  static const _wine = Color(0xFF493354);
  static const _cream = Colors.white;
  static const _gold = Color(0xFFF5B51B);
  static const _coral = Color(0xFFED5264);
  static const _ink = Color(0xFF26242B);
  static const _paper = Color(0xFFF8F8F7);
  static const _muted = Color(0xFF77747C);

  late final AnimationController _introController;
  late final AnimationController _transitionController;
  late final Animation<double> _introFade;
  bool _introStarted = false;
  bool _showingLogin = true;
  bool _enteringSavedSession = false;

  @override
  void initState() {
    super.initState();
    _introController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _transitionController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..value = 1;
    _introFade = CurvedAnimation(
      parent: _introController,
      curve: Curves.easeInOutCubic,
    );
    // La interfaz nunca debe quedar invisible esperando que Lottie termine de
    // leer el recurso. La animación decorativa carga de forma independiente.
    _introStarted = true;
    _introController.forward();
  }

  @override
  void dispose() {
    _introController.dispose();
    _transitionController.dispose();
    super.dispose();
  }

  void _startIntro() {
    if (_introStarted) return;
    _introStarted = true;
    _introController.forward();
  }

  void _showLogin() {
    if (_showingLogin) return;
    setState(() => _showingLogin = true);
    _transitionController.forward();
  }

  Future<void> _continueFromWelcome() async {
    if (!widget.hasSavedSession) {
      _showLogin();
      return;
    }
    if (_enteringSavedSession) return;
    setState(() => _enteringSavedSession = true);
    try {
      await widget.onAuthenticated();
    } catch (_) {
      await CloudStore.instance?.signOutRestaurant();
      if (!mounted) return;
      setState(() => _enteringSavedSession = false);
      _showLogin();
    }
  }

  double _lerp(double from, double to, double value) =>
      from + (to - from) * value;

  Widget _desktopLayout({
    required double width,
    required double height,
    required double progress,
    required double panelProgress,
    required double formProgress,
  }) {
    final artworkWidth = (width * .68).clamp(640.0, 880.0).toDouble();
    final artworkHeight = artworkWidth * .82;
    final panelWidth = (width * .40).clamp(360.0, 520.0).toDouble();
    final panelHeight = (height * .72).clamp(0.0, 680.0).toDouble();
    final artworkLeft = _lerp(
      (width - artworkWidth) / 2,
      (width * .5 - artworkWidth) / 2,
      progress,
    );
    final brandLeft = _lerp(width * .31, width * .055, progress);
    final panelLeft = _lerp(width + 48, width - panelWidth - 24, panelProgress);
    final panelTop = (height - panelHeight) / 2;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned(
          left: artworkLeft,
          top: -height * .025,
          width: artworkWidth,
          height: artworkHeight,
          child: IgnorePointer(
            child: Lottie.asset(
              'assets/animations/my_animation_tes.json',
              fit: BoxFit.contain,
              repeat: true,
              onLoaded: (_) => _startIntro(),
            ),
          ),
        ),
        if (!_introStarted)
          const Center(child: CircularProgressIndicator(color: _gold)),
        Positioned(
          left: brandLeft,
          top: height * .62,
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Fideli',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  color: _coral,
                  fontSize: 74,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -5,
                  height: 1,
                ),
              ),
              SizedBox(height: 10),
              Text(
                'Tu lealtad lo vale.',
                style: TextStyle(
                  fontFamily: 'FideliScript',
                  color: _wine,
                  fontSize: 54,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        IgnorePointer(
          ignoring: _showingLogin,
          child: Opacity(
            opacity: 1 - progress,
            child: Stack(
              children: [
                Positioned(
                  left: width * .10,
                  bottom: height * .06,
                  child: const _PageIndicator(),
                ),
                Positioned(
                  right: width * .08,
                  bottom: height * .045,
                  child: FilledButton(
                    onPressed: _enteringSavedSession
                        ? null
                        : _continueFromWelcome,
                    style: FilledButton.styleFrom(
                      minimumSize: Size(width * .28, 58),
                      backgroundColor: _coral,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      textStyle: const TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    child: _enteringSavedSession
                        ? const SizedBox.square(
                            dimension: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.4,
                              color: Colors.white,
                            ),
                          )
                        : Text(
                            widget.hasSavedSession
                                ? 'Entrar'
                                : 'Iniciar sesión',
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
        Positioned(
          key: const ValueKey('desktop-login-panel'),
          left: panelLeft,
          top: panelTop,
          width: panelWidth,
          height: panelHeight,
          child: DecoratedBox(
            decoration: const BoxDecoration(
              color: _wine,
              borderRadius: BorderRadius.all(Radius.circular(42)),
              boxShadow: [
                BoxShadow(
                  color: Color(0x26000000),
                  blurRadius: 34,
                  offset: Offset(-8, 12),
                ),
              ],
            ),
            child: Opacity(
              opacity: formProgress,
              child: Transform.translate(
                offset: Offset(30 * (1 - formProgress), 0),
                child: _LoginForm(
                  onAuthenticated: widget.onAuthenticated,
                  hasSavedSession: widget.hasSavedSession,
                  onContinueSavedSession: _continueFromWelcome,
                  savedSessionLoading: _enteringSavedSession,
                  savedBusiness: widget.savedBusiness,
                  savedBusinessMark: widget.savedBusinessMark,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final desktop = MediaQuery.sizeOf(context).width >= 900;
    return Scaffold(
      resizeToAvoidBottomInset: false,
      backgroundColor: _AuthFlowScreenState._paper,
      body: SafeArea(
        bottom: false,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
          child: FadeTransition(
            opacity: _introFade,
            child: Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: desktop ? 1180 : 680,
                  maxHeight: 900,
                ),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final width = constraints.maxWidth;
                    final height = constraints.maxHeight;
                    return AnimatedBuilder(
                      animation: _transitionController,
                      builder: (context, _) {
                        final progress = Curves.easeInOutCubic.transform(
                          _transitionController.value,
                        );
                        final panelProgress = Curves.easeOutCubic.transform(
                          ((_transitionController.value - 0.08) / 0.92).clamp(
                            0.0,
                            1.0,
                          ),
                        );
                        final formProgress = Curves.easeOut.transform(
                          ((_transitionController.value - 0.58) / 0.42).clamp(
                            0.0,
                            1.0,
                          ),
                        );

                        if (desktop) {
                          return _desktopLayout(
                            width: width,
                            height: height,
                            progress: progress,
                            panelProgress: panelProgress,
                            formProgress: formProgress,
                          );
                        }

                        final animationTop = -height * 0.02;
                        final animationLeft = -width * 0.12;
                        final animationWidth = width * 1.24;
                        final animationHeight = height * 0.60;

                        final panelTop = height * 0.48;

                        return Stack(
                          clipBehavior: Clip.none,
                          children: [
                            Positioned(
                              left: animationLeft,
                              top: animationTop,
                              width: animationWidth,
                              height: animationHeight,
                              child: IgnorePointer(
                                child: Lottie.asset(
                                  'assets/animations/my_animation_tes.json',
                                  fit: BoxFit.contain,
                                  repeat: true,
                                  onLoaded: (_) => _startIntro(),
                                ),
                              ),
                            ),
                            if (!_introStarted)
                              const Center(
                                child: CircularProgressIndicator(color: _gold),
                              ),
                            Positioned(
                              left: width * 0.07,
                              right: width * 0.07,
                              top: panelTop,
                              height: height - panelTop,
                              child: DecoratedBox(
                                decoration: const BoxDecoration(
                                  color: _wine,
                                  borderRadius: BorderRadius.vertical(
                                    top: Radius.circular(38),
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Color(0x33000000),
                                      blurRadius: 24,
                                      offset: Offset(0, -8),
                                    ),
                                  ],
                                ),
                                child: Opacity(
                                  opacity: formProgress,
                                  child: Transform.translate(
                                    offset: Offset(0, 20 * (1 - formProgress)),
                                    child: _LoginForm(
                                      onAuthenticated: widget.onAuthenticated,
                                      hasSavedSession: widget.hasSavedSession,
                                      onContinueSavedSession:
                                          _continueFromWelcome,
                                      savedSessionLoading:
                                          _enteringSavedSession,
                                      savedBusiness: widget.savedBusiness,
                                      savedBusinessMark:
                                          widget.savedBusinessMark,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            IgnorePointer(
                              ignoring: _showingLogin,
                              child: Opacity(
                                opacity: 1 - progress,
                                child: _WelcomeContent(
                                  width: width,
                                  height: height,
                                  buttonLabel: widget.hasSavedSession
                                      ? 'Entrar'
                                      : 'Iniciar sesión',
                                  loading: _enteringSavedSession,
                                  onContinue: _continueFromWelcome,
                                ),
                              ),
                            ),
                          ],
                        );
                      },
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _WelcomeContent extends StatelessWidget {
  const _WelcomeContent({
    required this.width,
    required this.height,
    required this.buttonLabel,
    required this.loading,
    required this.onContinue,
  });

  final double width;
  final double height;
  final String buttonLabel;
  final bool loading;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned(
          left: width * 0.08,
          top: height * 0.48,
          child: Text(
            'Fideli',
            style: const TextStyle(
              fontFamily: 'Poppins',
              color: _AuthFlowScreenState._coral,
              fontSize: 72,
              fontWeight: FontWeight.w800,
              letterSpacing: -5,
              height: 1,
            ),
          ),
        ),
        Positioned(
          left: width * 0.08,
          top: height * 0.59,
          child: Text(
            'Tu lealtad lo vale.',
            style: const TextStyle(
              fontFamily: 'FideliScript',
              color: _AuthFlowScreenState._wine,
              fontSize: 52,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Positioned(
          left: width * 0.13,
          bottom: height * 0.07,
          child: const _PageIndicator(),
        ),
        Positioned(
          right: width * 0.07,
          bottom: height * 0.045,
          child: FilledButton(
            onPressed: loading ? null : onContinue,
            style: FilledButton.styleFrom(
              minimumSize: Size(width * 0.39, 58),
              backgroundColor: _AuthFlowScreenState._coral,
              foregroundColor: Colors.white,
              elevation: 0,
              textStyle: const TextStyle(
                fontFamily: 'Poppins',
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            child: loading
                ? const SizedBox.square(
                    dimension: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.4,
                      color: Colors.white,
                    ),
                  )
                : Text(buttonLabel),
          ),
        ),
      ],
    );
  }
}

class _PageIndicator extends StatelessWidget {
  const _PageIndicator();

  @override
  Widget build(BuildContext context) {
    return const Row(
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            color: _AuthFlowScreenState._wine,
            borderRadius: BorderRadius.all(Radius.circular(10)),
          ),
          child: SizedBox(width: 30, height: 9),
        ),
        SizedBox(width: 8),
        DecoratedBox(
          decoration: BoxDecoration(
            color: _AuthFlowScreenState._wine,
            shape: BoxShape.circle,
          ),
          child: SizedBox(width: 9, height: 9),
        ),
        SizedBox(width: 8),
        DecoratedBox(
          decoration: BoxDecoration(
            color: _AuthFlowScreenState._wine,
            shape: BoxShape.circle,
          ),
          child: SizedBox(width: 9, height: 9),
        ),
      ],
    );
  }
}

class _LoginForm extends StatefulWidget {
  const _LoginForm({
    required this.onAuthenticated,
    required this.hasSavedSession,
    required this.onContinueSavedSession,
    required this.savedSessionLoading,
    this.savedBusiness,
    this.savedBusinessMark,
  });

  final Future<void> Function() onAuthenticated;
  final bool hasSavedSession;
  final VoidCallback onContinueSavedSession;
  final bool savedSessionLoading;
  final BusinessProfile? savedBusiness;
  final Uint8List? savedBusinessMark;

  @override
  State<_LoginForm> createState() => _LoginFormState();
}

class _LoginFormState extends State<_LoginForm> {
  final _restaurantController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _creatingAccount = false;
  bool _useAnotherAccount = false;
  bool _loading = false;
  String? _message;
  bool _messageIsError = false;
  Uint8List? _businessMark;
  String _savedBusinessName = '';

  @override
  void initState() {
    super.initState();
    final savedBusiness = widget.savedBusiness;
    _businessMark = widget.savedBusinessMark;
    if (savedBusiness != null) {
      _savedBusinessName = savedBusiness.name;
    }
    if (widget.hasSavedSession && _businessMark == null) {
      unawaited(_loadSavedAccountBranding(savedBusiness));
    }
  }

  Future<void> _loadSavedAccountBranding(BusinessProfile? savedBusiness) async {
    final cloud = CloudStore.instance;
    if (cloud == null) {
      return;
    }
    try {
      final branding = savedBusiness == null
          ? await cloud.loadBusinessBranding()
          : {
              'name': savedBusiness.name,
              'logoPath': savedBusiness.walletLogoPath,
              'iconPath': savedBusiness.walletIconPath,
            };
      if (branding == null) return;
      final mark = await cloud.downloadBusinessMark(
        logoPath: branding['logoPath'] ?? '',
        iconPath: branding['iconPath'] ?? '',
      );
      if (!mounted) return;
      setState(() {
        _savedBusinessName = branding['name'] ?? '';
        _businessMark = mark;
      });
    } catch (_) {
      // El acceso guardado sigue funcionando aunque no se pueda cargar el logo.
    }
  }

  @override
  void dispose() {
    _restaurantController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  String _friendlyError(Object error) {
    final message = error.toString().toLowerCase();
    if (message.contains('already registered') ||
        message.contains('already exists') ||
        message.contains('duplicate')) {
      return 'Ese correo ya está registrado.';
    }
    if (message.contains('invalid login credentials')) {
      return 'El correo o la contraseña no son correctos.';
    }
    if (message.contains('email not confirmed')) {
      return 'Confirma tu correo antes de iniciar sesión.';
    }
    if (message.contains('password')) {
      return 'La contraseña debe tener al menos 8 caracteres.';
    }
    if (message.contains('network') || message.contains('socket')) {
      return 'No se pudo conectar. Revisa tu conexión a internet.';
    }
    return 'No pudimos completar la operación. Intenta nuevamente.';
  }

  Future<void> _submit() async {
    if (_loading) return;
    FocusManager.instance.primaryFocus?.unfocus();
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    final restaurant = _restaurantController.text.trim();
    if (!email.contains('@')) {
      setState(() {
        _message = 'Escribe un correo válido.';
        _messageIsError = true;
      });
      return;
    }
    if (password.length < 8) {
      setState(() {
        _message = 'La contraseña debe tener al menos 8 caracteres.';
        _messageIsError = true;
      });
      return;
    }
    if (_creatingAccount && restaurant.length < 2) {
      setState(() {
        _message = 'Escribe el nombre del restaurante.';
        _messageIsError = true;
      });
      return;
    }

    final cloud = CloudStore.instance;
    if (cloud == null) {
      setState(() {
        _message = 'La conexión con Fideli no está disponible.';
        _messageIsError = true;
      });
      return;
    }

    setState(() {
      _loading = true;
      _message = null;
    });
    try {
      if (_creatingAccount) {
        final authenticated = await cloud.registerRestaurant(
          restaurantName: restaurant,
          email: email,
          password: password,
        );
        if (!authenticated) {
          if (!mounted) return;
          setState(() {
            _creatingAccount = false;
            _message =
                'Cuenta creada. Revisa tu correo para confirmarla y luego inicia sesión.';
            _messageIsError = false;
          });
          return;
        }
      } else {
        await cloud.signInRestaurant(email: email, password: password);
      }
      await widget.onAuthenticated();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _message = _friendlyError(error);
        _messageIsError = true;
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _removeSavedAccount() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _message = null;
    });
    try {
      await CloudStore.instance?.signOutRestaurant();
      if (!mounted) return;
      setState(() => _useAnotherAccount = true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _message = _friendlyError(error);
        _messageIsError = true;
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final business = AppScope.of(context).data.business;
    final showSavedAccount =
        widget.hasSavedSession && !_useAnotherAccount && !_creatingAccount;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            _creatingAccount ? 'Crea tu cuenta' : 'Bienvenido',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontFamily: 'Poppins',
              color: Colors.white,
              fontSize: 30,
              fontWeight: FontWeight.w700,
              letterSpacing: -1,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            _creatingAccount
                ? 'Registra tu restaurante en Fideli'
                : 'Ingresa a tu espacio Fideli',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontFamily: 'Poppins',
              color: Color(0xFFEAE5ED),
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 26),
          if (showSavedAccount) ...[
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: widget.savedSessionLoading || _loading
                        ? null
                        : widget.onContinueSavedSession,
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(76),
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Color(0x99FFFFFF)),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(24),
                      ),
                      textStyle: const TextStyle(
                        fontFamily: 'Poppins',
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    child: Row(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: SizedBox.square(
                            dimension: 50,
                            child: _businessMark == null
                                ? const ColoredBox(
                                    color: Color(0xFFFCE8EB),
                                    child: Icon(
                                      Icons.storefront_rounded,
                                      color: _AuthFlowScreenState._coral,
                                      size: 26,
                                    ),
                                  )
                                : Image.memory(
                                    _businessMark!,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, _, _) => const ColoredBox(
                                      color: Color(0xFFFCE8EB),
                                      child: Icon(
                                        Icons.storefront_rounded,
                                        color: _AuthFlowScreenState._coral,
                                        size: 26,
                                      ),
                                    ),
                                  ),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Text(
                            _savedBusinessName.isNotEmpty
                                ? _savedBusinessName
                                : business.name.isEmpty
                                ? 'Cuenta guardada'
                                : business.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.left,
                            style: const TextStyle(fontSize: 16),
                          ),
                        ),
                        if (widget.savedSessionLoading)
                          const SizedBox.square(
                            dimension: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.2,
                              color: Colors.white,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                IconButton(
                  tooltip: 'Quitar cuenta guardada',
                  onPressed: widget.savedSessionLoading || _loading
                      ? null
                      : _removeSavedAccount,
                  style: IconButton.styleFrom(
                    minimumSize: const Size(54, 54),
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Color(0x99FFFFFF)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                  ),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
            const SizedBox(height: 18),
            OutlinedButton(
              onPressed: _loading
                  ? null
                  : () => setState(() {
                      _useAnotherAccount = true;
                      _message = null;
                    }),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(58),
                foregroundColor: Colors.white,
                side: const BorderSide(color: Color(0x99FFFFFF)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                ),
                textStyle: const TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
              child: const Text('Iniciar con otra cuenta'),
            ),
          ] else ...[
            if (widget.hasSavedSession &&
                _useAnotherAccount &&
                !_creatingAccount)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => setState(() {
                    _useAnotherAccount = false;
                    _message = null;
                  }),
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.white,
                    padding: EdgeInsets.zero,
                  ),
                  icon: const Icon(Icons.arrow_back_rounded, size: 18),
                  label: const Text('Volver a la cuenta guardada'),
                ),
              ),
            if (_creatingAccount) ...[
              _AuthField(
                controller: _restaurantController,
                label: 'Nombre del restaurante',
                icon: Icons.storefront_outlined,
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 13),
            ],
            _AuthField(
              controller: _emailController,
              label: 'Correo electrónico',
              icon: Icons.mail_outline_rounded,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              autocorrect: false,
            ),
            const SizedBox(height: 13),
            _AuthField(
              controller: _passwordController,
              label: 'Contraseña',
              icon: Icons.lock_outline_rounded,
              obscureText: true,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _submit(),
              autocorrect: false,
            ),
          ],
          if (_message != null) ...[
            const SizedBox(height: 12),
            Text(
              _message!,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: _messageIsError
                    ? const Color(0xFFFFD7D2)
                    : const Color(0xFFD9F7DF),
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          if (!showSavedAccount) ...[
            const SizedBox(height: 22),
            FilledButton(
              onPressed: _loading ? null : _submit,
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(58),
                backgroundColor: _AuthFlowScreenState._gold,
                foregroundColor: _AuthFlowScreenState._ink,
                disabledBackgroundColor: const Color(0x99FFFFFF),
                disabledForegroundColor: _AuthFlowScreenState._ink,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                ),
                textStyle: const TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              child: _loading
                  ? const SizedBox.square(
                      dimension: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: _AuthFlowScreenState._ink,
                      ),
                    )
                  : Text(_creatingAccount ? 'Crear cuenta' : 'Entrar a Fideli'),
            ),
          ],
          SizedBox(height: showSavedAccount ? 26 : 18),
          OutlinedButton(
            onPressed: _loading
                ? null
                : () => setState(() {
                    if (_creatingAccount) {
                      _creatingAccount = false;
                    } else if (showSavedAccount) {
                      _creatingAccount = true;
                      _useAnotherAccount = true;
                    } else {
                      _creatingAccount = false;
                      _useAnotherAccount = false;
                    }
                    _message = null;
                  }),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(56),
              foregroundColor: Colors.white,
              backgroundColor: showSavedAccount || !_creatingAccount
                  ? _AuthFlowScreenState._coral
                  : Colors.transparent,
              side: BorderSide(
                color: showSavedAccount || !_creatingAccount
                    ? _AuthFlowScreenState._coral
                    : const Color(0x99FFFFFF),
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
              ),
              textStyle: const TextStyle(
                fontFamily: 'Poppins',
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
            child: Text(
              _creatingAccount
                  ? 'Ya tengo una cuenta'
                  : 'Crear una cuenta para mi restaurante',
            ),
          ),
        ],
      ),
    );
  }
}

class _AuthField extends StatelessWidget {
  const _AuthField({
    required this.controller,
    required this.label,
    required this.icon,
    this.obscureText = false,
    this.keyboardType,
    this.textInputAction,
    this.onSubmitted,
    this.autocorrect = true,
  });

  final TextEditingController controller;
  final String label;
  final IconData icon;
  final bool obscureText;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onSubmitted;
  final bool autocorrect;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      obscureText: obscureText,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      onSubmitted: onSubmitted,
      autocorrect: autocorrect,
      enableSuggestions: !obscureText,
      style: const TextStyle(
        fontFamily: 'Poppins',
        color: _AuthFlowScreenState._ink,
        fontSize: 14,
      ),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(
          fontFamily: 'Poppins',
          color: _AuthFlowScreenState._muted,
        ),
        floatingLabelStyle: const TextStyle(
          fontFamily: 'Poppins',
          color: _AuthFlowScreenState._wine,
        ),
        prefixIcon: Icon(icon, color: _AuthFlowScreenState._wine),
        filled: true,
        fillColor: _AuthFlowScreenState._cream,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 15,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: Color(0xFFE8E6E9)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: Color(0xFFE8E6E9)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(
            color: _AuthFlowScreenState._coral,
            width: 1.5,
          ),
        ),
      ),
    );
  }
}
