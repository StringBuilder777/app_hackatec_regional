// Pruebas del mapeo de respuestas de Cognito InitiateAuth -> AuthUser /
// AuthException. Usa http.testing.MockClient (no hace red real).

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:app_hackatec_regional/providers/auth_provider.dart';
import 'package:app_hackatec_regional/providers/cognito_auth_service.dart';

void main() {
  final endpoint = Uri.parse('https://cognito-idp.us-east-1.amazonaws.com/');
  const clientId = 'fake-client-id';

  test('200 con AuthenticationResult -> AuthUser con IdToken', () async {
    final client = MockClient((req) async {
      expect(req.headers['X-Amz-Target'],
          'AWSCognitoIdentityProviderService.InitiateAuth');
      expect(req.headers['Content-Type'], 'application/x-amz-json-1.1');
      final body = jsonDecode(req.body) as Map<String, dynamic>;
      expect(body['AuthFlow'], 'USER_PASSWORD_AUTH');
      expect(body['ClientId'], clientId);
      final params = body['AuthParameters'] as Map<String, dynamic>;
      expect(params['USERNAME'], 'cuidador@demo.com');
      expect(params['PASSWORD'], 'secreta123');

      return http.Response(
        jsonEncode({
          'AuthenticationResult': {
            'IdToken': 'a.b.c',
            'AccessToken': 'x.y.z',
            'ExpiresIn': 3600,
            'TokenType': 'Bearer',
          },
        }),
        200,
      );
    });
    final service = CognitoAuthService(
        userPoolClientId: clientId, endpoint: endpoint, client: client);

    final user = await service.login('cuidador@demo.com', 'secreta123');

    expect(user.email, 'cuidador@demo.com');
    expect(user.idToken, 'a.b.c');
  });

  test('400 NotAuthorizedException -> mensaje de credenciales incorrectas',
      () async {
    final client = MockClient((req) async => http.Response(
          jsonEncode({
            '__type': 'NotAuthorizedException',
            'message': 'Incorrect username or password.',
          }),
          400,
        ));
    final service = CognitoAuthService(
        userPoolClientId: clientId, endpoint: endpoint, client: client);

    await expectLater(
      service.login('cuidador@demo.com', 'mala'),
      throwsA(isA<AuthException>().having(
          (e) => e.message, 'message', 'Usuario o contraseña incorrectos.')),
    );
  });

  test('400 UserNotFoundException -> mensaje de usuario no encontrado',
      () async {
    final client = MockClient((req) async => http.Response(
          jsonEncode({'__type': 'UserNotFoundException'}),
          400,
        ));
    final service = CognitoAuthService(
        userPoolClientId: clientId, endpoint: endpoint, client: client);

    await expectLater(
      service.login('nadie@demo.com', 'lo-que-sea'),
      throwsA(isA<AuthException>()),
    );
  });

  test('__type desconocido -> usa el message de la respuesta', () async {
    final client = MockClient((req) async => http.Response(
          jsonEncode({
            '__type': 'SomethingWeirdException',
            'message': 'Algo raro pasó.',
          }),
          400,
        ));
    final service = CognitoAuthService(
        userPoolClientId: clientId, endpoint: endpoint, client: client);

    await expectLater(
      service.login('a@b.com', 'x'),
      throwsA(isA<AuthException>().having(
          (e) => e.message, 'message', 'Algo raro pasó.')),
    );
  });

  test('200 sin AuthenticationResult (challenge) -> AuthException', () async {
    final client = MockClient((req) async => http.Response(
          jsonEncode({'ChallengeName': 'NEW_PASSWORD_REQUIRED'}),
          200,
        ));
    final service = CognitoAuthService(
        userPoolClientId: clientId, endpoint: endpoint, client: client);

    await expectLater(
      service.login('a@b.com', 'x'),
      throwsA(isA<AuthException>()),
    );
  });

  test('error de red -> AuthException', () async {
    final client = MockClient((req) async => throw Exception('sin red'));
    final service = CognitoAuthService(
        userPoolClientId: clientId, endpoint: endpoint, client: client);

    await expectLater(
      service.login('a@b.com', 'x'),
      throwsA(isA<AuthException>()),
    );
  });
}
