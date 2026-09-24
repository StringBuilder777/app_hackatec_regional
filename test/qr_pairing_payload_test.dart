// Pruebas del parseo del JSON plano que codifica el QR de emparejamiento
// ({"deviceId": "...", "pairingCode": "..."}). No depende de cámara ni red.

import 'package:flutter_test/flutter_test.dart';

import 'package:app_hackatec_regional/features/pairing/qr_scan_screen.dart';

void main() {
  group('QrPairingPayload.tryParse', () {
    test('parsea un QR válido', () {
      final payload =
          QrPairingPayload.tryParse('{"deviceId":"sim-room-01","pairingCode":"AB12CD"}');
      expect(payload, isNotNull);
      expect(payload!.deviceId, 'sim-room-01');
      expect(payload.pairingCode, 'AB12CD');
    });

    test('recorta espacios en deviceId y pairingCode', () {
      final payload = QrPairingPayload.tryParse(
          '{"deviceId":" pi-demo-01 ","pairingCode":" 9K2M7X "}');
      expect(payload!.deviceId, 'pi-demo-01');
      expect(payload.pairingCode, '9K2M7X');
    });

    test('devuelve null si el texto no es JSON', () {
      expect(QrPairingPayload.tryParse('esto no es json'), isNull);
    });

    test('devuelve null si el JSON no es un objeto', () {
      expect(QrPairingPayload.tryParse('["deviceId","pairingCode"]'), isNull);
    });

    test('devuelve null si falta deviceId', () {
      expect(
        QrPairingPayload.tryParse('{"pairingCode":"AB12CD"}'),
        isNull,
      );
    });

    test('devuelve null si falta pairingCode', () {
      expect(
        QrPairingPayload.tryParse('{"deviceId":"sim-room-01"}'),
        isNull,
      );
    });

    test('devuelve null si los campos no son strings', () {
      expect(
        QrPairingPayload.tryParse('{"deviceId":1,"pairingCode":2}'),
        isNull,
      );
    });

    test('devuelve null si los campos están vacíos', () {
      expect(
        QrPairingPayload.tryParse('{"deviceId":"","pairingCode":"  "}'),
        isNull,
      );
    });

    test('ignora campos extra sin fallar', () {
      final payload = QrPairingPayload.tryParse(
          '{"deviceId":"sim-room-01","pairingCode":"AB12CD","extra":true}');
      expect(payload, isNotNull);
    });
  });
}
