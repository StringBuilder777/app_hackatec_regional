// Pruebas del mapeo de códigos HTTP -> excepciones tipadas del cliente del
// API de SenseCare. Usa http.testing.MockClient (no hace red real).

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:app_hackatec_regional/core/services/sensecare_api_service.dart';

void main() {
  const baseUrl = 'https://api.example.com';
  const idToken = 'fake-id-token';

  group('SenseCareApiService.pairDevice', () {
    test('200 -> no lanza excepción', () async {
      final client = MockClient((req) async {
        expect(req.method, 'POST');
        expect(req.url.path, '/devices/sim-room-01/pair');
        expect(req.headers['Authorization'], 'Bearer $idToken');
        final body = jsonDecode(req.body) as Map<String, dynamic>;
        expect(body['pairingCode'], 'AB12CD');
        return http.Response(
            jsonEncode({'paired': true, 'deviceId': 'sim-room-01'}), 200);
      });
      final api = SenseCareApiService(baseUrl: baseUrl, client: client);

      await expectLater(
        api.pairDevice(
            deviceId: 'sim-room-01', pairingCode: 'AB12CD', idToken: idToken),
        completes,
      );
    });

    test('403 código incorrecto -> ForbiddenException', () async {
      final client = MockClient((req) async => http.Response(
          jsonEncode({'error': 'Codigo de emparejamiento invalido'}), 403));
      final api = SenseCareApiService(baseUrl: baseUrl, client: client);

      await expectLater(
        api.pairDevice(
            deviceId: 'sim-room-01', pairingCode: 'WRONG', idToken: idToken),
        throwsA(isA<ForbiddenException>()),
      );
    });

    test('404 deviceId inexistente -> NotFoundException', () async {
      final client = MockClient((req) async => http.Response(
          jsonEncode({'error': 'Dispositivo no encontrado'}), 404));
      final api = SenseCareApiService(baseUrl: baseUrl, client: client);

      await expectLater(
        api.pairDevice(
            deviceId: 'no-existe', pairingCode: 'AB12CD', idToken: idToken),
        throwsA(isA<NotFoundException>()),
      );
    });

    test('400 -> BadRequestException', () async {
      final client = MockClient((req) async =>
          http.Response(jsonEncode({'error': 'Falta pairingCode'}), 400));
      final api = SenseCareApiService(baseUrl: baseUrl, client: client);

      await expectLater(
        api.pairDevice(deviceId: 'sim-room-01', pairingCode: '', idToken: idToken),
        throwsA(isA<BadRequestException>()),
      );
    });

    test('401 -> UnauthorizedException', () async {
      final client = MockClient((req) async => http.Response('', 401));
      final api = SenseCareApiService(baseUrl: baseUrl, client: client);

      await expectLater(
        api.pairDevice(
            deviceId: 'sim-room-01', pairingCode: 'AB12CD', idToken: idToken),
        throwsA(isA<UnauthorizedException>()),
      );
    });

    test('500 con body no-JSON -> ApiException genérica', () async {
      final client =
          MockClient((req) async => http.Response('<html>oops</html>', 500));
      final api = SenseCareApiService(baseUrl: baseUrl, client: client);

      await expectLater(
        api.pairDevice(
            deviceId: 'sim-room-01', pairingCode: 'AB12CD', idToken: idToken),
        throwsA(isA<ApiException>()),
      );
    });

    test('error de red -> NetworkException', () async {
      final client = MockClient((req) async => throw const HttpUnavailable());
      final api = SenseCareApiService(baseUrl: baseUrl, client: client);

      await expectLater(
        api.pairDevice(
            deviceId: 'sim-room-01', pairingCode: 'AB12CD', idToken: idToken),
        throwsA(isA<NetworkException>()),
      );
    });
  });

  group('SenseCareApiService.getDeviceLatest', () {
    test('200 con latestTelemetry -> parsea correctamente', () async {
      final client = MockClient((req) async {
        expect(req.method, 'GET');
        expect(req.url.path, '/devices/pi-demo-01/latest');
        return http.Response(
          jsonEncode({
            'deviceId': 'pi-demo-01',
            'lastSeenAt': '2026-09-24T18:30:00Z',
            'latestTelemetry': {
              'deviceId': 'pi-demo-01',
              'occurredAt': '2026-09-24T18:30:00Z',
              'temperatureC': 27.3,
              'humidityPct': 48.1,
              'co2Ppm': 840,
              'proximityCm': 12,
              'dbAvg': 32.1,
              'dbPeak': 40.5,
              'receivedAt': '2026-09-24T18:30:01.203Z',
            },
          }),
          200,
        );
      });
      final api = SenseCareApiService(baseUrl: baseUrl, client: client);

      final result =
          await api.getDeviceLatest(deviceId: 'pi-demo-01', idToken: idToken);

      expect(result.deviceId, 'pi-demo-01');
      expect(result.lastSeenAt, isNotNull);
      expect(result.latestTelemetry, isNotNull);
      expect(result.latestTelemetry!.temperatureC, 27.3);
      expect(result.latestTelemetry!.co2Ppm, 840);
    });

    test('200 con lastSeenAt/latestTelemetry null -> no es error', () async {
      final client = MockClient((req) async => http.Response(
            jsonEncode({
              'deviceId': 'pi-demo-01',
              'lastSeenAt': null,
              'latestTelemetry': null,
            }),
            200,
          ));
      final api = SenseCareApiService(baseUrl: baseUrl, client: client);

      final result =
          await api.getDeviceLatest(deviceId: 'pi-demo-01', idToken: idToken);

      expect(result.lastSeenAt, isNull);
      expect(result.latestTelemetry, isNull);
    });

    test('403 sin emparejar -> ForbiddenException', () async {
      final client = MockClient((req) async => http.Response(
          jsonEncode({'error': 'No tienes acceso a este dispositivo'}), 403));
      final api = SenseCareApiService(baseUrl: baseUrl, client: client);

      await expectLater(
        api.getDeviceLatest(deviceId: 'pi-demo-01', idToken: idToken),
        throwsA(isA<ForbiddenException>()),
      );
    });
  });

  group('SenseCareApiService.getDeviceTelemetry', () {
    test('manda from/to/limit como query params', () async {
      final client = MockClient((req) async {
        expect(req.url.queryParameters['from'], '2026-09-24T00:00:00Z');
        expect(req.url.queryParameters['to'], '2026-09-24T23:59:59Z');
        expect(req.url.queryParameters['limit'], '200');
        return http.Response(
            jsonEncode({'deviceId': 'pi-demo-01', 'count': 0, 'items': []}),
            200);
      });
      final api = SenseCareApiService(baseUrl: baseUrl, client: client);

      final items = await api.getDeviceTelemetry(
        deviceId: 'pi-demo-01',
        idToken: idToken,
        from: '2026-09-24T00:00:00Z',
        to: '2026-09-24T23:59:59Z',
        limit: 200,
      );
      expect(items, isEmpty);
    });

    test('parsea la lista de items', () async {
      final client = MockClient((req) async => http.Response(
            jsonEncode({
              'deviceId': 'pi-demo-01',
              'count': 2,
              'items': [
                {
                  'deviceId': 'pi-demo-01',
                  'occurredAt': '2026-09-24T18:00:00Z',
                  'temperatureC': 26.0,
                },
                {
                  'deviceId': 'pi-demo-01',
                  'occurredAt': '2026-09-24T18:05:00Z',
                  'temperatureC': 26.5,
                },
              ],
            }),
            200,
          ));
      final api = SenseCareApiService(baseUrl: baseUrl, client: client);

      final items = await api.getDeviceTelemetry(
          deviceId: 'pi-demo-01', idToken: idToken);
      expect(items.length, 2);
      expect(items[0].temperatureC, 26.0);
      expect(items[1].temperatureC, 26.5);
    });
  });
}

/// Simula un fallo de red (equivalente a no tener conexión) para probar el
/// mapeo a [NetworkException].
class HttpUnavailable implements Exception {
  const HttpUnavailable();
}
