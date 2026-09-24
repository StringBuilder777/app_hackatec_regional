import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../core/config/app_config.dart';
import 'auth_provider.dart';

/// Implementación real de [AuthService] contra Amazon Cognito
/// (`InitiateAuth` con `USER_PASSWORD_AUTH`), ver
/// `docs/DEMO_INGEST_AUTH.md` (sección 3) en el repo del backend.
///
/// No hay auto-registro: solo funcionan cuentas creadas a mano por un admin
/// (`aws cognito-idp admin-create-user`). Esta clase no intenta ofrecer un
/// flujo de registro.
class CognitoAuthService implements AuthService {
  final String userPoolClientId;
  final Uri endpoint;
  final http.Client _client;

  CognitoAuthService({
    String? userPoolClientId,
    Uri? endpoint,
    http.Client? client,
  })  : userPoolClientId = userPoolClientId ?? AppConfig.cognitoUserPoolClientId,
        endpoint = endpoint ?? Uri.parse(AppConfig.cognitoIdpEndpoint),
        _client = client ?? http.Client();

  @override
  Future<AuthUser> login(String email, String password) async {
    final username = email.trim();

    http.Response resp;
    try {
      resp = await _client.post(
        endpoint,
        headers: const {
          'Content-Type': 'application/x-amz-json-1.1',
          'X-Amz-Target': 'AWSCognitoIdentityProviderService.InitiateAuth',
        },
        body: jsonEncode({
          'AuthFlow': 'USER_PASSWORD_AUTH',
          'ClientId': userPoolClientId,
          'AuthParameters': {
            'USERNAME': username,
            'PASSWORD': password,
          },
        }),
      );
    } on SocketException {
      throw const AuthException(
          'Sin conexión a internet. Revisa tu red e intenta de nuevo.');
    } catch (e) {
      throw AuthException('No se pudo conectar con el servidor: $e');
    }

    Map<String, dynamic> body = const {};
    if (resp.body.isNotEmpty) {
      try {
        final decoded = jsonDecode(resp.body);
        if (decoded is Map) body = decoded.cast<String, dynamic>();
      } catch (_) {
        // Respuesta no-JSON inesperada; se maneja abajo con el status code.
      }
    }

    if (resp.statusCode != 200) {
      throw AuthException(_mapCognitoError(body));
    }

    final result = body['AuthenticationResult'] as Map<String, dynamic>?;
    final idToken = result?['IdToken'] as String?;
    if (idToken == null || idToken.isEmpty) {
      // No hay AuthenticationResult: normalmente significa que Cognito pide
      // un paso adicional (challenge), p. ej. NEW_PASSWORD_REQUIRED. Las
      // cuentas de demo se crean con contraseña permanente para evitar
      // esto, pero si ocurre no hay flujo soportado en la app.
      final challenge = body['ChallengeName'] as String?;
      throw AuthException(challenge != null
          ? 'Tu cuenta requiere un paso adicional ($challenge) no soportado en la app. Contacta al administrador.'
          : 'El servidor no devolvió un token de sesión válido.');
    }

    return AuthUser(username, idToken);
  }

  /// Traduce el `__type` de error de Cognito a un mensaje entendible.
  /// Ver la tabla de "Errores comunes" en `docs/DEMO_INGEST_AUTH.md`.
  String _mapCognitoError(Map<String, dynamic> body) {
    final type = body['__type'] as String?;
    final message = body['message'] as String?;
    switch (type) {
      case 'NotAuthorizedException':
        return 'Usuario o contraseña incorrectos.';
      case 'UserNotFoundException':
        return 'No existe una cuenta con ese usuario.';
      case 'UserNotConfirmedException':
        return 'La cuenta no está confirmada. Contacta al administrador.';
      case 'PasswordResetRequiredException':
        return 'Se requiere restablecer la contraseña. Contacta al administrador.';
      case 'TooManyRequestsException':
      case 'LimitExceededException':
        return 'Demasiados intentos. Espera un momento e intenta de nuevo.';
      case null:
        return 'No se pudo iniciar sesión. Intenta de nuevo.';
      default:
        return message?.isNotEmpty == true
            ? message!
            : 'No se pudo iniciar sesión ($type).';
    }
  }
}
