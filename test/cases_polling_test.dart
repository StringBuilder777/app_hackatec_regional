// Pruebas del polling de casos (contrato GET /cases): alertas especializadas,
// casos nuevos vs. viejos, actualizados, y una sola petición a la vez.

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:app_hackatec_regional/core/services/notification_service.dart';
import 'package:app_hackatec_regional/core/services/sensecare_api_service.dart';
import 'package:app_hackatec_regional/core/services/storage_service.dart';
import 'package:app_hackatec_regional/models/alert.dart';
import 'package:app_hackatec_regional/models/case_summary.dart';
import 'package:app_hackatec_regional/providers/alerts_provider.dart';

class _FakeNotifications implements NotificationService {
  @override
  dynamic noSuchMethod(Invocation invocation) => Future<void>.value();
}

class _FakeApi implements SenseCareApiService {
  List<CaseSummary> cases = [];
  int calls = 0;
  Completer<void>? hold;
  Exception? error;

  @override
  Future<List<CaseSummary>> listCases(
      {required String idToken, int? limit}) async {
    calls++;
    await hold?.future;
    if (error != null) throw error!;
    return cases;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

CaseSummary _case({
  String id = 'c1',
  String anomaly = 'PERSON_PRONE_INACTIVE',
  Duration age = Duration.zero,
  String? updatedAt,
  String? decision,
  String? dial,
}) =>
    CaseSummary.fromJson({
      'caseId': id,
      'deviceId': 'pi-demo-01',
      'eventType': 'VISUAL_ANOMALY',
      'anomalyType': anomaly,
      'severity': 'critical',
      'status': 'DETECTED',
      'humanDecision': decision,
      'dialStatus': dial,
      'createdAt': DateTime.now().toUtc().subtract(age).toIso8601String(),
      'updatedAt': updatedAt,
    });

Future<AlertsProvider> _provider(_FakeApi api) async {
  SharedPreferences.setMockInitialValues({});
  final storage = StorageService(await SharedPreferences.getInstance());
  return AlertsProvider(storage, _FakeNotifications(), api, () => 'token');
}

void main() {
  test('un caso nuevo llega como alerta especializada y dispara la llamada',
      () async {
    final api = _FakeApi()..cases = [_case()];
    final alerts = await _provider(api);
    final incoming = <Alert>[];
    alerts.incoming.listen(incoming.add);

    await alerts.refreshCases();
    await Future<void>.delayed(Duration.zero);

    final alert = alerts.byId('c1')!;
    expect(alert.title, 'Posible caída detectada');
    expect(alert.body, contains('Persona en el suelo sin moverse'));
    expect(alert.severity, AlertSeverity.critical);
    expect(incoming.map((a) => a.id), ['c1']); // Llamada automática.
  });

  test('un caso viejo entra callado (sin notificación ni llamada)', () async {
    final api = _FakeApi()..cases = [_case(age: const Duration(hours: 2))];
    final alerts = await _provider(api);
    final incoming = <Alert>[];
    alerts.incoming.listen(incoming.add);

    await alerts.refreshCases();
    await Future<void>.delayed(Duration.zero);

    expect(alerts.byId('c1'), isNotNull);
    expect(incoming, isEmpty);
  });

  test('un caso actualizado se refleja y avisa; si no cambió, no', () async {
    final api = _FakeApi()
      ..cases = [_case(updatedAt: '2026-09-24T20:00:00.000Z')];
    final alerts = await _provider(api);
    final updates = <String>[];
    alerts.caseUpdates.listen(updates.add);

    await alerts.refreshCases();
    await alerts.refreshCases(); // Mismo updatedAt: nada.
    api.cases = [
      _case(updatedAt: '2026-09-24T20:00:08.000Z', decision: 'CANCELLED'),
    ];
    await alerts.refreshCases();
    await Future<void>.delayed(Duration.zero);

    expect(alerts.byId('c1')!.status, AlertStatus.canceled);
    expect(updates, ['Caso actualizado: Posible caída detectada · cancelado']);
  });

  test('solo dialStatus confirma una llamada del sistema', () async {
    final api = _FakeApi()
      ..cases = [_case(id: 'a'), _case(id: 'b', dial: 'DIALING')];
    final alerts = await _provider(api);

    await alerts.refreshCases();

    expect(alerts.byId('a')!.body, isNot(contains('marcando')));
    expect(alerts.byId('b')!.body,
        contains('El sistema está marcando al contacto'));
  });

  test('una sola petición a la vez', () async {
    final api = _FakeApi()..hold = Completer<void>();
    final alerts = await _provider(api);

    final first = alerts.refreshCases();
    await alerts.refreshCases(); // La anterior sigue: se salta.
    expect(api.calls, 1);
    api.hold!.complete();
    await first;
  });

  test('una fecha sin zona horaria se lee como UTC', () {
    final c = CaseSummary.fromJson(
        {'caseId': 'x', 'createdAt': '2026-09-24T20:00:00'});
    expect(c.createdAt, DateTime.utc(2026, 9, 24, 20));
  });

  test('un caso sin createdAt nunca dispara la llamada', () async {
    final api = _FakeApi()
      ..cases = [
        CaseSummary.fromJson({'caseId': 'x', 'severity': 'critical'}),
      ];
    final alerts = await _provider(api);
    final incoming = <Alert>[];
    alerts.incoming.listen(incoming.add);

    await alerts.refreshCases();
    await Future<void>.delayed(Duration.zero);

    expect(alerts.byId('x'), isNotNull);
    expect(incoming, isEmpty);
  });

  test('un refresco pedido con un ciclo en vuelo se hace al terminar',
      () async {
    final api = _FakeApi()..hold = Completer<void>();
    final alerts = await _provider(api);

    final first = alerts.refreshCases();
    await alerts.refreshCases(); // P. ej. tras cancelar: queda pendiente.
    api.hold!.complete();
    await first;
    expect(api.calls, 2);
  });

  test('sin avisos por casos guardados con la versión anterior', () async {
    final api = _FakeApi()..cases = [_case(age: const Duration(hours: 2))];
    final alerts = await _provider(api);
    await alerts.refreshCases();
    // Como lo guardaba la versión anterior: sin campos del contrato.
    alerts.byId('c1')!.data
      ..remove('humanDecision')
      ..remove('dialStatus')
      ..remove('notificationStatus');
    final updates = <String>[];
    alerts.caseUpdates.listen(updates.add);
    api.cases = [_case(age: const Duration(hours: 2), dial: 'CALLED')];

    await alerts.refreshCases();
    await Future<void>.delayed(Duration.zero);

    expect(alerts.byId('c1')!.body, contains('El sistema realizó una llamada'));
    expect(updates, isEmpty);
  });

  test('un token vencido se ve y pide volver a entrar', () async {
    final api = _FakeApi()..error = const UnauthorizedException();
    final alerts = await _provider(api);

    await alerts.refreshCases();

    expect(alerts.casesError, contains('vuelve a entrar'));
    expect(alerts.casesNeedLogin, isTrue);
  });

  test('un ciclo correcto muestra cuántos casos trajo', () async {
    final api = _FakeApi()..cases = [_case(age: const Duration(hours: 2))];
    final alerts = await _provider(api);

    await alerts.refreshCases();

    expect(alerts.casesError, isNull);
    expect(alerts.casesCount, 1);
    expect(alerts.casesSyncedAt, isNotNull);
  });

  test('un campo con otro tipo no tira la lista de casos', () {
    final c = CaseSummary.fromJson(
        {'caseId': 42, 'severity': 'critical', 'dialStatus': 7});
    expect(c.caseId, '42');
    expect(c.dialStatus, '7');
  });

  testWidgets('consulta cada 5 s y deja de hacerlo al pausar', (tester) async {
    final api = _FakeApi();
    final alerts = await _provider(api);

    alerts.startPolling();
    await tester.pump();
    expect(api.calls, 1); // Refresco inmediato.
    await tester.pump(const Duration(seconds: 10));
    expect(api.calls, 3);

    alerts.stopPolling();
    await tester.pump(const Duration(seconds: 10));
    expect(api.calls, 3);
  });
}
