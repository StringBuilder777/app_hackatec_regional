import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../../models/case_decision_result.dart';
import '../../models/case_summary.dart';
import '../../models/telemetry_reading.dart';
import '../config/app_config.dart';

/// Error base de una llamada al API de SenseCare. `statusCode` es `null`
/// cuando el error ocurrió antes de recibir respuesta (p. ej. sin red).
class ApiException implements Exception {
  final String message;
  final int? statusCode;
  const ApiException(this.message, [this.statusCode]);

  @override
  String toString() => message;
}

/// 401: falta el header Authorization o el IdToken expiró (dura 1 hora).
class UnauthorizedException extends ApiException {
  const UnauthorizedException(
      [String message = 'Tu sesión expiró. Vuelve a iniciar sesión.'])
      : super(message, 401);
}

/// 403: el pairingCode no coincide, o el usuario no emparejó ese deviceId.
class ForbiddenException extends ApiException {
  const ForbiddenException(
      [String message = 'No tienes acceso a este dispositivo.'])
      : super(message, 403);
}

/// 404: el deviceId no existe en `SenseCare-Devices`.
class NotFoundException extends ApiException {
  const NotFoundException([String message = 'Dispositivo no encontrado.'])
      : super(message, 404);
}

/// 400: el cuerpo/parametros de la solicitud no pasan el schema del backend.
class BadRequestException extends ApiException {
  const BadRequestException([String message = 'Solicitud inválida.'])
      : super(message, 400);
}

/// Error de red (sin conexión, DNS, timeout) o respuesta no-JSON inesperada
/// del servidor (p. ej. un 5xx de API Gateway sin body JSON).
class NetworkException extends ApiException {
  const NetworkException(
      [String message = 'No se pudo conectar con el servidor.'])
      : super(message);
}

/// Cliente HTTP del API de SenseCare (`docs/DEMO_INGEST_AUTH.md` del
/// backend). Todas las rutas de este cliente requieren un `IdToken` de
/// Cognito vigente (lo entrega [AuthProvider] tras el login).
class SenseCareApiService {
  final String baseUrl;
  final http.Client _client;

  SenseCareApiService({String? baseUrl, http.Client? client})
      : baseUrl = baseUrl ?? AppConfig.apiBaseUrl,
        _client = client ?? http.Client();

  Uri _uri(String path, [Map<String, String>? query]) {
    final trimmedBase =
        baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;
    final uri = Uri.parse('$trimmedBase$path');
    if (query == null || query.isEmpty) return uri;
    return uri.replace(queryParameters: query);
  }

  Map<String, String> _headers(String idToken) => {
        'Authorization': 'Bearer $idToken',
        'Content-Type': 'application/json',
      };

  /// Decodifica el body a un Map, o `{}` si viene vacío o no es JSON válido
  /// (p. ej. una página de error de API Gateway). Compartido por
  /// [_decodeOrThrow] y por el manejo especial del 409 en [_decideCase].
  Map<String, dynamic> _decodeBody(http.Response resp) {
    if (resp.body.isEmpty) return const {};
    try {
      final decoded = jsonDecode(resp.body);
      if (decoded is Map) return decoded.cast<String, dynamic>();
    } catch (_) {
      // Se ignora: se usa un mensaje generico segun el status code.
    }
    return const {};
  }

  /// Decodifica el body (si lo hay) y lanza la excepción tipada que
  /// corresponda al código de estado. Devuelve el body decodificado en 2xx.
  Map<String, dynamic> _decodeOrThrow(http.Response resp) {
    final body = _decodeBody(resp);

    String errorMessage(String fallback) =>
        (body['error'] as String?)?.trim().isNotEmpty == true
            ? body['error'] as String
            : fallback;

    switch (resp.statusCode) {
      case 200:
      case 201:
      case 202:
        return body;
      case 400:
        throw BadRequestException(errorMessage('Solicitud inválida.'));
      case 401:
        throw const UnauthorizedException();
      case 403:
        throw ForbiddenException(
            errorMessage('No tienes acceso a este dispositivo.'));
      case 404:
        throw NotFoundException(errorMessage('Dispositivo no encontrado.'));
      default:
        throw ApiException(
            'Error inesperado del servidor (${resp.statusCode}).',
            resp.statusCode);
    }
  }

  Future<http.Response> _send(Future<http.Response> Function() call) async {
    try {
      return await call();
    } on SocketException {
      throw const NetworkException(
          'Sin conexión a internet. Revisa tu red e intenta de nuevo.');
    } on HttpException catch (e) {
      throw NetworkException('Error de red: ${e.message}');
    } on FormatException {
      throw const NetworkException('Respuesta inválida del servidor.');
    } on ApiException {
      rethrow;
    } catch (e) {
      throw NetworkException('No se pudo conectar con el servidor: $e');
    }
  }

  /// `POST /devices/{deviceId}/pair` -- crea/otorga acceso de lectura para
  /// este usuario sobre `deviceId` si `pairingCode` coincide con el
  /// guardado en el backend. Lanza [ForbiddenException] si el código es
  /// incorrecto y [NotFoundException] si el `deviceId` no existe.
  Future<void> pairDevice({
    required String deviceId,
    required String pairingCode,
    required String idToken,
  }) async {
    final resp = await _send(() => _client.post(
          _uri('/devices/$deviceId/pair'),
          headers: _headers(idToken),
          body: jsonEncode({'pairingCode': pairingCode}),
        ));
    _decodeOrThrow(resp);
  }

