import 'dart:async';
import 'dart:convert';

import 'package:fideli/main.dart';
import 'package:fideli/config/supabase_config.dart';
import 'package:fideli/models/app_data.dart';
import 'package:fideli/models/customer_intelligence.dart';
import 'package:fideli/services/local_store.dart';
import 'package:fideli/services/wallet_service.dart';
import 'package:fideli/screens/auth_flow_screen.dart';
import 'package:fideli/screens/business_screen.dart';
import 'package:fideli/screens/campaigns_screen.dart';
import 'package:fideli/screens/customers_screen.dart';
import 'package:fideli/screens/dashboard_screen.dart';
import 'package:fideli/screens/navigation_menu_screen.dart';
import 'package:fideli/screens/programs_screen.dart';
import 'package:fideli/screens/wallet_studio_screen.dart';
import 'package:fideli/state/app_scope.dart';
import 'package:fideli/state/app_state.dart';
import 'package:fideli/theme/fideli_theme.dart';
import 'package:fideli/widgets/common.dart';
import 'package:fideli/widgets/scanner_action_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('el enlace compartido abre la tienda pública del slug', () {
    final uri = SupabaseConfig.publicClubUriForBusiness(
      'business-id',
      publicSlug: 'cafe-del-centro',
    );

    expect(uri.origin, 'https://fideli.site');
    expect(uri.path, '/');
    expect(uri.queryParameters, {'tienda': 'cafe-del-centro'});
  });

  test('Poppins es la tipografía global de la aplicación', () {
    final theme = FideliTheme.light();

    expect(theme.textTheme.bodyMedium?.fontFamily, 'Poppins');
    expect(theme.textTheme.titleMedium?.fontFamily, 'Poppins');
    expect(theme.textTheme.labelLarge?.fontFamily, 'Poppins');
    expect(theme.scaffoldBackgroundColor, Colors.white);
  });

  testWidgets('los mensajes visibles no exponen el proveedor de datos', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showMessage(
              context,
              'Supabase respondió con un error de PostgREST',
            ),
            child: const Text('Mostrar'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Mostrar'));
    await tester.pump();

    expect(find.textContaining('Supabase'), findsNothing);
    expect(find.textContaining('PostgREST'), findsNothing);
    expect(
      find.text('No se pudo completar. Revisa tu conexión.'),
      findsOneWidget,
    );
  });

  test(
    'una respuesta remota antigua no revive un elemento eliminado',
    () async {
      final pendingLoad = Completer<AppData?>();
      final local = AppData.initial()
        ..campaigns.add(
          Campaign(id: 'campaign-race', name: 'Vieja', message: 'Mensaje'),
        );
      final state = AppState(
        LocalStore(),
        local,
        cloudDataLoader: () => pendingLoad.future,
      );

      final refresh = state.refreshFromCloud();
      await Future<void>.delayed(Duration.zero);
      state.data.campaigns.clear();
      await state.commitLocalOnly();

      final staleRemote = AppData.initial()
        ..campaigns.add(
          Campaign(id: 'campaign-race', name: 'Vieja', message: 'Mensaje'),
        );
      pendingLoad.complete(staleRemote);

      expect(await refresh, isFalse);
      expect(state.data.campaigns, isEmpty);
    },
  );

  testWidgets('muestra la bienvenida visual al iniciar', (tester) async {
    final state = AppState(LocalStore(), AppData.initial());
    await tester.pumpWidget(FideliApp(state: state));
    await tester.pump();
    expect(find.text('Fideli'), findsOneWidget);
    expect(find.text('Tu lealtad lo vale.'), findsOneWidget);
    expect(find.text('Iniciar sesión'), findsOneWidget);

    await tester.tap(find.text('Iniciar sesión'));
    await tester.pump(const Duration(milliseconds: 1200));
    expect(find.text('Correo electrónico'), findsOneWidget);
    expect(find.text('Contraseña'), findsOneWidget);
    expect(find.text('Código del comercio'), findsNothing);
    expect(
      find.text('Pantalla de prueba · todavía sin autenticación'),
      findsNothing,
    );
    expect(find.text('Crear una cuenta para mi restaurante'), findsOneWidget);
  });

  testWidgets('una sesión guardada muestra Entrar y abre el dashboard', (
    tester,
  ) async {
    var entered = false;
    await tester.pumpWidget(
      MaterialApp(
        home: AuthFlowScreen(
          hasSavedSession: true,
          onAuthenticated: () async => entered = true,
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Entrar'), findsOneWidget);
    expect(find.text('Iniciar sesión'), findsNothing);

    await tester.tap(find.text('Entrar'));
    await tester.pump();
    expect(entered, isTrue);
  });

  testWidgets('el acceso de escritorio conserva la marca junto al formulario', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(home: AuthFlowScreen(onAuthenticated: () async {})),
    );
    await tester.pump();
    await tester.tap(find.text('Iniciar sesión'));
    await tester.pump(const Duration(milliseconds: 1200));

    expect(find.text('Fideli'), findsOneWidget);
    expect(find.text('Tu lealtad lo vale.'), findsOneWidget);
    expect(find.byKey(const ValueKey('desktop-login-panel')), findsOneWidget);
    expect(find.text('Correo electrónico'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('alta, sellos, visitas y canje forman un flujo coherente', () async {
    final data = AppData.initial();
    data.programs.add(
      LoyaltyProgram(
        id: 'program-points',
        name: 'Club principal',
        type: ProgramType.stamps,
        goal: 7,
      ),
    );
    data.rewards.add(
      Reward(
        id: 'reward-welcome',
        programId: 'program-points',
        name: 'Producto de cortesía',
        stampsCost: 7,
      ),
    );
    final state = AppState(LocalStore(), data);
    final ana = state.addCustomer(name: 'Ana');
    await state.commit();
    final bob = state.addCustomer(name: 'Bob', referredBy: ana.referralCode);
    await state.commit();

    expect(ana.points, 50);
    expect(ana.balanceFor('program-points').points, 50);
    expect(bob.points, 0);

    for (var index = 0; index < 7; index++) {
      await state.registerStampVisit(bob.id);
    }
    await state.commit();
    expect(bob.stamps, 7);
    expect(bob.visits, 7);

    final redeemed = state.redeemReward(bob.id, 'reward-welcome');
    await state.commit();
    expect(redeemed, isTrue);
    expect(bob.stamps, 0);
    expect(state.data.rewards.first.redemptions, 1);
  });

  test('una tarjeta de 8 sellos desbloquea el premio intermedio', () async {
    final data = AppData.initial();
    final program = LoyaltyProgram(
      id: 'program-eight',
      name: 'Club de ocho',
      type: ProgramType.stamps,
      goal: 8,
      stampMilestones: [
        StampMilestone(
          id: 'reward-three',
          stamp: 3,
          reward: 'Bebida gratis',
          message: 'Ganaste una bebida',
        ),
        StampMilestone(
          id: 'reward-eight',
          stamp: 8,
          reward: 'Premio final',
          message: 'Completaste la tarjeta',
        ),
      ],
    );
    data.programs.add(program);
    data.rewards.addAll([
      Reward(
        id: 'reward-three',
        programId: program.id,
        name: 'Bebida gratis',
        stampsCost: 3,
      ),
      Reward(
        id: 'reward-eight',
        programId: program.id,
        name: 'Premio final',
        stampsCost: 8,
      ),
    ]);
    final customer = Customer(
      id: 'customer-eight',
      name: 'Ana',
      referralCode: 'ANA8000',
      joinedAt: DateTime(2026),
      cardBalances: {program.id: CardBalance()},
    );
    data.customers.add(customer);
    final state = AppState(LocalStore(), data);

    await state.adjustCardValue(
      customer.id,
      program.id,
      delta: 4,
      description: 'Sellos enviados',
    );

    expect(program.goal, 8);
    expect(customer.balanceFor(program.id).stamps, 4);
    expect(customer.unlockedRewardIds, contains('reward-three'));
    expect(customer.unlockedRewardIds, isNot(contains('reward-eight')));

    expect(state.redeemReward(customer.id, 'reward-three'), isTrue);
    expect(customer.balanceFor(program.id).stamps, 4);
    expect(state.canRedeemReward(customer.id, 'reward-three'), isFalse);
  });

  test(
    'la actualización Wallet conserva el valor anterior del programa',
    () async {
      Map<String, dynamic>? submitted;
      final service = WalletService(
        client: MockClient((request) async {
          submitted = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response(
            jsonEncode({'ok': true, 'queuedPasses': 1}),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );
      final customer = Customer(
        id: 'customer-notification',
        name: 'Ana',
        referralCode: 'ANA4000',
        joinedAt: DateTime(2026),
        cardBalances: {'program-ten': CardBalance(stamps: 4)},
      );

      final result = await service.syncCustomer(
        BusinessProfile(name: 'Culina'),
        customer,
        programId: 'program-ten',
        previousProgramValue: 3,
      );

      expect(result.ok, isTrue);
      expect(submitted?['programId'], 'program-ten');
      expect(submitted?['previousProgramValue'], 3);
    },
  );

  test('una cuenta nueva empieza sin programas ni recompensas ajenas', () {
    final data = AppData.initial();

    expect(data.programs, isEmpty);
    expect(data.rewards, isEmpty);
  });

  test('el almacenamiento local queda aislado por cuenta', () async {
    final first = AppData.initial();
    first.programs.add(
      LoyaltyProgram(
        id: 'padelbo-program',
        name: 'Club PadelBo',
        type: ProgramType.stamps,
      ),
    );
    await LocalStore(namespace: 'account-padelbo').save(first);

    final other = await LocalStore(namespace: 'account-nueva').load();

    expect(other.programs, isEmpty);
  });

  test('cada cliente solo muestra los programas donde está inscrito', () {
    final data = AppData.initial();
    data.programs.add(
      LoyaltyProgram(
        id: 'program-secondary',
        name: 'Club secundario',
        type: ProgramType.points,
      ),
    );
    final customer = Customer(
      id: 'customer-one',
      name: 'Ana',
      referralCode: 'ANA1234',
      joinedAt: DateTime(2026),
      cardBalances: {'program-secondary': CardBalance()},
    );

    final programs = data.activeProgramsForCustomer(customer);

    expect(programs.map((item) => item.id), ['program-secondary']);
  });

  testWidgets('Mi negocio no muestra color hexadecimal ni sucursales', (
    tester,
  ) async {
    final state = AppState(LocalStore(), AppData.initial());
    await tester.pumpWidget(
      AppScope(
        state: state,
        child: const MaterialApp(home: Scaffold(body: BusinessScreen())),
      ),
    );
    await tester.pump();
    expect(find.text('Color hexadecimal'), findsNothing);
    expect(find.text('Sucursales'), findsNothing);
    expect(find.text('Agregar sucursal'), findsNothing);
  });

  testWidgets('Mi negocio separa la vista previa del editor en escritorio', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final state = AppState(LocalStore(), AppData.initial());
    await tester.pumpWidget(
      AppScope(
        state: state,
        child: const MaterialApp(home: Scaffold(body: BusinessScreen())),
      ),
    );
    await tester.pump();

    final preview = tester.getRect(find.text('Vista previa'));
    final editor = tester.getRect(find.text('Datos del negocio'));
    expect(preview.left, lessThan(editor.left));
    expect((preview.top - editor.top).abs(), lessThan(260));
    expect(tester.takeException(), isNull);
  });

  testWidgets('el dashboard profesional cabe en una pantalla de iPhone', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final state = AppState(LocalStore(), AppData.initial());
    await tester.pumpWidget(
      AppScope(
        state: state,
        child: MaterialApp(
          home: Scaffold(
            body: DashboardScreen(
              onProgramsPressed: (_) {},
              onCustomersPressed: (_) {},
              onCampaignsPressed: (_) {},
              onBusinessPressed: (_) {},
              onSharePressed: (_) {},
              onWalletPressed: (_) {},
              onSignOut: () async {},
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 1200));
    expect(find.text('Programa\nde fidelidad'), findsOneWidget);
    expect(find.text('Mi\nnegocio'), findsOneWidget);
    expect(find.text('Wallet\nStudio'), findsOneWidget);
    expect(find.text('Compartir\nnegocio'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('el dashboard de escritorio no usa scroll interior', (
    tester,
  ) async {
    var scannerOpened = false;
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final state = AppState(LocalStore(), AppData.initial());
    await tester.pumpWidget(
      AppScope(
        state: state,
        child: MaterialApp(
          home: Scaffold(
            body: DashboardScreen(
              onProgramsPressed: (_) {},
              onCustomersPressed: (_) {},
              onCampaignsPressed: (_) {},
              onBusinessPressed: (_) {},
              onSharePressed: (_) {},
              onWalletPressed: (_) {},
              onScanPressed: (_) => scannerOpened = true,
              onSignOut: () async {},
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 1200));

    expect(find.byType(SingleChildScrollView), findsNothing);
    expect(find.byType(BackdropFilter), findsNothing);
    expect(find.text('ACCESOS RÁPIDOS'), findsNothing);
    expect(
      find.byKey(const ValueKey('studio-fideli-sidebar-logo')),
      findsOneWidget,
    );
    expect(find.text('Compartir\nnegocio'), findsOneWidget);
    expect(find.text('Crear tarjeta'), findsOneWidget);
    expect(find.text('Escanear cliente'), findsOneWidget);
    expect(find.text('Programa de fidelidad'), findsNothing);
    expect(find.text('Tu negocio'), findsOneWidget);
    expect(find.text('Sellos, puntos y beneficios'), findsNothing);
    expect(find.text('Atiende y acompaña'), findsNothing);
    expect(find.text('Habla con tus clientes'), findsNothing);
    expect(find.text('Personaliza tus tarjetas'), findsNothing);
    expect(find.text('Invita a nuevos clientes'), findsNothing);
    expect(find.text('Perfil, logo y datos'), findsNothing);
    expect(find.text('GESTIONA'), findsNothing);
    expect(find.text('CONOCE'), findsNothing);
    expect(find.text('COMUNICA'), findsNothing);
    expect(find.text('DISEÑA'), findsNothing);
    expect(find.text('COMPARTE'), findsNothing);
    expect(find.text('CONFIGURA'), findsNothing);
    final flatCard = tester.widget<AnimatedContainer>(
      find.byKey(const ValueKey('dashboard-module-programs')),
    );
    final flatDecoration = flatCard.decoration! as BoxDecoration;
    expect(flatDecoration.border, isNull);
    expect(flatDecoration.boxShadow, isNull);
    await tester.tap(find.text('Escanear cliente'));
    expect(scannerOpened, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('el detalle del cliente se abre como panel lateral', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final data = AppData.initial();
    data.customers.add(
      Customer(
        id: 'panel-customer',
        name: 'Lucas Tejerina',
        phone: '76543210',
        email: 'lucas@example.com',
        referralCode: 'LUCAS01',
        joinedAt: DateTime(2026),
      ),
    );
    final state = AppState(LocalStore(), data);

    await tester.pumpWidget(
      AppScope(
        state: state,
        child: const MaterialApp(home: Scaffold(body: CustomersScreen())),
      ),
    );
    await tester.pump();
    await tester.tap(find.text('Lucas Tejerina'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));

    expect(find.byKey(const ValueKey('customer-side-panel')), findsOneWidget);
    expect(find.byTooltip('Cerrar'), findsOneWidget);
    expect(find.text('TARJETAS DEL CLIENTE'), findsOneWidget);
    expect(find.text('RECOMPENSAS'), findsOneWidget);
    expect(find.text('HISTORIAL'), findsOneWidget);

    await tester.tap(find.byTooltip('Cerrar'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('customer-side-panel')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('el acceso rápido de tarjeta abre directamente el creador', (
    tester,
  ) async {
    final state = AppState(LocalStore(), AppData.initial());
    await tester.pumpWidget(
      AppScope(
        state: state,
        child: const MaterialApp(
          home: ProgramsScreen(openCreatorOnStart: true),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Configura solo lo necesario'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('el acceso rápido de campaña abre directamente el editor', (
    tester,
  ) async {
    final state = AppState(LocalStore(), AppData.initial());
    await tester.pumpWidget(
      AppScope(
        state: state,
        child: const MaterialApp(
          home: CampaignsScreen(openComposerOnStart: true),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Guardar y enviar'), findsOneWidget);
    expect(find.text('Título de la notificación'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('campaign-notification-title')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('el acceso rápido puede abrir y cerrar sin romper dependencias', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final state = AppState(LocalStore(), AppData.initial());
    await tester.pumpWidget(
      AppScope(
        state: state,
        child: MaterialApp(home: NavigationMenuScreen(onSignOut: () async {})),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Crear tarjeta'));
    await tester.pumpAndSettle();
    expect(find.text('Configura solo lo necesario'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Volver al Dashboard'));
    await tester.pumpAndSettle();

    expect(find.text('Crear tarjeta'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('el avatar abre el menú de cuenta y permite cerrar sesión', (
    tester,
  ) async {
    var signedOut = false;
    final data = AppData.initial();
    data.business.name = 'Culina Coffee';
    final state = AppState(LocalStore(), data);
    await tester.pumpWidget(
      AppScope(
        state: state,
        child: MaterialApp(
          home: Scaffold(
            body: DashboardScreen(
              onProgramsPressed: (_) {},
              onCustomersPressed: (_) {},
              onCampaignsPressed: (_) {},
              onBusinessPressed: (_) {},
              onSharePressed: (_) {},
              onWalletPressed: (_) {},
              onSignOut: () async => signedOut = true,
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 1200));

    await tester.tap(find.byTooltip('Mi cuenta'));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Culina Coffee'), findsOneWidget);
    expect(find.text('Cerrar sesión'), findsOneWidget);

    await tester.tap(find.text('Cerrar sesión'));
    await tester.pump(const Duration(milliseconds: 500));
    expect(signedOut, isTrue);
  });

  testWidgets('el botón QR abre y cierra su ruta sin romper dependencias', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          floatingActionButton: ScannerActionButton(
            scannerBuilder: (_) => const Center(child: Text('Cámara lista')),
          ),
        ),
      ),
    );

    await tester.tap(find.byTooltip('Escanear QR de cliente'));
    await tester.pumpAndSettle();
    expect(find.text('Cámara lista'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byTooltip('Volver'));
    await tester.pumpAndSettle();
    expect(find.text('Cámara lista'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('eliminar un programa cierra el editor antes de actualizar', (
    tester,
  ) async {
    final data = AppData.initial();
    data.programs.add(
      LoyaltyProgram(
        id: 'delete-program',
        name: 'Programa temporal',
        type: ProgramType.stamps,
        goal: 8,
      ),
    );
    data.rewards.add(
      Reward(
        id: 'delete-reward',
        name: 'Premio temporal',
        programId: 'delete-program',
        stampsCost: 8,
      ),
    );
    data.customers.add(
      Customer(
        id: 'delete-customer',
        name: 'Cliente temporal',
        referralCode: 'DELETE1',
        joinedAt: DateTime(2026),
        unlockedRewardIds: const ['delete-reward'],
        redeemedRewardIds: const ['delete-reward'],
        cardBalances: {'delete-program': CardBalance(stamps: 8)},
      ),
    );
    final state = AppState(LocalStore(), data);
    final wallet = WalletService(
      client: MockClient(
        (_) async => http.Response(
          jsonEncode({'ok': true, 'message': 'Programa eliminado'}),
          200,
          headers: {'content-type': 'application/json'},
        ),
      ),
    );
    await tester.pumpWidget(
      AppScope(
        state: state,
        child: MaterialApp(home: ProgramsScreen(walletService: wallet)),
      ),
    );

    await tester.tap(find.text('Programa temporal'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Eliminar programa'));
    await tester.tap(find.text('Eliminar programa'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Borrar tarjeta'));
    await tester.pump(const Duration(milliseconds: 900));

    expect(state.data.programs, isEmpty);
    expect(state.data.rewards, isEmpty);
    expect(state.data.customers.single.unlockedRewardIds, isEmpty);
    expect(state.data.customers.single.redeemedRewardIds, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'activar una tarjeta no se revierte si Wallet está desconectado',
    (tester) async {
      final data = AppData.initial();
      final program = LoyaltyProgram(
        id: 'toggle-program',
        name: 'Tarjeta para activar',
        type: ProgramType.stamps,
        goal: 8,
        active: false,
      );
      data.programs.add(program);
      final state = AppState(LocalStore(), data);
      final wallet = WalletService(
        client: MockClient(
          (_) async => http.Response(
            jsonEncode({'message': 'Wallet no disponible'}),
            503,
            headers: {'content-type': 'application/json'},
          ),
        ),
      );
      await tester.pumpWidget(
        AppScope(
          state: state,
          child: MaterialApp(home: ProgramsScreen(walletService: wallet)),
        ),
      );

      await tester.tap(find.byType(Switch).first);
      await tester.pumpAndSettle();

      expect(program.active, isTrue);
      expect(tester.widget<Switch>(find.byType(Switch).first).value, isTrue);
      expect(find.textContaining('Tarjeta activada'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('editar un programa sin cambios no llama a Wallet', (
    tester,
  ) async {
    var requests = 0;
    final data = AppData.initial();
    final program = LoyaltyProgram(
      id: 'unchanged-program',
      name: 'Tarjeta sin cambios',
      type: ProgramType.stamps,
      goal: 10,
      stampMilestones: [
        StampMilestone(
          id: 'final-reward',
          stamp: 10,
          reward: 'Producto de cortesía',
          message: '🎉 ¡Completaste tu tarjeta! Tu recompensa está lista.',
        ),
      ],
    );
    data.programs.add(program);
    data.rewards.add(
      Reward(
        id: 'final-reward',
        programId: program.id,
        name: 'Producto de cortesía',
        stampsCost: 10,
      ),
    );
    final state = AppState(LocalStore(), data);
    final wallet = WalletService(
      client: MockClient((_) async {
        requests++;
        return http.Response('{}', 200);
      }),
    );
    await tester.pumpWidget(
      AppScope(
        state: state,
        child: MaterialApp(home: ProgramsScreen(walletService: wallet)),
      ),
    );

    await tester.tap(find.text('Tarjeta sin cambios'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.check_rounded));
    await tester.pumpAndSettle();

    expect(requests, 0);
    expect(find.text('No hay cambios para guardar'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('tocar fuera cierra el editor de programas', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final data = AppData.initial();
    data.programs.add(
      LoyaltyProgram(
        id: 'dismiss-program',
        name: 'Programa descartable',
        type: ProgramType.stamps,
      ),
    );
    final state = AppState(LocalStore(), data);
    await tester.pumpWidget(
      AppScope(
        state: state,
        child: const MaterialApp(home: ProgramsScreen()),
      ),
    );

    await tester.tap(find.text('Programa descartable'));
    await tester.pumpAndSettle();
    expect(find.text('Editar tarjeta'), findsOneWidget);
    await tester.tapAt(const Offset(8, 8));
    await tester.pumpAndSettle();

    expect(find.text('Editar tarjeta'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('editar una campaña sin cambios no altera el borrador', (
    tester,
  ) async {
    final sentAt = DateTime.utc(2026, 10, 10, 12);
    final campaign = Campaign(
      id: 'unchanged-campaign',
      name: 'Campaña sin cambios',
      message: 'Mensaje original',
      sentAt: sentAt,
    );
    final data = AppData.initial()..campaigns.add(campaign);
    final state = AppState(LocalStore(), data);
    await tester.pumpWidget(
      AppScope(
        state: state,
        child: const MaterialApp(home: CampaignsScreen()),
      ),
    );

    await tester.tap(find.text('Campaña sin cambios'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Guardar borrador'));
    await tester.pumpAndSettle();

    expect(campaign.sentAt, sentAt);
    expect(find.text('No hay cambios para guardar'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('editar el título de campaña cierra el formulario sin errores', (
    tester,
  ) async {
    final campaign = Campaign(
      id: 'custom-title-campaign',
      name: 'Campaña de temporada',
      message: 'Mensaje original',
    );
    final data = AppData.initial()..campaigns.add(campaign);
    final state = AppState(LocalStore(), data);
    await tester.pumpWidget(
      AppScope(
        state: state,
        child: const MaterialApp(home: CampaignsScreen()),
      ),
    );

    await tester.tap(find.text('Campaña de temporada'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('campaign-notification-title')),
      'Día de la Madre',
    );
    await tester.tap(find.byTooltip('Guardar borrador'));
    await tester.pumpAndSettle();

    expect(campaign.notificationTitle, 'Día de la Madre');
    expect(tester.takeException(), isNull);
  });

  testWidgets('guardar y enviar conserva el título personalizado', (
    tester,
  ) async {
    final requests = <({String path, Map<String, dynamic> body})>[];
    final client = MockClient((request) async {
      requests.add((
        path: request.url.path,
        body: jsonDecode(request.body) as Map<String, dynamic>,
      ));
      return http.Response(
        jsonEncode({'ok': true, 'targetedCustomers': 1, 'queuedPasses': 1}),
        200,
      );
    });
    final campaign = Campaign(
      id: 'send-custom-title',
      name: 'Campaña especial',
      message: 'Mensaje original',
    );
    final data = AppData.initial()..campaigns.add(campaign);
    final state = AppState(LocalStore(), data);
    await tester.pumpWidget(
      AppScope(
        state: state,
        child: MaterialApp(
          home: CampaignsScreen(walletService: WalletService(client: client)),
        ),
      ),
    );

    await tester.tap(find.text('Campaña especial'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('campaign-notification-title')),
      'Día de la Madre',
    );
    await tester.ensureVisible(find.text('Guardar y enviar'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Guardar y enviar'));
    await tester.pumpAndSettle();

    expect(campaign.notificationTitle, 'Día de la Madre');
    expect(requests, isNotEmpty);
    expect(requests.first.path, endsWith('/api/campaigns/send'));
    expect(requests.first.body['notificationTitle'], 'Día de la Madre');
    expect(campaign.sentAt, isNotNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('el nombre y el título de notificación permanecen separados', (
    tester,
  ) async {
    Map<String, dynamic>? sentBody;
    final client = MockClient((request) async {
      sentBody = jsonDecode(request.body) as Map<String, dynamic>;
      return http.Response(
        jsonEncode({'ok': true, 'targetedCustomers': 1, 'queuedPasses': 1}),
        200,
      );
    });
    final campaign = Campaign(
      id: 'name-as-title',
      name: 'Día de Santa Cruz',
      notificationTitle: 'Oferta cruceña',
      message: 'Feliz día cruceño',
    );
    final state = AppState(
      LocalStore(),
      AppData.initial()..campaigns.add(campaign),
    );
    await tester.pumpWidget(
      AppScope(
        state: state,
        child: MaterialApp(
          home: CampaignsScreen(walletService: WalletService(client: client)),
        ),
      ),
    );

    await tester.tap(find.text('Día de Santa Cruz'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('campaign-name')),
      'Nombre interno de campaña',
    );
    await tester.tap(find.byTooltip('Guardar borrador'));
    await tester.pumpAndSettle();

    expect(campaign.name, 'Nombre interno de campaña');
    expect(campaign.notificationTitle, 'Oferta cruceña');

    await tester.tap(find.text('Enviar'));
    await tester.pumpAndSettle();

    expect(campaign.name, 'Nombre interno de campaña');
    expect(campaign.notificationTitle, 'Oferta cruceña');
    expect(sentBody?['campaignName'], 'Nombre interno de campaña');
    expect(sentBody?['notificationTitle'], 'Oferta cruceña');
    expect(tester.takeException(), isNull);
  });

  testWidgets('crear una membresía asigna nombre automático y la guarda', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final state = AppState(LocalStore(), AppData.initial());
    final wallet = WalletService(
      client: MockClient(
        (_) async => http.Response(
          jsonEncode({'ok': true, 'affectedPasses': 0}),
          200,
          headers: {'content-type': 'application/json'},
        ),
      ),
    );
    await tester.pumpWidget(
      AppScope(
        state: state,
        child: MaterialApp(home: ProgramsScreen(walletService: wallet)),
      ),
    );

    await tester.tap(find.text('Nueva tarjeta'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Membresía').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.check_rounded));
    await tester.pumpAndSettle();

    expect(state.data.programs, hasLength(1));
    expect(state.data.programs.single.name, 'Membresía');
    expect(state.data.programs.single.type, ProgramType.membership);
    expect(state.data.programs.single.cardKind, 'Membresía');
    expect(find.text('QR'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('el comercio puede compartir el QR de cualquier tarjeta', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final data = AppData.initial();
    data.programs.addAll([
      LoyaltyProgram(
        id: 'stamps-share',
        name: 'Sellos',
        type: ProgramType.stamps,
      ),
      LoyaltyProgram(
        id: 'gift-share',
        name: 'Regalo',
        type: ProgramType.points,
        cardKind: 'Tarjeta de regalo',
      ),
      LoyaltyProgram(
        id: 'membership-share',
        name: 'Membresía',
        type: ProgramType.membership,
        cardKind: 'Membresía',
      ),
    ]);

    await tester.pumpWidget(
      AppScope(
        state: AppState(LocalStore(), data),
        child: const MaterialApp(home: ProgramsScreen()),
      ),
    );
    await tester.pump();

    expect(find.text('QR'), findsNWidgets(3));
    expect(tester.takeException(), isNull);
  });

  testWidgets('cargar saldo cierra el diálogo antes de actualizar la tarjeta', (
    tester,
  ) async {
    Map<String, dynamic>? submitted;
    Uri? submittedUri;
    final data = AppData.initial();
    final program = LoyaltyProgram(
      id: 'gift-balance',
      name: 'Regalo',
      type: ProgramType.points,
      cardKind: 'Tarjeta de regalo',
    );
    final customer = Customer(
      id: 'gift-customer',
      name: 'Ana',
      referralCode: 'ANA1234',
      joinedAt: DateTime(2026),
      cardBalances: {program.id: CardBalance()},
    );
    data.programs.add(program);
    data.customers.add(customer);
    final state = AppState(LocalStore(), data);
    final wallet = WalletService(
      client: MockClient((request) async {
        submittedUri = request.url;
        submitted = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(
          jsonEncode({'ok': true, 'value': 25, 'queuedPasses': 1}),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );

    await tester.pumpWidget(
      AppScope(
        state: state,
        child: MaterialApp(
          home: CustomerServiceScreen(
            customerId: customer.id,
            programId: program.id,
            walletService: wallet,
          ),
        ),
      ),
    );

    await tester.tap(find.text('Cargar saldo'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '25');
    await tester.tap(find.text('Confirmar'));
    await tester.pump(const Duration(milliseconds: 900));

    expect(customer.balanceFor(program.id).points, 25);
    expect(submittedUri?.path, endsWith('/gift-customer/card-balance'));
    expect(submitted?['programId'], program.id);
    expect(submitted?['value'], 25);
    expect(submitted?['previousValue'], 0);
    expect(find.text('Saldo disponible: Bs 25'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('si el servidor rechaza el saldo se restaura el valor anterior', (
    tester,
  ) async {
    final data = AppData.initial();
    final program = LoyaltyProgram(
      id: 'gift-failed',
      name: 'Regalo',
      type: ProgramType.points,
      cardKind: 'Tarjeta de regalo',
    );
    final customer = Customer(
      id: 'gift-failed-customer',
      name: 'Ana',
      referralCode: 'ANA0001',
      joinedAt: DateTime(2026),
      cardBalances: {program.id: CardBalance(points: 10)},
    )..points = 10;
    data.programs.add(program);
    data.customers.add(customer);
    final state = AppState(LocalStore(), data);
    final wallet = WalletService(
      client: MockClient(
        (_) async => http.Response(
          jsonEncode({'message': 'No se pudo guardar'}),
          500,
          headers: {'content-type': 'application/json'},
        ),
      ),
    );

    await tester.pumpWidget(
      AppScope(
        state: state,
        child: MaterialApp(
          home: CustomerServiceScreen(
            customerId: customer.id,
            programId: program.id,
            walletService: wallet,
          ),
        ),
      ),
    );
    await tester.tap(find.text('Cargar saldo'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '5');
    await tester.tap(find.text('Confirmar'));
    await tester.pump(const Duration(milliseconds: 900));

    expect(customer.balanceFor(program.id).points, 10);
    expect(find.text('Saldo disponible: Bs 10'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('la entrada del dashboard solo se anima una vez por sesión', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final state = AppState(LocalStore(), AppData.initial());
    await tester.pumpWidget(
      AppScope(
        state: state,
        child: MaterialApp(home: NavigationMenuScreen(onSignOut: () async {})),
      ),
    );
    await tester.pump(const Duration(milliseconds: 1200));
    await tester.tap(find.text('Programa\nde fidelidad'));
    await tester.pump(const Duration(milliseconds: 600));
    expect(tester.takeException(), isNull);
    final programPage = find.byType(ProgramsScreen, skipOffstage: false);
    expect(programPage, findsOneWidget);
    Navigator.of(tester.element(programPage)).pop();
    await tester.pump(const Duration(milliseconds: 500));

    final fades = tester.widgetList<FadeTransition>(
      find.descendant(
        of: find.byType(DashboardScreen),
        matching: find.byType(FadeTransition),
      ),
    );
    expect(fades, isNotEmpty);
    expect(fades.every((fade) => fade.opacity.value == 1), isTrue);
  });

  test('los niveles pertenecen únicamente a programas de puntos', () async {
    final data = AppData.initial();
    final pointsProgram = LoyaltyProgram(
      id: 'points-card',
      name: 'Club de puntos',
      type: ProgramType.points,
      tiers: [
        TierRule(id: 'bronze', name: 'Bronce', threshold: 0),
        TierRule(id: 'gold', name: 'Oro', threshold: 100),
      ],
    );
    data.programs.add(pointsProgram);
    final state = AppState(LocalStore(), data);
    final customer = state.addCustomer(name: 'Carla');
    state.adjustCardValue(
      customer.id,
      pointsProgram.id,
      delta: 100,
      description: 'Compra',
    );
    await state.commit();
    expect(customer.tier, 'Oro');
    expect(
      data.programs
          .where((program) => program.type != ProgramType.points)
          .every((program) => program.tiers.isEmpty),
      isTrue,
    );
    expect(pointsProgram.tiers, isNotEmpty);
    expect(data.challenges, isEmpty);
    expect(data.automations, isEmpty);
  });

  test('una campaña no envía dos peticiones simultáneas', () async {
    var requests = 0;
    final client = MockClient((request) async {
      requests++;
      await Future<void>.delayed(const Duration(milliseconds: 30));
      return http.Response(
        jsonEncode({
          'ok': true,
          'targetedCustomers': 1,
          'registeredDevices': 1,
        }),
        200,
      );
    });
    final service = WalletService(client: client);
    final business = BusinessProfile(backendUrl: 'https://fideli.test');

    final results = await Future.wait([
      service.sendCampaign(
        business,
        requestId: 'same-request',
        message: 'Prueba',
        audience: 'Todos',
      ),
      service.sendCampaign(
        business,
        requestId: 'same-request',
        message: 'Prueba',
        audience: 'Todos',
      ),
    ]);

    expect(requests, 1);
    expect(results.every((result) => result.ok), isTrue);
  });

  test('una campaña envía su título personalizado de notificación', () async {
    Map<String, dynamic>? sentBody;
    final client = MockClient((request) async {
      sentBody = jsonDecode(request.body) as Map<String, dynamic>;
      return http.Response(
        jsonEncode({'ok': true, 'targetedCustomers': 1, 'queuedPasses': 1}),
        200,
      );
    });
    final service = WalletService(client: client);
    final business = BusinessProfile(backendUrl: 'https://fideli.test');

    await service.sendCampaign(
      business,
      requestId: 'custom-title',
      notificationTitle: 'Día de la Madre',
      message: 'Tenemos un regalo para ti',
      audience: 'Todos',
    );

    expect(sentBody?['notificationTitle'], 'Día de la Madre');
  });

  test('el título de campaña es opcional y se envía vacío', () async {
    Map<String, dynamic>? sentBody;
    final service = WalletService(
      client: MockClient((request) async {
        sentBody = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(
          jsonEncode({'ok': true, 'targetedCustomers': 1, 'queuedPasses': 1}),
          200,
        );
      }),
    );

    await service.sendCampaign(
      BusinessProfile(backendUrl: 'https://fideli.test'),
      requestId: 'empty-title',
      message: 'Mensaje sin título personalizado',
      audience: 'Todos',
    );

    expect(sentBody?['notificationTitle'], '');
  });

  test(
    'guardar campaña persiste nombre y título como campos distintos',
    () async {
      Uri? requestedUri;
      Map<String, dynamic>? savedBody;
      final service = WalletService(
        client: MockClient((request) async {
          requestedUri = request.url;
          savedBody = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response(jsonEncode({'ok': true}), 200);
        }),
      );
      final campaign = Campaign(
        id: 'campaign-save-title',
        name: 'Nombre interno',
        notificationTitle: 'Día de la Madre',
        message: 'Tenemos un regalo para ti',
      );

      final result = await service.saveCampaign(
        BusinessProfile(backendUrl: 'https://fideli.test'),
        campaign,
      );

      expect(result.ok, isTrue);
      expect(requestedUri?.path.endsWith('/api/campaigns/save'), isTrue);
      expect(savedBody?['name'], 'Nombre interno');
      expect(savedBody?['campaignName'], 'Nombre interno');
      expect(savedBody?['notificationTitle'], 'Día de la Madre');
    },
  );

  test('una campaña individual conserva el cliente seleccionado', () {
    final campaign = Campaign(
      id: 'campaign-one',
      name: 'Cumpleaños',
      notificationTitle: 'Feliz cumpleaños, Ana',
      message: 'Tenemos algo para ti',
      audience: 'Una persona',
      targetCustomerId: 'customer-42',
      targetCustomerName: 'Ana Pérez',
    );

    final restored = Campaign.fromJson(campaign.toJson());

    expect(restored.audience, 'Una persona');
    expect(restored.notificationTitle, 'Feliz cumpleaños, Ana');
    expect(restored.targetCustomerId, 'customer-42');
    expect(restored.targetCustomerName, 'Ana Pérez');
  });

  test('la inteligencia del cliente conserva segmento y métricas', () {
    final customer = Customer(
      id: 'customer-intelligence',
      name: 'Ana',
      referralCode: 'ANA42',
      joinedAt: DateTime(2026),
      intelligence: CustomerIntelligence(
        segment: CustomerSegment.atRisk,
        totalVisits: 9,
        visits90d: 4,
        daysSinceLastVisit: 28,
        expectedVisitIntervalDays: 12,
        delayRatio: 2.33,
        riskScore: .76,
        valueScore: .62,
        explanation: 'Está demorando más de lo habitual en volver.',
      ),
    );

    final restored = Customer.fromJson(customer.toJson());

    expect(restored.intelligence?.segment, CustomerSegment.atRisk);
    expect(restored.intelligence?.totalVisits, 9);
    expect(restored.intelligence?.riskScore, .76);
    expect(restored.intelligence?.valueLabel, 'Valor medio');
  });

  test('el historial guarda tipo, programa, monto y metadatos', () {
    final activity = ActivityRecord(
      id: 'activity-1',
      customerId: 'customer-1',
      description: 'Compra registrada',
      createdAt: DateTime.utc(2026, 10, 3),
      eventType: 'purchase',
      programId: 'program-points',
      amountMinor: 2590,
      metadata: const {'source': 'qr'},
    );

    final restored = ActivityRecord.fromJson(activity.toJson());

    expect(restored.eventType, 'purchase');
    expect(restored.programId, 'program-points');
    expect(restored.amountMinor, 2590);
    expect(restored.metadata['source'], 'qr');
  });

  test('un programa conserva sus mensajes de bienvenida y finalización', () {
    final program = LoyaltyProgram(
      id: 'stamps-card',
      name: 'Café frecuente',
      type: ProgramType.stamps,
      welcomeMessage: '¡Tu tarjeta ya está lista!',
      completionMessage: '¡Completaste tus cafés!',
    );

    final restored = LoyaltyProgram.fromJson(program.toJson());

    expect(restored.welcomeMessage, '¡Tu tarjeta ya está lista!');
    expect(restored.completionMessage, '¡Completaste tus cafés!');
  });

  test(
    'Wallet Studio conserva plantillas aunque todavía no haya programas',
    () {
      final data = AppData.initial();
      final membership = data.wallet.templateFor('membership')
        ..colorHex = '#123456'
        ..backgroundImagePath = 'templates/membership/background'
        ..walletLayout = 'classic';

      final restored = AppData.decode(data.encode());
      final restoredMembership = restored.wallet.templateFor('membership');

      expect(membership.stampIcon, 'check');
      expect(restoredMembership.colorHex, '#123456');
      expect(
        restoredMembership.backgroundImagePath,
        'templates/membership/background',
      );
      expect(restoredMembership.walletLayout, 'classic');
    },
  );

  testWidgets('Wallet Studio fija la tarjeta al editar en escritorio', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final state = AppState(LocalStore(), AppData.initial());
    await tester.pumpWidget(
      AppScope(
        state: state,
        child: const MaterialApp(home: Scaffold(body: WalletStudioScreen())),
      ),
    );
    await tester.pump(const Duration(milliseconds: 1100));
    await tester.tap(find.text('Editar'));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('desktop-pinned-preview')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('editor-open')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Wallet Studio permite previsualizar regalo, membresía y puntos',
    (tester) async {
      tester.view.physicalSize = const Size(430, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final data = AppData.initial();
      for (final design in ['gift', 'membership', 'points']) {
        data.wallet.templateFor(design).walletLayout = 'classic';
      }
      data.programs.addAll([
        LoyaltyProgram(
          id: 'gift-card',
          name: 'Regalo',
          type: ProgramType.points,
          cardKind: 'Tarjeta de regalo',
        ),
        LoyaltyProgram(
          id: 'membership-card',
          name: 'Club mensual',
          type: ProgramType.membership,
          cardKind: 'Membresía',
          expiresAt: DateTime(2030, 12, 31),
        ),
        LoyaltyProgram(
          id: 'points-card',
          name: 'Puntos',
          type: ProgramType.points,
        ),
      ]);
      final state = AppState(LocalStore(), data);

      await tester.pumpWidget(
        AppScope(
          state: state,
          child: const MaterialApp(home: Scaffold(body: WalletStudioScreen())),
        ),
      );
      await tester.pump(const Duration(milliseconds: 1100));

      Future<void> selectType(String current, String next) async {
        await tester.tap(find.text(current).first);
        await tester.pumpAndSettle();
        await tester.tap(find.text(next).last);
        await tester.pumpAndSettle();
      }

      await selectType('Tarjeta de sellos', 'Tarjeta de regalo');
      expect(find.text('SALDO'), findsOneWidget);
      expect(find.text('Bs 150,00'), findsOneWidget);
      expect(find.byKey(const ValueKey('classic-card-layout')), findsOneWidget);

      await selectType('Tarjeta de regalo', 'Membresía');
      expect(find.text('MEMBRESÍA'), findsOneWidget);
      expect(find.text('ACTIVA'), findsOneWidget);
      expect(find.text('VENCIMIENTO'), findsOneWidget);
      expect(find.byKey(const ValueKey('classic-card-layout')), findsOneWidget);

      await selectType('Membresía', 'Tarjeta de puntos');
      expect(find.text('TUS PUNTOS'), findsOneWidget);
      expect(find.byKey(const ValueKey('classic-card-layout')), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
