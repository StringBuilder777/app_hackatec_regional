// Pruebas unitarias de los modelos (round-trip de serialización JSON).
// Evitamos pruebas de widget que requieran plugins nativos (notificaciones).

import 'package:flutter_test/flutter_test.dart';

import 'package:app_hackatec_regional/models/alert.dart';
import 'package:app_hackatec_regional/models/care_profile.dart';

void main() {
  test('Alert conserva sus datos al serializar y deserializar', () {
    final original = Alert(
      id: '1',
      title: 'Caída detectada',
      body: 'Posible caída en la habitación',
      severity: AlertSeverity.critical,
      status: AlertStatus.active,
      imageUrl: 'https://example.com/a.png',
      timestamp: DateTime(2026, 9, 23, 14, 30),
    );

    final restored = Alert.fromJson(original.toJson());

    expect(restored.id, '1');
    expect(restored.title, 'Caída detectada');
    expect(restored.severity, AlertSeverity.critical);
    expect(restored.status, AlertStatus.active);
    expect(restored.imageUrl, 'https://example.com/a.png');
    expect(restored.timestamp, DateTime(2026, 9, 23, 14, 30));
  });

  test('CareProfile conserva medicación, ventanas y cuidados', () {
    const original = CareProfile(
      id: 'p1',
      name: 'Abuela',
      medications: [
        MedicationReminder(id: 'm1', name: 'Aspirina', hour: 8, minute: 0),
      ],
      sleepWindow:
          TimeWindow(startHour: 22, startMinute: 0, endHour: 7, endMinute: 0),
      homeWindow:
          TimeWindow(startHour: 9, startMinute: 0, endHour: 18, endMinute: 0),
      careNeeds: ['Silla de ruedas', 'Dieta blanda'],
    );

    final restored = CareProfile.fromJson(original.toJson());

    expect(restored.name, 'Abuela');
    expect(restored.medications.length, 1);
    expect(restored.medications.first.name, 'Aspirina');
    expect(restored.sleepWindow?.startHour, 22);
    expect(restored.homeWindow?.endHour, 18);
    expect(restored.careNeeds, ['Silla de ruedas', 'Dieta blanda']);
  });
}
