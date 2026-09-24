import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';

import 'app/home_shell.dart';
import 'app/theme.dart';
import 'core/services/notification_service.dart';
import 'core/services/push_service.dart';
import 'core/services/sensecare_api_service.dart';
import 'core/services/storage_service.dart';
import 'features/auth/login_screen.dart';
import 'models/alert.dart';
import 'providers/alerts_provider.dart';
import 'providers/auth_provider.dart';
import 'providers/cognito_auth_service.dart';
import 'providers/devices_provider.dart';
import 'providers/profiles_provider.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('es');

  final storage = await StorageService.create();

  final notifications = NotificationService();
  await notifications.init();

  // Costura de push: hoy corre en modo local; mañana entra AWS SNS -> FCM.
  final push = FcmPushService();
  await push.initialize();

  runApp(CuidadosApp(
    storage: storage,
    notifications: notifications,
    push: push,
  ));
}

class CuidadosApp extends StatelessWidget {
  final StorageService storage;
  final NotificationService notifications;
  final PushService push;

  const CuidadosApp({
    super.key,
    required this.storage,
    required this.notifications,
    required this.push,
  });

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        // Hoy: Cognito real (ver CognitoAuthService). Para volver al mock
        // local de demo, cambia CognitoAuthService() por MockAuthService().
        ChangeNotifierProvider(
            create: (_) => AuthProvider(CognitoAuthService(), storage)),
        ChangeNotifierProvider(
            create: (_) => AlertsProvider(storage, notifications)),
        ChangeNotifierProvider(
            create: (_) => ProfilesProvider(storage, notifications)),
        // DevicesProvider necesita el IdToken vigente de AuthProvider para
        // autorizar cada llamada al backend; el ProxyProvider lo mantiene
        // sincronizado sin que la UI tenga que pasarlo a mano.
        ChangeNotifierProxyProvider<AuthProvider, DevicesProvider>(
          create: (ctx) => DevicesProvider(
            SenseCareApiService(),
            storage,
            () => ctx.read<AuthProvider>().idToken,
          ),
          update: (ctx, auth, previous) {
            final provider = previous ??
                DevicesProvider(
                  SenseCareApiService(),
                  storage,
                  () => auth.idToken,
                );
            provider.updateTokenProvider(() => auth.idToken);
            return provider;
          },
        ),
      ],
      child: MaterialApp(
        title: 'Alertas Cuidados',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        themeMode: ThemeMode.light,
        home: _PushBridge(
            push: push, notifications: notifications, child: const AuthGate()),
      ),
    );
  }
}

/// Decide qué mostrar según haya sesión iniciada.
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    final loggedIn = context.watch<AuthProvider>().isLoggedIn;
    return loggedIn ? const HomeShell() : const LoginScreen();
  }
}

/// Conecta los mensajes push entrantes con el flujo de alertas de la app.
class _PushBridge extends StatefulWidget {
  final PushService push;
  final NotificationService notifications;
  final Widget child;
  const _PushBridge(
      {required this.push, required this.notifications, required this.child});

  @override
  State<_PushBridge> createState() => _PushBridgeState();
}

class _PushBridgeState extends State<_PushBridge> {
  StreamSubscription<Map<String, dynamic>>? _sub;

  @override
  void initState() {
    super.initState();
    _sub = widget.push.onData.listen((data) {
      if (!mounted) return;
      // Un push data-only de SNS/FCM se convierte en alerta y se muestra.
      context.read<AlertsProvider>().receiveIncoming(Alert.fromPushData(data));
    });

    // Al tocar una notificación de alerta, márcala como vista.
    widget.notifications.onTap = (payload) {
      if (!mounted || payload == null) return;
      context.read<AlertsProvider>().markViewed(payload);
    };
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
