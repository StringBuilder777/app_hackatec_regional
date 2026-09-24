// Pruebas de AuthProvider: login/logout, exposición de idToken, y
// restauración de sesión (incluyendo el formato legado sin idToken).
// No depende de red real: usa MockAuthService y una implementación fake de
// StorageService en memoria (no requiere plugins nativos).

import 'package:flutter_test/flutter_test.dart';

import 'package:app_hackatec_regional/core/services/storage_service.dart';
import 'package:app_hackatec_regional/providers/auth_provider.dart';

/// Fake en memoria de las dos operaciones de StorageService que usa
/// AuthProvider, para no depender de shared_preferences en estas pruebas.
class _FakeStorage implements StorageService {
  final Map<String, String> _strings = {};

  @override
  String? readString(String key) => _strings[key];

  @override
  Future<void> writeString(String key, String value) async {
    _strings[key] = value;
  }

  @override
  Future<void> remove(String key) async {
    _strings.remove(key);
  }

  @override
  List<Map<String, dynamic>> readList(String key) => [];

  @override
  Future<void> writeList(String key, List<Map<String, dynamic>> items) async {}
}

class _FakeAuthService implements AuthService {
  final String tokenToReturn;
  _FakeAuthService(this.tokenToReturn);

  @override
  Future<AuthUser> login(String email, String password) async {
    if (password == 'bad') throw const AuthException('Credenciales inválidas');
    return AuthUser(email, tokenToReturn);
  }
}

void main() {
  test('login exitoso deja isLoggedIn=true y expone el idToken', () async {
    final storage = _FakeStorage();
    final provider =
        AuthProvider(_FakeAuthService('a.b.c'), storage);

    final ok = await provider.login('cuidador@demo.com', 'buena');

    expect(ok, isTrue);
    expect(provider.isLoggedIn, isTrue);
    expect(provider.user?.email, 'cuidador@demo.com');
    expect(provider.idToken, 'a.b.c');
    expect(provider.error, isNull);
  });

  test('login fallido deja error y no autentica', () async {
    final storage = _FakeStorage();
    final provider = AuthProvider(_FakeAuthService('a.b.c'), storage);

    final ok = await provider.login('cuidador@demo.com', 'bad');

    expect(ok, isFalse);
    expect(provider.isLoggedIn, isFalse);
    expect(provider.error, isNotNull);
  });

  test('idToken es null cuando viene vacío (MockAuthService)', () async {
    final storage = _FakeStorage();
    final provider = AuthProvider(_FakeAuthService(''), storage);

    await provider.login('cuidador@demo.com', 'buena');

    expect(provider.idToken, isNull);
  });

  test('una nueva instancia restaura la sesión (email + idToken) guardada',
      () async {
    final storage = _FakeStorage();
    final provider1 = AuthProvider(_FakeAuthService('a.b.c'), storage);
    await provider1.login('cuidador@demo.com', 'buena');

    final provider2 = AuthProvider(_FakeAuthService('a.b.c'), storage);

    expect(provider2.isLoggedIn, isTrue);
    expect(provider2.user?.email, 'cuidador@demo.com');
    expect(provider2.idToken, 'a.b.c');
  });

  test('restaura sesión en formato legado (solo el email, sin JSON)',
      () async {
    final storage = _FakeStorage();
    await storage.writeString('auth_session', 'legado@demo.com');

    final provider = AuthProvider(_FakeAuthService('a.b.c'), storage);

    expect(provider.isLoggedIn, isTrue);
    expect(provider.user?.email, 'legado@demo.com');
    expect(provider.idToken, isNull);
  });

  test('logout limpia la sesión', () async {
    final storage = _FakeStorage();
    final provider = AuthProvider(_FakeAuthService('a.b.c'), storage);
    await provider.login('cuidador@demo.com', 'buena');

    await provider.logout();

    expect(provider.isLoggedIn, isFalse);
    expect(storage.readString('auth_session'), isNull);
  });
}
