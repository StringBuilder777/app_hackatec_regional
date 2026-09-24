// Pruebas de DevicesProvider: emparejamiento, persistencia local de la
// lista de dispositivos, y actualización del estado tras refreshLatest.
// Usa SharedPreferences.setMockInitialValues (en memoria) y
// http.testing.MockClient, sin red ni cámara real. No se prueba el timer de
// polling en sí (startPolling) para evitar temporizadores colgados al
// terminar el test; refreshLatest (la unidad que el timer invoca) sí se
// prueba directamente.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:app_hackatec_regional/core/services/sensecare_api_service.dart';
import 'package:app_hackatec_regional/core/services/storage_service.dart';
import 'package:app_hackatec_regional/providers/devices_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<StorageService> newStorage() async {
    SharedPreferences.setMockInitialValues({});
    return StorageService.create();
  }

  test('pairDevice exitoso agrega el dispositivo y lo persiste', () async {
    final storage = await newStorage();
    final client = MockClient((req) async => http.Response(
        jsonEncode({'paired': true, 'deviceId': 'sim-room-01'}), 200));
    final api = SenseCareApiService(baseUrl: 'https://api.example.com', client: client);
    final provider = DevicesProvider(api, storage, () => 'fake-token');

    final ok = await provider.pairDevice('sim-room-01', 'AB12CD');

    expect(ok, isTrue);
    expect(provider.isPaired('sim-room-01'), isTrue);
    expect(provider.pairError, isNull);
    expect(provider.devices.single.deviceId, 'sim-room-01');
  });

  test('pairDevice con código incorrecto (403) deja pairError y no empareja',
      () async {
    final storage = await newStorage();
    final client = MockClient((req) async => http.Response(
        jsonEncode({'error': 'Codigo de emparejamiento invalido'}), 403));
    final api = SenseCareApiService(baseUrl: 'https://api.example.com', client: client);
    final provider = DevicesProvider(api, storage, () => 'fake-token');

    final ok = await provider.pairDevice('sim-room-01', 'WRONG');

    expect(ok, isFalse);
    expect(provider.isPaired('sim-room-01'), isFalse);
    expect(provider.pairError, isNotNull);
  });

  test('pairDevice sin sesión (token nulo) no llama al backend', () async {
    final storage = await newStorage();
    var called = false;
    final client = MockClient((req) async {
      called = true;
      return http.Response('{}', 200);
    });
    final api = SenseCareApiService(baseUrl: 'https://api.example.com', client: client);
    final provider = DevicesProvider(api, storage, () => null);

    final ok = await provider.pairDevice('sim-room-01', 'AB12CD');

    expect(ok, isFalse);
    expect(called, isFalse);
    expect(provider.pairError, contains('sesión'));
  });

  test('pairDevice con campos vacíos falla sin llamar al backend', () async {
    final storage = await newStorage();
    var called = false;
    final client = MockClient((req) async {
      called = true;
      return http.Response('{}', 200);
    });
    final api = SenseCareApiService(baseUrl: 'https://api.example.com', client: client);
    final provider = DevicesProvider(api, storage, () => 'fake-token');

    final ok = await provider.pairDevice('', '');

    expect(ok, isFalse);
    expect(called, isFalse);
  });

  test('la lista de dispositivos emparejados persiste entre instancias',
      () async {
    SharedPreferences.setMockInitialValues({});
    final storage1 = await StorageService.create();
    final client = MockClient((req) async => http.Response(
        jsonEncode({'paired': true, 'deviceId': 'pi-demo-01'}), 200));
    final api = SenseCareApiService(baseUrl: 'https://api.example.com', client: client);
    final provider1 = DevicesProvider(api, storage1, () => 'fake-token');
    await provider1.pairDevice('pi-demo-01', 'ZZ99YY');

    // Nueva instancia sobre las mismas SharedPreferences (no se resetean).
    final storage2 = await StorageService.create();
    final provider2 = DevicesProvider(api, storage2, () => 'fake-token');

    expect(provider2.isPaired('pi-demo-01'), isTrue);
  });

  test('removeDevice quita el dispositivo de la lista y lo persiste',
      () async {
    final storage = await newStorage();
    final client = MockClient((req) async => http.Response(
        jsonEncode({'paired': true, 'deviceId': 'sim-room-01'}), 200));
    final api = SenseCareApiService(baseUrl: 'https://api.example.com', client: client);
    final provider = DevicesProvider(api, storage, () => 'fake-token');
    await provider.pairDevice('sim-room-01', 'AB12CD');
    expect(provider.isPaired('sim-room-01'), isTrue);

    await provider.removeDevice('sim-room-01');

    expect(provider.isPaired('sim-room-01'), isFalse);
    expect(provider.devices, isEmpty);
  });

  test('refreshLatest actualiza lastSeenAt y latestTelemetry del dispositivo',
      () async {
    final storage = await newStorage();
    final client = MockClient((req) async {
      if (req.method == 'POST') {
        return http.Response(
            jsonEncode({'paired': true, 'deviceId': 'pi-demo-01'}), 200);
      }
      return http.Response(
        jsonEncode({
          'deviceId': 'pi-demo-01',
          'lastSeenAt': '2026-09-24T18:30:00Z',
          'latestTelemetry': {
            'deviceId': 'pi-demo-01',
            'occurredAt': '2026-09-24T18:30:00Z',
            'temperatureC': 27.3,
          },
        }),
        200,
      );
    });
    final api = SenseCareApiService(baseUrl: 'https://api.example.com', client: client);
    final provider = DevicesProvider(api, storage, () => 'fake-token');
    await provider.pairDevice('pi-demo-01', 'AB12CD');

    await provider.refreshLatest('pi-demo-01');

    final device = provider.byId('pi-demo-01');
    expect(device, isNotNull);
    expect(device!.lastSeenAt, isNotNull);
    expect(device.latestTelemetry?.temperatureC, 27.3);
  });

  test('refreshLatest en error no lanza y deja el estado anterior intacto',
      () async {
    final storage = await newStorage();
    final client = MockClient((req) async {
      if (req.method == 'POST') {
        return http.Response(
            jsonEncode({'paired': true, 'deviceId': 'pi-demo-01'}), 200);
      }
      return http.Response(jsonEncode({'error': 'boom'}), 500);
    });
    final api = SenseCareApiService(baseUrl: 'https://api.example.com', client: client);
    final provider = DevicesProvider(api, storage, () => 'fake-token');
    await provider.pairDevice('pi-demo-01', 'AB12CD');

    await provider.refreshLatest('pi-demo-01');

    final device = provider.byId('pi-demo-01');
    expect(device, isNotNull);
    expect(device!.lastSeenAt, isNull);
  });
}
