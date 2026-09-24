// Pruebas de la llamada automática: a quién se llama, qué dice la voz y cuándo
// se marca. Teléfono, voz y notificaciones van simulados (sin plugins nativos).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:app_hackatec_regional/core/services/notification_service.dart';
import 'package:app_hackatec_regional/core/services/phone_call_service.dart';
import 'package:app_hackatec_regional/core/services/sensecare_api_service.dart';
import 'package:app_hackatec_regional/core/services/storage_service.dart';
import 'package:app_hackatec_regional/core/services/voice_service.dart';
import 'package:app_hackatec_regional/features/alerts/emergency_call_banner.dart';
import 'package:app_hackatec_regional/models/alert.dart';
import 'package:app_hackatec_regional/models/care_profile.dart';
import 'package:app_hackatec_regional/models/emergency_call.dart';
import 'package:app_hackatec_regional/providers/alerts_provider.dart';
import 'package:app_hackatec_regional/providers/emergency_call_provider.dart';
import 'package:app_hackatec_regional/providers/profiles_provider.dart';

class _FakeNotifications implements NotificationService {
  @override
  dynamic noSuchMethod(Invocation invocation) => Future<void>.value();
}

/// Teléfono simulado: `placeCall` deja la llamada activa hasta que la prueba
/// cuelga (`inCall = false`).
class _FakePhone implements PhoneCallService {
  final dialed = <String>[];
  bool granted = true;
  bool inCall = false;

  /// Simula un error inesperado al marcar (el servicio real nunca lanza).
  bool crash = false;

  @override
  Future<bool> requestPermission() async => granted;

  @override
  Future<bool> placeCall(String number) async {
    if (crash) throw StateError('falla simulada');
    if (!granted) return false;
    dialed.add(number);
    inCall = true;
    return true;
  }

  @override
  Future<bool> isInCall() async => inCall;
}

class _FakeVoice implements VoiceService {
  final said = <String>[];
  int stops = 0;

  @override
  Future<void> speak(String text) async => said.add(text);

  @override
  Future<void> stop() async => stops++;
}

const _luis = CareProfile(
  id: 'luis',
  name: 'Luis Emilio Pérez',
  address: 'Calle Juárez 123, Centro',
  responsible: CareContact(name: 'Ana', phone: '5511112222'),
  emergencyContact: CareContact(name: 'Beto', phone: '5533334444'),
);

Alert _alert(AlertSeverity severity,
        {String title = 'Caída detectada',
        String body = 'Posible caída en la habitación principal.'}) =>
    Alert(
      id: 'a-${severity.name}',
      title: title,
      body: body,
      severity: severity,
      timestamp: DateTime(2026, 9, 24, 10),
    );

Alert _critical(String id, {String? profileId}) => Alert(
      id: id,
      title: 'Caída detectada',
      body: '',
      severity: AlertSeverity.critical,
      timestamp: DateTime(2026, 9, 24, 11),
      data: {'profileId': ?profileId},
    );

AutoCallState? _state(EmergencyCallProvider calls, String alertId) =>
    calls.calls.where((c) => c.alert.id == alertId).firstOrNull?.state;

