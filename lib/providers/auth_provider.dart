import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../core/services/push_service.dart';
import '../core/services/sensecare_api_service.dart';
import '../core/services/storage_service.dart';

/// Usuario autenticado (mínimo para el MVP).
///
/// [idToken] es el JWT de Cognito (o cadena vacía para el mock local); lo
/// necesita [SenseCareApiService] para autorizar cada llamada al backend.
class AuthUser {
  final String email;
  final String idToken;
  const AuthUser(this.email, [this.idToken = '']);
}

/// Contrato de autenticación. Hoy: mock local. Mañana: Cognito / tu backend AWS
/// implementando esta misma interfaz, sin tocar la UI.
abstract class AuthService {
  Future<AuthUser> login(String email, String password);
}

class AuthException implements Exception {
  final String message;
  const AuthException(this.message);
  @override
  String toString() => message;
}

/// Auth mock: acepta cualquier correo válido y contraseña de >= 4 caracteres.
class MockAuthService implements AuthService {
  @override
  Future<AuthUser> login(String email, String password) async {
    await Future.delayed(const Duration(milliseconds: 600)); // simula red
    final e = email.trim();
    if (!e.contains('@') || !e.contains('.')) {
      throw const AuthException('Ingresa un correo válido.');
    }
    if (password.length < 4) {
      throw const AuthException(
          'La contraseña debe tener al menos 4 caracteres.');
    }
    return AuthUser(e);
  }
}

class AuthProvider extends ChangeNotifier {
  static const _sessionKey = 'auth_session';
  static const _pushEndpointKey = 'push_endpoint_id';

  final AuthService _service;
  final StorageService _storage;
  final PushService? _push;
  final SenseCareApiService _api;

  AuthUser? _user;
  bool _loading = false;
  String? _error;

  /// [push]/[api] son opcionales (con default) para no romper construcciones
  /// existentes de `AuthProvider` que no los pasan. El registro de push se
  /// resuelve AQUÍ, dentro de este provider (en vez de un
  /// `ChangeNotifierProxyProvider<AuthProvider, X>` como el de
  /// `DevicesProvider` en `main.dart`), porque es un efecto secundario del
  /// evento "login exitoso" que ya vive en este mismo provider -- no hay
  /// estado nuevo que la UI necesite observar, así que una capa de provider
  /// intermedia sólo para reenviar el idToken sería abstracción de más.
  AuthProvider(
    this._service,
    this._storage, {
    PushService? push,
    SenseCareApiService? api,
  })  : _push = push,
        _api = api ?? SenseCareApiService() {
    _restore();
  }

  AuthUser? get user => _user;
  bool get isLoggedIn => _user != null;
  bool get loading => _loading;
  String? get error => _error;

  /// El IdToken de Cognito de la sesión actual, o `null` si no hay sesión o
  /// el usuario viene del mock local (sin token real). Puede haber expirado
  /// (dura 1 hora) — quien lo use debe manejar un 401 pidiendo re-login.
  String? get idToken =>
      (_user?.idToken.isNotEmpty ?? false) ? _user!.idToken : null;

  void _restore() {
    final raw = _storage.readString(_sessionKey);
    if (raw == null || raw.isEmpty) return;
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final email = decoded['email'] as String?;
      final idToken = decoded['idToken'] as String? ?? '';
      if (email != null && email.isNotEmpty) _user = AuthUser(email, idToken);
    } catch (_) {
      // Formato legado (sesión guardada antes de persistir el idToken):
      // el valor crudo es directamente el email.
      _user = AuthUser(raw);
    }
    // A propósito NO se re-registra el push aquí: `_restore()` corre en el
    // constructor, antes de que cualquier UI haya visto `isLoggedIn` pasar
    // de `false` a `true` (para la app, la sesión "ya estaba" iniciada). Si
    // el token de push cambió (reinstalación, etc.) se corrige en el
    // siguiente login real.
  }

  Future<bool> login(String email, String password) async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      final user = await _service.login(email, password);
      _user = user;
      await _storage.writeString(
        _sessionKey,
        jsonEncode({'email': user.email, 'idToken': user.idToken}),
      );
      _loading = false;
      notifyListeners();
      // Fire-and-forget: el registro de push es best-effort y no debe
      // bloquear la navegación tras un login exitoso.
      unawaited(_registerPushDevice());
      return true;
    } on AuthException catch (e) {
      _error = e.message;
      _loading = false;
      notifyListeners();
      return false;
    } catch (_) {
      _error = 'No se pudo iniciar sesión. Intenta de nuevo.';
      _loading = false;
      notifyListeners();
      return false;
    }
  }

  /// Registra el token de push de este dispositivo (`POST
  /// /me/push-devices`) justo después de iniciar sesión, una sola vez por
  /// sesión. No hace nada si `push` no fue provisto, si
  /// `push.isAvailable` es `false` (sin `google-services.json` todavía --
  /// ver `docs/AWS_SNS_FCM.md`) o si el login fue con el mock local (sin
  /// `idToken` real): la app sigue funcionando en modo local exactamente
  /// igual que hoy. Cualquier error de red/backend se ignora: el usuario ya
  /// inició sesión y no debe quedar bloqueado por esto, que se puede
  /// reintentar en el siguiente login.
  Future<void> _registerPushDevice() async {
    final push = _push;
    final token = idToken;
    if (push == null || !push.isAvailable || token == null) return;
    try {
      final deviceToken = await push.deviceToken();
      if (deviceToken == null || deviceToken.isEmpty) return;
      final endpointId = await _api.registerPushDevice(
        platform: 'android',
        token: deviceToken,
        idToken: token,
      );
      if (endpointId.isNotEmpty) {
        await _storage.writeString(_pushEndpointKey, endpointId);
      }
    } catch (_) {
      // Best-effort; ver docstring de arriba.
    }
  }

  Future<void> logout() async {
    await _unregisterPushDevice();
    _user = null;
    await _storage.remove(_sessionKey);
    notifyListeners();
  }

  /// Da de baja el endpoint de push registrado (si lo hay) antes de perder
  /// el `idToken` necesario para autorizar la llamada. Se llama ANTES de
  /// borrar `_user` para que `idToken` siga disponible. Un 404 (el endpoint
  /// ya no existía) u otro error de red se ignoran igual que en
  /// `_registerPushDevice`: el logout local no debe depender de esto.
  Future<void> _unregisterPushDevice() async {
    final endpointId = _storage.readString(_pushEndpointKey);
    final token = idToken;
    if (endpointId == null || endpointId.isEmpty || token == null) return;
    try {
      await _api.unregisterPushDevice(endpointId: endpointId, idToken: token);
    } catch (_) {
      // Best-effort; ver _registerPushDevice.
    } finally {
      await _storage.remove(_pushEndpointKey);
    }
  }
}
