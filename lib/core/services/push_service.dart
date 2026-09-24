import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

/// Costura de push (recepción remota).
///
/// Hoy la app corre en "modo local" (sin backend). Cuando el backend en AWS
/// SNS esté listo, en Android SNS entrega vía FCM y los mensajes llegan aquí.
/// Ver `docs/AWS_SNS_FCM.md` para activarlo (google-services.json + plugin).
abstract class PushService {
  Future<void> initialize();

  /// Token del dispositivo a registrar como endpoint en AWS SNS.
  Future<String?> deviceToken();

  /// Payloads `data` entrantes, normalizados a `Map<String, dynamic>`.
  Stream<Map<String, dynamic>> get onData;

  bool get isAvailable;

  void dispose();
}

/// Handler de mensajes en segundo plano. Debe ser función top-level.
@pragma('vm:entry-point')
Future<void> firebaseBackgroundHandler(RemoteMessage message) async {
  // En segundo plano el sistema muestra la notificación automáticamente.
  // Si se requiere procesar el payload, inicializa lo mínimo aquí.
}

/// Implementación FCM que se autodegrada: si no hay `google-services.json`,
/// `initialize()` no crashea y la app sigue en modo local.
class FcmPushService implements PushService {
  final _controller = StreamController<Map<String, dynamic>>.broadcast();
  bool _available = false;

  @override
  bool get isAvailable => _available;

  @override
  Stream<Map<String, dynamic>> get onData => _controller.stream;

  @override
  Future<void> initialize() async {
    try {
      await Firebase.initializeApp();
      final messaging = FirebaseMessaging.instance;
      await messaging.requestPermission();
      FirebaseMessaging.onBackgroundMessage(firebaseBackgroundHandler);
      FirebaseMessaging.onMessage.listen(_emit);
      FirebaseMessaging.onMessageOpenedApp.listen(_emit);
      _available = true;
      debugPrint(
          'FCM listo. Token de dispositivo: ${await messaging.getToken()}');
    } catch (e) {
      _available = false;
      debugPrint('FCM no configurado (falta google-services.json). '
          'La app corre en modo local. Detalle: $e');
    }
  }

  void _emit(RemoteMessage m) {
    if (m.data.isNotEmpty) {
      _controller.add(Map<String, dynamic>.from(m.data));
    }
  }

  @override
  Future<String?> deviceToken() async {
    if (!_available) return null;
    try {
      return await FirebaseMessaging.instance.getToken();
    } catch (_) {
      return null;
    }
  }

  @override
  void dispose() => _controller.close();
}
