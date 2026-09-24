import 'dart:convert';

import 'package:flutter/foundation.dart';

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

  final AuthService _service;
  final StorageService _storage;

  AuthUser? _user;
  bool _loading = false;
  String? _error;

  AuthProvider(this._service, this._storage) {
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

  Future<void> logout() async {
    _user = null;
    await _storage.remove(_sessionKey);
    notifyListeners();
  }
}
