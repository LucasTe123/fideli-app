import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';

import '../services/cloud_store.dart';

/// Presentación y acceso visual de Fideli.
///
/// Mantiene separadas las cuentas de los restaurantes y los clientes Wallet.
class AuthFlowScreen extends StatefulWidget {
  const AuthFlowScreen({
    super.key,
    required this.onAuthenticated,
    this.hasSavedSession = false,
  });

  final Future<void> Function() onAuthenticated;
  final bool hasSavedSession;

  @override
  State<AuthFlowScreen> createState() => _AuthFlowScreenState();
}

class _AuthFlowScreenState extends State<AuthFlowScreen>
    with TickerProviderStateMixin {
  static const _wine = Color(0xFF1D1D21);
  static const _cream = Colors.white;
  static const _gold = Color(0xFFB7B7B3);

  late final AnimationController _introController;
  late final AnimationController _transitionController;
  late final Animation<double> _introFade;
  bool _introStarted = false;
  bool _showingLogin = false;
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
    );
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
    final artworkWidth = (width * .56).clamp(560.0, 650.0).toDouble();
    final artworkHeight = artworkWidth * .83;
    final artworkLeft = _lerp(
      (width - artworkWidth) / 2,
      (width * .5 - artworkWidth) / 2,
      progress,
    );
    final brandLeft = _lerp(width * .31, width * .055, progress);
    final panelLeft = _lerp(width + 48, width * .515, panelProgress);

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned(
          left: artworkLeft,
          top: -height * .035,
          width: artworkWidth,
          height: artworkHeight,
          child: IgnorePointer(
            child: Lottie.asset(
              'assets/animations/friends_at_a_cafe.json',
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
          top: height * .58,
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Fideli',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  color: _wine,
                  fontSize: 50,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -4,
                  height: 1,
                ),
              ),
              SizedBox(height: 9),
              Text(
                'Tu lealtad lo vale.',
                style: TextStyle(
                  fontFamily: 'FideliScript',
                  color: _wine,
                  fontSize: 38,
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
                      backgroundColor: _wine,
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
          top: 24,
          bottom: 24,
          width: width * .455,
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
                child: _LoginForm(onAuthenticated: widget.onAuthenticated),
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
      backgroundColor: Colors.white,
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

                        final animationTop = _lerp(
                          -height * 0.07,
                          -height * 0.02,
                          progress,
                        );
                        final animationLeft = _lerp(
                          -width * 0.27,
                          width * 0.05,
                          progress,
                        );
                        final animationWidth = _lerp(
                          width * 1.55,
                          width * 0.90,
                          progress,
                        );
                        final animationHeight = _lerp(
                          height * 0.64,
                          height * 0.34,
                          progress,
                        );

                        final panelTop = _lerp(
                          height + 30,
                          height * 0.29,
                          panelProgress,
                        );

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
                                  'assets/animations/friends_at_a_cafe.json',
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
                              height: height * 0.78,
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
          top: height * 0.51,
          child: Text(
            'Fideli',
            style: const TextStyle(
              fontFamily: 'Poppins',
              color: _AuthFlowScreenState._wine,
              fontSize: 50,
              fontWeight: FontWeight.w800,
              letterSpacing: -4,
              height: 1,
            ),
          ),
        ),
        Positioned(
          left: width * 0.08,
          top: height * 0.58,
          child: Text(
            'Tu lealtad lo vale.',
            style: const TextStyle(
              fontFamily: 'FideliScript',
              color: _AuthFlowScreenState._wine,
              fontSize: 39,
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
              backgroundColor: _AuthFlowScreenState._wine,
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
  const _LoginForm({required this.onAuthenticated});

  final Future<void> Function() onAuthenticated;

  @override
  State<_LoginForm> createState() => _LoginFormState();
}

class _LoginFormState extends State<_LoginForm> {
  final _restaurantController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _creatingAccount = false;
  bool _loading = false;
  String? _message;
  bool _messageIsError = false;

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

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(28, 28, 28, 110),
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
              color: Color(0xFFF2DEDA),
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 24),
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
          const SizedBox(height: 22),
          FilledButton(
            onPressed: _loading ? null : _submit,
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(56),
              backgroundColor: Colors.white,
              foregroundColor: _AuthFlowScreenState._wine,
              disabledBackgroundColor: const Color(0x99FFFFFF),
              disabledForegroundColor: _AuthFlowScreenState._wine,
              textStyle: const TextStyle(
                fontFamily: 'Poppins',
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            child: _loading
                ? const SizedBox.square(
                    dimension: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: _AuthFlowScreenState._wine,
                    ),
                  )
                : Text(_creatingAccount ? 'Crear cuenta' : 'Entrar a Fideli'),
          ),
          TextButton(
            onPressed: _loading
                ? null
                : () => setState(() {
                    _creatingAccount = !_creatingAccount;
                    _message = null;
                  }),
            style: TextButton.styleFrom(foregroundColor: Colors.white),
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
        color: Color(0xFF2F201E),
        fontSize: 14,
      ),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(
          fontFamily: 'Poppins',
          color: Color(0xFF5F514F),
        ),
        floatingLabelStyle: const TextStyle(
          fontFamily: 'Poppins',
          color: _AuthFlowScreenState._wine,
        ),
        prefixIcon: Icon(icon, color: const Color(0xFF5F514F)),
        filled: true,
        fillColor: _AuthFlowScreenState._cream,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 15,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: Color(0xFFE1D8CE)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: Color(0xFFE1D8CE)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(
            color: _AuthFlowScreenState._wine,
            width: 1.5,
          ),
        ),
      ),
    );
  }
}