void main() {
  group('datos', () {
    test('CareProfile conserva dirección y contactos', () {
      final restored = CareProfile.fromJson(
          _luis.copyWith(userIsResponsible: true).toJson());
      expect(restored.address, 'Calle Juárez 123, Centro');
      expect(restored.responsible.phone, '5511112222');
      expect(restored.userIsResponsible, isTrue);
      expect(restored.emergencyContact.name, 'Beto');
    });

    test('un perfil guardado antes de esta versión carga sin contactos', () {
      final old = CareProfile.fromJson({'id': 'p1', 'name': 'Abuela'});
      expect(old.address, '');
      expect(old.responsible.hasPhone, isFalse);
      expect(old.userIsResponsible, isFalse);
    });

    test('Alert conserva la llamada automática registrada', () {
      final called = _alert(AlertSeverity.critical).copyWith(
          calledTo: 'Ana (responsable)', calledAt: DateTime(2026, 9, 24, 10, 5));
      final restored = Alert.fromJson(called.toJson());
      expect(restored.calledTo, 'Ana (responsable)');
      expect(restored.calledAt, DateTime(2026, 9, 24, 10, 5));
    });
  });

  group('a quién llamar', () {
    test('al responsable si el usuario no lo es', () {
      final target = callTargetFor(_luis)!;
      expect(target.kind, CallTargetKind.responsible);
      expect(target.contact.phone, '5511112222');
      expect(target.label, 'Ana (responsable)');
    });

    test('al contacto de emergencia si el usuario es el responsable', () {
      final target = callTargetFor(_luis.copyWith(userIsResponsible: true))!;
      expect(target.kind, CallTargetKind.emergencyContact);
      expect(target.contact.phone, '5533334444');
    });

    test('a nadie si falta el teléfono', () {
      expect(
          callTargetFor(
              _luis.copyWith(responsible: const CareContact(name: 'Ana'))),
          isNull);
    });

    test('solo las graves y las advertencias llaman', () {
      expect(autoCallDelay(AlertSeverity.critical), const Duration(seconds: 15));
      expect(autoCallDelay(AlertSeverity.warning), const Duration(seconds: 60));
      expect(autoCallDelay(AlertSeverity.info), isNull);
    });
  });

  group('lo que dice la voz', () {
    test('al responsable: qué pasó y si puede llegar', () {
      final script = callScript(
          _alert(AlertSeverity.critical), _luis, callTargetFor(_luis)!);
      expect(script, contains('Hola, Ana.'));
      expect(script, contains('Luis Emilio Pérez tuvo un accidente: se cayó.'));
      expect(script, contains('¿Puedes llegar para ayudarle?'));
      expect(script, contains('9 1 1'));
    });

    test('al contacto de emergencia: quién es, qué pasó y la dirección', () {
      final profile = _luis.copyWith(userIsResponsible: true);
      final script = callScript(
          _alert(AlertSeverity.critical), profile, callTargetFor(profile)!);
      expect(script, contains('Luis Emilio Pérez se cayó.'));
      expect(script,
          contains('Es una persona adulta mayor y necesita ayuda.'));
      expect(script, contains('La dirección es: Calle Juárez 123, Centro.'));
    });

    test('si no es una caída, dice el título de la alerta', () {
      final alert = _alert(AlertSeverity.warning,
          title: 'Medicación pendiente',
          body: 'No se ha registrado la toma programada.');
      expect(situationOf(alert),
          'tiene una alerta sin atender: Medicación pendiente');
    });

    test('en una advertencia no pide llamar al 911', () {
      final alert = _alert(AlertSeverity.warning,
          title: 'Medicación pendiente',
          body: 'No se ha registrado la toma programada.');
      for (final p in [_luis, _luis.copyWith(userIsResponsible: true)]) {
        expect(callScript(alert, p, callTargetFor(p)!),
            isNot(contains('9 1 1')));
      }
    });

    test('"riesgo de caída" y "recaída" no son una caída', () {
      bool fall(String title, [String body = '']) =>
          isFall(_alert(AlertSeverity.warning, title: title, body: body));
      expect(fall('Riesgo de caída'), isFalse);
      expect(fall('Recaída de presión'), isFalse);
      expect(fall('Alerta', 'Se cayó en la sala.'), isTrue);
      expect(fall('Caída detectada'), isTrue);
    });
  });

  group('llamada automática', () {
    late AlertsProvider alerts;
    late _FakePhone phone;
    late _FakeVoice voice;

    Future<EmergencyCallProvider> setUpCalls(CareProfile profile,
        {List<CareProfile> more = const []}) async {
      SharedPreferences.setMockInitialValues({});
      final storage = StorageService(await SharedPreferences.getInstance());
      final notifications = _FakeNotifications();
      alerts = AlertsProvider(
          storage, notifications, SenseCareApiService(), () => null);
      final profiles = ProfilesProvider(storage, notifications);
      for (final p in [profile, ...more]) {
        await profiles.upsert(p);
      }
      phone = _FakePhone();
      voice = _FakeVoice();
      return EmergencyCallProvider(alerts, profiles, phone, voice);
    }

    /// Cuelgan: la voz calla y se libera el turno de la siguiente llamada.
    Future<void> hangUp(WidgetTester tester) async {
      phone.inCall = false;
      await tester.pump(const Duration(seconds: 10));
    }

    testWidgets('grave: avisa, marca al responsable a los 15 s y la voz habla',
        (tester) async {
      final calls = await setUpCalls(_luis);
      await alerts.receiveIncoming(_alert(AlertSeverity.critical));
      await tester.pump(const Duration(seconds: 14));
      expect(phone.dialed, isEmpty);
      expect(voice.said.first,
          startsWith('Alerta grave. Luis Emilio Pérez se cayó.'));

      await tester.pump(const Duration(seconds: 1));
      expect(phone.dialed, ['5511112222']);
      expect(calls.calls.single.voiceDone, isFalse); // Aún no habla.

      await tester.pump(const Duration(seconds: 15)); // Timbre y mensajes.
      expect(voice.said, contains('Llamando a Ana.'));
      expect(voice.said.where((s) => s.startsWith('Hola, Ana.')), hasLength(1));
      expect(voice.said.where((s) => s.startsWith('Repito.')), isNotEmpty);
      expect(alerts.byId('a-critical')!.calledTo, 'Ana (responsable)');
      // Sigue "llamando" hasta que cuelgan, aunque la voz ya terminó.
      expect(_state(calls, 'a-critical'), AutoCallState.calling);
      expect(calls.calls.single.voiceDone, isTrue);

      await hangUp(tester);
      expect(calls.calls, isEmpty);
    });

    testWidgets('si el usuario es el responsable, llama a su contacto',
        (tester) async {
      await setUpCalls(_luis.copyWith(userIsResponsible: true));
      await alerts.receiveIncoming(_alert(AlertSeverity.critical));
      await tester.pump(const Duration(seconds: 15));
      expect(phone.dialed, ['5533334444']);
      await hangUp(tester);
    });

    testWidgets('advertencia sin atender: llama al minuto', (tester) async {
      await setUpCalls(_luis);
      await alerts.receiveIncoming(_alert(AlertSeverity.warning));
      await tester.pump(const Duration(seconds: 59));
      expect(phone.dialed, isEmpty);
      await tester.pump(const Duration(seconds: 1));
      expect(phone.dialed, ['5511112222']);
      await hangUp(tester);
    });

    testWidgets('advertencia atendida a tiempo: no llama', (tester) async {
      final calls = await setUpCalls(_luis);
      await alerts.receiveIncoming(_alert(AlertSeverity.warning));
      await tester.pump(const Duration(seconds: 30));
      await alerts.markViewed('a-warning');
      await tester.pump(const Duration(seconds: 40));
      expect(phone.dialed, isEmpty);
      expect(calls.calls, isEmpty);
    });

    testWidgets('grave vista igual llama; cancelada (falsa alarma) no',
        (tester) async {
      await setUpCalls(_luis);
      await alerts.receiveIncoming(_alert(AlertSeverity.critical));
      await alerts.markViewed('a-critical');
      await tester.pump(const Duration(seconds: 15));
      expect(phone.dialed, hasLength(1));
      await hangUp(tester);

      await alerts.receiveIncoming(_critical('b'));
      await alerts.cancel('b');
      await tester.pump(const Duration(seconds: 20));
      expect(phone.dialed, hasLength(1));
    });

    testWidgets('"No llamar" cancela y "Llamar ahora" marca de inmediato',
        (tester) async {
      final calls = await setUpCalls(_luis);
      await alerts.receiveIncoming(_alert(AlertSeverity.critical));
      await tester.pump();
      calls.cancel('a-critical');
      await tester.pump(const Duration(seconds: 20));
      expect(phone.dialed, isEmpty);

      await alerts.receiveIncoming(_alert(AlertSeverity.warning));
      await tester.pump();
      await calls.callNow('a-warning');
      await tester.pump();
      expect(phone.dialed, ['5511112222']);
      await hangUp(tester);
    });

    testWidgets('sin permiso de llamadas queda como fallida', (tester) async {
      final calls = await setUpCalls(_luis);
      phone.granted = false;
      await alerts.receiveIncoming(_alert(AlertSeverity.critical));
      await tester.pump(const Duration(seconds: 15));
      expect(phone.dialed, isEmpty);
      expect(calls.calls.single.state, AutoCallState.failed);
    });

    testWidgets('una llamada en espera de turno se cancela con su alerta',
        (tester) async {
      final calls = await setUpCalls(_luis);
      await alerts.receiveIncoming(_alert(AlertSeverity.critical));
      await tester.pump(const Duration(seconds: 5));
      await alerts.receiveIncoming(_critical('b'));
      await tester.pump(const Duration(seconds: 15)); // A en llamada; B en cola.
      expect(phone.dialed, hasLength(1));
      expect(_state(calls, 'b'), AutoCallState.queued);

      await alerts.cancel('b');
      expect(_state(calls, 'b'), isNull);
      await hangUp(tester); // A cuelga: B ya no debe marcar.
      await tester.pump(const Duration(seconds: 10));
      expect(phone.dialed, hasLength(1));
    });

    testWidgets('"No llamar" también sirve con la llamada en espera',
        (tester) async {
      final calls = await setUpCalls(_luis);
      await alerts.receiveIncoming(_alert(AlertSeverity.critical));
      await tester.pump(const Duration(seconds: 5));
      await alerts.receiveIncoming(_critical('b'));
      await tester.pump(const Duration(seconds: 15));
      calls.cancel('b');
      await hangUp(tester);
      await tester.pump(const Duration(seconds: 10));
      expect(phone.dialed, hasLength(1));
    });

    testWidgets('la siguiente marca cuando cuelgan, no cuando calla la voz',
        (tester) async {
      final calls = await setUpCalls(_luis);
      await alerts.receiveIncoming(_alert(AlertSeverity.critical));
      await tester.pump(const Duration(seconds: 5));
      await alerts.receiveIncoming(_critical('b'));
      await tester.pump(const Duration(seconds: 17)); // A hablando; B en cola.
      await calls.stopVoice(); // Ana sigue en la línea.
      await tester.pump(const Duration(seconds: 30));
      expect(phone.dialed, hasLength(1));
      expect(_state(calls, 'a-critical'), AutoCallState.calling);
      expect(_state(calls, 'b'), AutoCallState.queued);

      await hangUp(tester); // Ana cuelga: ahora sí marca B.
      expect(phone.dialed, hasLength(2));
      await hangUp(tester);
    });

    testWidgets('con el teléfono ocupado espera a que cuelguen para marcar',
        (tester) async {
      final calls = await setUpCalls(_luis);
      phone.inCall = true; // El cuidador ya está en otra llamada.
      await alerts.receiveIncoming(_alert(AlertSeverity.critical));
      await tester.pump(const Duration(seconds: 20));
      expect(phone.dialed, isEmpty);
      expect(_state(calls, 'a-critical'), AutoCallState.queued);

      await hangUp(tester); // Cuelga su llamada: ahora sí marca.
      expect(phone.dialed, ['5511112222']);
      await hangUp(tester);
    });

    testWidgets('con el teléfono ocupado, "No llamar" evita que marque',
        (tester) async {
      final calls = await setUpCalls(_luis);
      phone.inCall = true;
      await alerts.receiveIncoming(_alert(AlertSeverity.critical));
      await tester.pump(const Duration(seconds: 20));
      calls.cancel('a-critical');
      await hangUp(tester);
      expect(phone.dialed, isEmpty);
      expect(calls.calls, isEmpty);
    });

    testWidgets('si algo lanza al marcar, la cola no se traba',
        (tester) async {
      final calls = await setUpCalls(_luis);
      phone.crash = true;
      await alerts.receiveIncoming(_alert(AlertSeverity.critical));
      await tester.pump(const Duration(seconds: 15));
      expect(tester.takeException(), isA<StateError>()); // Se reporta.
      expect(_state(calls, 'a-critical'), AutoCallState.failed);

      phone.crash = false;
      await alerts.receiveIncoming(_critical('b'));
      await tester.pump(const Duration(seconds: 15));
      expect(phone.dialed, ['5511112222']);
      await hangUp(tester);
    });

    testWidgets('"No llamar" no corta el aviso de otra cuenta regresiva',
        (tester) async {
      final calls = await setUpCalls(_luis);
      await alerts.receiveIncoming(_alert(AlertSeverity.critical));
      await alerts.receiveIncoming(_alert(AlertSeverity.warning));
      await tester.pump();
      calls.cancel('a-warning');
      expect(voice.stops, 0); // La grave sigue contando: su aviso sigue.
      calls.cancel('a-critical');
      expect(voice.stops, 1);
    });

    testWidgets('en una llamada, aunque la voz ya terminó, nadie habla encima',
        (tester) async {
      final calls = await setUpCalls(_luis);
      await alerts.receiveIncoming(_alert(AlertSeverity.critical));
      await tester.pump(const Duration(seconds: 40)); // Mensajes ya dichos.
      final before = voice.said.length;
      await alerts.receiveIncoming(_critical('b'));
      await tester.pump();
      expect(voice.said.skip(before).where((s) => s.startsWith('Alerta grave')),
          isEmpty);
      calls.cancel('b');
      await hangUp(tester);
    });

    testWidgets('una fallida se quita si cancelan su alerta; "Reintentar" marca',
        (tester) async {
      final calls = await setUpCalls(_luis);
      phone.granted = false;
      await alerts.receiveIncoming(_alert(AlertSeverity.critical));
      await alerts.receiveIncoming(_critical('b'));
      await tester.pump(const Duration(seconds: 15));
      expect(_state(calls, 'a-critical'), AutoCallState.failed);
      expect(_state(calls, 'b'), AutoCallState.failed);

      await alerts.cancel('b');
      expect(_state(calls, 'b'), isNull);

      phone.granted = true;
      await calls.callNow('a-critical');
      await tester.pump();
      expect(phone.dialed, ['5511112222']);
      await hangUp(tester);
    });

    testWidgets('llama por el perfil del push; pausado o desconocido no llama',
        (tester) async {
      const juan = CareContact(name: 'Juan', phone: '5555556666');
      const rosa = CareProfile(id: 'rosa', name: 'Rosa', responsible: juan);
      const pepe = CareProfile(
          id: 'pepe', name: 'Pepe', responsible: juan, enabled: false);
      final calls = await setUpCalls(_luis, more: [rosa, pepe]);
      await alerts.receiveIncoming(_critical('r', profileId: 'rosa'));
      await tester.pump(const Duration(seconds: 15));
      expect(phone.dialed, ['5555556666']);
      await hangUp(tester);

      await alerts.receiveIncoming(_critical('p', profileId: 'pepe'));
      await tester.pump();
      expect(calls.notice, contains('"Pepe" está pausado'));
      await alerts.receiveIncoming(_critical('x', profileId: 'nadie'));
      await tester.pump(const Duration(seconds: 20));
      expect(calls.notice, contains('no se encontró el perfil'));
      expect(phone.dialed, hasLength(1));
    });

    testWidgets('el aviso flota sobre cualquier pantalla y "No llamar" cancela',
        (tester) async {
      final calls = await setUpCalls(_luis);
      final navigator = GlobalKey<NavigatorState>();
      await tester.pumpWidget(ChangeNotifierProvider.value(
        value: calls,
        child: MaterialApp(
          navigatorKey: navigator,
          builder: withEmergencyCallBanner, // El mismo de main.dart.
          home: const Scaffold(body: Text('Alertas')),
        ),
      ));
      // Una pantalla encima, como el formulario de un perfil.
      navigator.currentState!.push(MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('Formulario'))));
      await tester.pumpAndSettle();

      await alerts.receiveIncoming(_alert(AlertSeverity.critical));
      await tester.pump();
      expect(find.text('Formulario'), findsOneWidget);
      expect(find.text('Llamaré a Ana (responsable) en 15 s'), findsOneWidget);

      await tester.tap(find.text('No llamar'));
      await tester.pump();
      expect(find.text('No llamar'), findsNothing);
      expect(calls.calls, isEmpty);
    });

    testWidgets('en llamada, el aviso muestra la voz y luego la espera',
        (tester) async {
      final calls = await setUpCalls(_luis);
      await tester.pumpWidget(ChangeNotifierProvider.value(
        value: calls,
        child: const MaterialApp(
          builder: withEmergencyCallBanner,
          home: Scaffold(body: Text('Alertas')),
        ),
      ));
      await alerts.receiveIncoming(_alert(AlertSeverity.critical));
      await tester.pump(const Duration(seconds: 15)); // Marca.
      expect(find.text('Llamando a Ana (responsable)…'), findsOneWidget);
      expect(find.text('Detener voz'), findsOneWidget);

      await tester.pump(const Duration(seconds: 15)); // La voz ya terminó.
      expect(find.text('En llamada con Ana (responsable)'), findsOneWidget);
      expect(find.text('Detener voz'), findsNothing);

      await hangUp(tester);
      expect(find.textContaining('Ana (responsable)'), findsNothing);
    });

    testWidgets('informativa no llama; sin teléfono no llama y avisa',
        (tester) async {
      final calls = await setUpCalls(
          _luis.copyWith(responsible: const CareContact(name: 'Ana')));
      await alerts.receiveIncoming(_alert(AlertSeverity.info));
      await tester.pump();
      expect(calls.notice, isNull);

      await alerts.receiveIncoming(_alert(AlertSeverity.critical));
      await tester.pump(const Duration(seconds: 20));
      expect(phone.dialed, isEmpty);
      expect(calls.notice, contains('agrega el teléfono del responsable'));
    });
  });
}