  /// `GET /devices/{deviceId}/latest` -- último valor conocido de cada
  /// sensor. Lanza [ForbiddenException] si el usuario no emparejó este
  /// `deviceId` todavía.
  Future<DeviceLatestResult> getDeviceLatest({
    required String deviceId,
    required String idToken,
  }) async {
    final resp = await _send(() => _client.get(
          _uri('/devices/$deviceId/latest'),
          headers: _headers(idToken),
        ));
    final body = _decodeOrThrow(resp);
    return DeviceLatestResult.fromJson(body);
  }

  /// `GET /devices/{deviceId}/telemetry?from=&to=&limit=` -- historial para
  /// graficar. `from`/`to` deben ser ISO-8601 UTC terminados en `Z`; `limit`
  /// máximo 500 (default backend: 100).
  Future<List<TelemetryReading>> getDeviceTelemetry({
    required String deviceId,
    required String idToken,
    String? from,
    String? to,
    int? limit,
  }) async {
    final resp = await _send(() => _client.get(
          _uri('/devices/$deviceId/telemetry', {
            if (from != null) 'from': from,
            if (to != null) 'to': to,
            if (limit != null) 'limit': '$limit',
          }),
          headers: _headers(idToken),
        ));
    final body = _decodeOrThrow(resp);
    final items = (body['items'] as List? ?? const [])
        .map((e) => TelemetryReading.fromJson((e as Map).cast<String, dynamic>()))
        .toList();
    return items;
  }

  /// `POST /me/push-devices` -- registra el token de push (FCM) de este
  /// dispositivo como un nuevo endpoint de Amazon Pinpoint para el
  /// usuario autenticado. Devuelve el `endpointId` que hay que guardar para
  /// poder darlo de baja después con [unregisterPushDevice] (p. ej. al
  /// cerrar sesión) -- ver `AuthProvider`.
  Future<String> registerPushDevice({
    required String platform,
    required String token,
    required String idToken,
  }) async {
    final resp = await _send(() => _client.post(
          _uri('/me/push-devices'),
          headers: _headers(idToken),
          body: jsonEncode({'platform': platform, 'token': token}),
        ));
    final body = _decodeOrThrow(resp);
    return body['endpointId'] as String? ?? '';
  }

  /// `DELETE /me/push-devices/{endpointId}` -- da de baja el endpoint (p.
  /// ej. al cerrar sesión). Lanza [NotFoundException] si ya no existe o no
  /// pertenece a este usuario; quien llama puede tratarlo como no-op.
  Future<void> unregisterPushDevice({
    required String endpointId,
    required String idToken,
  }) async {
    final resp = await _send(() => _client.delete(
          _uri('/me/push-devices/$endpointId'),
          headers: _headers(idToken),
        ));
    _decodeOrThrow(resp);
  }

  /// `GET /cases?limit=N` -- casos (alertas) visibles para este usuario.
  /// Devuelve lista vacía (nunca 403) si el usuario no tiene dispositivos
  /// emparejados todavía -- ver [CaseSummary].
  Future<List<CaseSummary>> listCases({
    required String idToken,
    int? limit,
  }) async {
    final resp = await _send(() => _client.get(
          _uri('/cases', {if (limit != null) 'limit': '$limit'}),
          headers: _headers(idToken),
        ));
    final body = _decodeOrThrow(resp);
    final items = (body['items'] as List? ?? const [])
        .map((e) => CaseSummary.fromJson((e as Map).cast<String, dynamic>()))
        .toList();
    return items;
  }

  /// `GET /cases/{caseId}/events` -- bitácora de eventos de un caso (filas
  /// opacas, ver [CaseEvent]). Lanza [ForbiddenException]/[NotFoundException]
  /// igual que las demás rutas de `/cases`.
  Future<List<CaseEvent>> getCaseEvents({
    required String caseId,
    required String idToken,
  }) async {
    final resp = await _send(() => _client.get(
          _uri('/cases/$caseId/events'),
          headers: _headers(idToken),
        ));
    final body = _decodeOrThrow(resp);
    final items = (body['items'] as List? ?? const [])
        .map((e) => CaseEvent.fromJson((e as Map).cast<String, dynamic>()))
        .toList();
    return items;
  }

  /// `POST /cases/{caseId}/cancel` -- marca el caso como resuelto sin
  /// escalar. Ver [_decideCase] para el manejo del 409.
  Future<CaseDecisionResult> cancelCase({
    required String caseId,
    required String idToken,
  }) =>
      _decideCase('/cases/$caseId/cancel', idToken);

  /// `POST /cases/{caseId}/escalate` -- marca el caso como escalado. Ver
  /// [_decideCase] para el manejo del 409.
  Future<CaseDecisionResult> escalateCase({
    required String caseId,
    required String idToken,
  }) =>
      _decideCase('/cases/$caseId/escalate', idToken);

  /// POST sin body a una ruta de decisión de caso (`/cancel` o
  /// `/escalate`). Éxito (200) y conflicto (409) devuelven la misma forma
  /// de body (`{ caseId, alertStatus }`, con `error` extra en el 409) y
  /// ambos son un resultado *válido* de la operación -- un 409 significa
  /// "otra vía ya decidió este caso", no un fallo de red ni de permisos.
  /// Por eso NO se trata como una `ApiException` más (ver
  /// [CaseDecisionResult] para el razonamiento completo); todo lo demás
  /// (400/401/403/404/5xx) sigue la ruta normal de [_decodeOrThrow].
  Future<CaseDecisionResult> _decideCase(String path, String idToken) async {
    final resp = await _send(() => _client.post(
          _uri(path),
          headers: _headers(idToken),
        ));
    if (resp.statusCode == 409) {
      return CaseDecisionResult.fromJson(_decodeBody(resp), conflict: true);
    }
    final body = _decodeOrThrow(resp);
    return CaseDecisionResult.fromJson(body);
  }

  void dispose() => _client.close();
}
