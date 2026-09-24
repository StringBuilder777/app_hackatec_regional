// Pruebas del indicador de "en vivo" / "obsoleto": requisito de producto es
// no presentar una lectura como en vivo si no se actualizó hace 15+ s.

import 'package:flutter_test/flutter_test.dart';

import 'package:app_hackatec_regional/features/devices/freshness.dart';

void main() {
  group('isFresh', () {
    test('null -> no es fresco', () {
      expect(isFresh(null), isFalse);
    });

    test('hace 5 segundos -> es fresco', () {
      final t = DateTime.now().toUtc().subtract(const Duration(seconds: 5));
      expect(isFresh(t), isTrue);
    });

    test('hace exactamente 15 segundos -> todavía es fresco (límite incluido)',
        () {
      // Misma "hora actual" para ambos lados: con dos DateTime.now() la
      // diferencia es 15 s + unos microsegundos y la prueba fallaba.
      final now = DateTime.now().toUtc();
      final t = now.subtract(const Duration(seconds: 15));
      expect(isFresh(t, now: now), isTrue);
    });

    test('hace 20 segundos -> ya no es fresco', () {
      final t = DateTime.now().toUtc().subtract(const Duration(seconds: 20));
      expect(isFresh(t), isFalse);
    });

    test('hace varios minutos -> no es fresco', () {
      final t = DateTime.now().toUtc().subtract(const Duration(minutes: 5));
      expect(isFresh(t), isFalse);
    });
  });

  group('lastSeenLabel', () {
    test('null -> "Sin lecturas todavía"', () {
      expect(lastSeenLabel(null), 'Sin lecturas todavía');
    });

    test('hace 2 segundos -> "justo ahora"', () {
      final t = DateTime.now().toUtc().subtract(const Duration(seconds: 2));
      expect(lastSeenLabel(t), contains('justo ahora'));
    });

    test('hace 30 segundos -> en segundos', () {
      final t = DateTime.now().toUtc().subtract(const Duration(seconds: 30));
      expect(lastSeenLabel(t), contains('s'));
    });

    test('hace 5 minutos -> en minutos', () {
      final t = DateTime.now().toUtc().subtract(const Duration(minutes: 5));
      expect(lastSeenLabel(t), contains('min'));
    });

    test('hace 3 horas -> en horas', () {
      final t = DateTime.now().toUtc().subtract(const Duration(hours: 3));
      expect(lastSeenLabel(t), contains('h'));
    });

    test('hace 2 días -> en días', () {
      final t = DateTime.now().toUtc().subtract(const Duration(days: 2));
      expect(lastSeenLabel(t), contains('d'));
    });
  });
}
