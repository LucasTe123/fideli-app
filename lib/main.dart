import 'package:flutter/material.dart';

import 'screens/navigation_menu_screen.dart';
import 'screens/escena_cafe_screen.dart';
import 'screens/auth_flow_screen.dart';
import 'screens/storefront_screen.dart';
import 'services/cloud_store.dart';
import 'state/app_scope.dart';
import 'state/app_state.dart';
import 'theme/fideli_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const FideliBootstrap());
}

class FideliBootstrap extends StatefulWidget {
  const FideliBootstrap({super.key});

  @override
  State<FideliBootstrap> createState() => _FideliBootstrapState();
}

class _FideliBootstrapState extends State<FideliBootstrap> {
  late final Future<void> _cloudStartup = CloudStore.initialize();
  late Future<AppState> _startup = AppState.load();

  void _retry() {
    setState(() => _startup = AppState.load());
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<AppState>(
      future: _startup,
      builder: (context, snapshot) {
        if (snapshot.hasData) {
          return FideliApp(
            state: snapshot.requireData,
            cloudReady: _cloudStartup,
          );
        }
        return MaterialApp(
          title: 'Fideli',
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xFF9E483F),
            ),
            scaffoldBackgroundColor: Colors.white,
            useMaterial3: true,
          ),
          home: Scaffold(
            body: Center(
              child: snapshot.hasError
                  ? Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          'No se pudo abrir Fideli',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 14),
                        FilledButton(
                          onPressed: _retry,
                          child: const Text('Reintentar'),
                        ),
                      ],
                    )
                  : const Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Fideli',
                          style: TextStyle(
                            fontSize: 34,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        SizedBox(height: 24),
                        CircularProgressIndicator(),
                        SizedBox(height: 14),
                        Text('Abriendo tu espacio…'),
                      ],
                    ),
            ),
          ),
        );
      },
    );
  }
}

class FideliApp extends StatefulWidget {
  const FideliApp({super.key, required this.state, this.cloudReady});
  final AppState state;
  final Future<void>? cloudReady;

  @override
  State<FideliApp> createState() => _FideliAppState();
}

class _FideliAppState extends State<FideliApp> {
  late AppState _state = widget.state;
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();
  late final Future<void> _cloudReady =
      widget.cloudReady ?? Future<void>.value();
  bool _accessGranted = false;
  String? get _publicStoreSlug {
    final value = Uri.base.queryParameters['tienda']?.trim();
    return value == null || value.isEmpty ? null : value;
  }

  @override
  void initState() {
    super.initState();
    _cloudReady.whenComplete(() {
      if (mounted) setState(() {});
    });
  }

  Future<void> _authenticated() async {
    await _cloudReady;
    final cloud = CloudStore.instance;
    if (cloud == null || !cloud.hasRestaurantSession) {
      throw StateError('No se pudo iniciar la sesión del restaurante.');
    }
    final nextState = await AppState.load(cloudStore: cloud);
    if (!mounted) {
      nextState.dispose();
      return;
    }
    final previousState = _state;
    setState(() {
      _state = nextState;
      _accessGranted = true;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!identical(previousState, _state)) previousState.dispose();
    });
  }

  Future<void> _signOut() async {
    // Retira primero cualquier ruta secundaria que todavía dependa del estado
    // autenticado. Así el AppScope nunca cambia con un diálogo vivo encima.
    _navigatorKey.currentState?.popUntil((route) => route.isFirst);
    await WidgetsBinding.instance.endOfFrame;
    final cloud = CloudStore.instance;
    await cloud?.signOutRestaurant();
    final nextState = await AppState.load();
    if (!mounted) {
      nextState.dispose();
      return;
    }
    final previousState = _state;
    setState(() {
      _state = nextState;
      _accessGranted = false;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!identical(previousState, _state)) previousState.dispose();
    });
  }

  @override
  Widget build(BuildContext context) {
    return AppScope(
      state: _state,
      child: MaterialApp(
        navigatorKey: _navigatorKey,
        title: 'Fideli',
        debugShowCheckedModeBanner: false,
        builder: (context, child) {
          if (MediaQuery.sizeOf(context).width < 900 || child == null) {
            return child ?? const SizedBox.shrink();
          }
          final theme = Theme.of(context);
          return Theme(
            data: theme.copyWith(
              visualDensity: const VisualDensity(horizontal: -1, vertical: -1),
              iconTheme: theme.iconTheme.copyWith(size: 20),
            ),
            child: child,
          );
        },
        theme: FideliTheme.light(),
        // El AnimatedSwitcher mantenía al mismo tiempo la pantalla anterior y
        // la nueva, aunque ya pertenecían a AppState distintos. En Web eso
        // terminaba desmontando un InheritedWidget con dependientes activos.
        home: _publicStoreSlug != null
            ? FutureBuilder<void>(
                future: _cloudReady,
                builder: (context, snapshot) =>
                    snapshot.connectionState == ConnectionState.done
                    ? PublicStorefrontScreen(slug: _publicStoreSlug!)
                    : const Scaffold(
                        body: Center(child: CircularProgressIndicator()),
                      ),
              )
            : !_accessGranted
            ? AuthFlowScreen(
                hasSavedSession:
                    CloudStore.instance?.hasRestaurantSession == true,
                onAuthenticated: _authenticated,
              )
            : _state.data.business.onboarded
            ? NavigationMenuScreen(onSignOut: _signOut)
            : EscenaCafeScreen(
                onCompleted: () {
                  if (mounted) setState(() {});
                },
              ),
      ),
    );
  }
}
