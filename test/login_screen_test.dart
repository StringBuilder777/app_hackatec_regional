// Pruebas del login: acepta usuarios de Cognito que no son correo (sin "@") y
// los manda sin espacios sueltos. El servicio de auth va simulado.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:app_hackatec_regional/core/services/storage_service.dart';
import 'package:app_hackatec_regional/features/auth/login_screen.dart';
import 'package:app_hackatec_regional/providers/auth_provider.dart';

class _RecordingAuth implements AuthService {
  String? username;
  String? password;

  @override
  Future<AuthUser> login(String email, String password) async {
    username = email;
    this.password = password;
    return AuthUser(email, 'token-de-prueba');
  }
}

void main() {
  late _RecordingAuth service;

  Future<void> pumpLogin(WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final storage = StorageService(await SharedPreferences.getInstance());
    service = _RecordingAuth();
    await tester.pumpWidget(ChangeNotifierProvider(
      create: (_) => AuthProvider(service, storage),
      child: const MaterialApp(home: LoginScreen()),
    ));
  }

  Future<void> submit(WidgetTester tester) async {
    await tester.ensureVisible(find.text('Ingresar'));
    await tester.tap(find.text('Ingresar'));
    await tester.pump();
  }

  testWidgets('acepta un usuario sin "@" y lo manda sin espacios',
      (tester) async {
    await pumpLogin(tester);
    await tester.enterText(find.byType(TextFormField).first, ' operador-1 ');
    await tester.enterText(find.byType(TextFormField).last, ' Clave-Prueba1 ');
    await submit(tester);

    expect(find.text('Ingresa tu usuario'), findsNothing);
    expect(service.username, 'operador-1');
    expect(service.password, ' Clave-Prueba1 '); // La contraseña va intacta.
  });

  for (final (caso, usuario) in [('vacío', ''), ('de puros espacios', '   ')]) {
    testWidgets('pide el usuario si se deja $caso', (tester) async {
      await pumpLogin(tester);
      await tester.enterText(find.byType(TextFormField).first, usuario);
      await tester.enterText(find.byType(TextFormField).last, 'Clave-Prueba1');
      await submit(tester);

      expect(find.text('Ingresa tu usuario'), findsOneWidget);
      expect(service.username, isNull);
    });
  }
}
