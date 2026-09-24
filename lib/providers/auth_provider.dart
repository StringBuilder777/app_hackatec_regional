import 'package:flutter/foundation.dart';

import '../core/services/storage_service.dart';

/// Usuario autenticado (mínimo para el MVP).
class AuthUser {
  final String email;
  const AuthUser(this.email);
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

  void _restore() {
    final email = _storage.readString(_sessionKey);
    if (email != null && email.isNotEmpty) _user = AuthUser(email);
  }

  Future<bool> login(String email, String password) async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      final user = await _service.login(email, password);
      _user = user;
      await _storage.writeString(_sessionKey, user.email);
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
