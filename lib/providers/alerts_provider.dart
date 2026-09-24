import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/services/notification_service.dart';
import '../core/services/sensecare_api_service.dart';
import '../core/services/storage_service.dart';
import '../models/alert.dart';
import '../models/case_decision_result.dart';
import '../models/case_summary.dart';

/// Filtro de la lista de alertas.
enum AlertFilter { all, active, viewed, canceled }

extension AlertFilterX on AlertFilter {
  String get label => switch (this) {
        AlertFilter.all => 'Todas',
        AlertFilter.active => 'Activas',
        AlertFilter.viewed => 'Vistas',
        AlertFilter.canceled => 'Canceladas',
      };
}

class AlertsProvider extends ChangeNotifier {
  static const _key = 'alerts';

  final StorageService _storage;
  final NotificationService _notifications;
  final SenseCareApiService _api;
  String? Function() _tokenProvider;

  final List<Alert> _alerts = [];
  AlertFilter _filter = AlertFilter.all;

  /// Contrato de polling de casos.
  static const pollInterval = Duration(seconds: 5);

  /// Un caso nuevo más viejo que esto entra sin notificación ni llamada.
  static const _freshCase = Duration(minutes: 10);

  Timer? _pollTimer;
  bool _syncing = false;

  /// Avisos dentro de la app de casos actualizados ("Caso actualizado: …").
  Stream<String> get caseUpdates => _caseUpdates.stream;
  final _caseUpdates = StreamController<String>.broadcast();

  /// Mensaje del último error al cancelar/escalar contra el backend (sesión
  /// expirada, sin red, etc.). `null` en éxito o cuando la alerta era
  /// puramente local. Sigue el mismo patrón que `DevicesProvider.pairError`:
  /// el provider atrapa la `ApiException` y expone el mensaje ya listo para
  /// mostrar, en vez de que la UI tenga que hacer su propio `catch`.
  String? _decisionError;
  String? get decisionError => _decisionError;

  AlertsProvider(
    this._storage,
    this._notifications,
    this._api,
    String? Function() tokenProvider,
  ) : _tokenProvider = tokenProvider {
    _load();
  }

  /// Ver `DevicesProvider.updateTokenProvider`: refresca de dónde se lee el
  /// IdToken vigente cuando `AuthProvider` cambia (login/logout), sin que la
  /// UI tenga que pasarlo a mano en cada llamada a `cancel`/`escalate`.
  void updateTokenProvider(String? Function() tokenProvider) {
    _tokenProvider = tokenProvider;
  }

  AlertFilter get filter => _filter;

  /// Alertas ordenadas (más reciente primero) y filtradas.
  List<Alert> get visibleAlerts {
    final list = _sorted();
    return switch (_filter) {
      AlertFilter.all => list,
      AlertFilter.active =>
        list.where((a) => a.status == AlertStatus.active).toList(),
      AlertFilter.viewed =>
        list.where((a) => a.status == AlertStatus.viewed).toList(),
      AlertFilter.canceled =>
        list.where((a) => a.status == AlertStatus.canceled).toList(),
    };
  }

  /// La última alerta recibida (sin importar el filtro).
  Alert? get latest => _alerts.isEmpty ? null : _sorted().first;

  int get activeCount =>
      _alerts.where((a) => a.status == AlertStatus.active).length;

  List<Alert> _sorted() =>
      [..._alerts]..sort((a, b) => b.timestamp.compareTo(a.timestamp));

  void setFilter(AlertFilter f) {
    _filter = f;
    notifyListeners();
  }

  void _load() {
    final stored = _storage.readList(_key);
    if (stored.isEmpty) {
      _alerts.addAll(_seed());
      _persist();
    } else {
      _alerts.addAll(stored.map(Alert.fromJson));
    }
  }

  Alert? byId(String id) {
    for (final a in _alerts) {
      if (a.id == id) return a;
    }
    return null;
  }

  /// Alertas nuevas según llegan; de aquí cuelga la llamada automática.
  Stream<Alert> get incoming => _incoming.stream;
  final _incoming = StreamController<Alert>.broadcast();

  /// Punto único de entrada de una alerta (simulada o desde AWS SNS -> FCM):
  /// la guarda y dispara la notificación rica.
  Future<void> receiveIncoming(Alert alert) async {
    _alerts.add(alert);
    notifyListeners();
    await _persist();
    // Antes de la notificación: la llamada automática no depende de ella.
    _incoming.add(alert);
    await _notifications.showAlert(alert);
  }

  Future<void> markViewed(String id) => _updateStatus(id, AlertStatus.viewed);

  Future<void> _updateStatus(String id, AlertStatus status) =>
      _update(id, (a) => a.copyWith(status: status));

  /// Deja constancia de la llamada automática que se hizo por la alerta.
  Future<void> recordCall(String id, String calledTo) => _update(
      id, (a) => a.copyWith(calledTo: calledTo, calledAt: DateTime.now()));

  Future<void> _update(String id, Alert Function(Alert) change) async {
    final i = _alerts.indexWhere((a) => a.id == id);
    if (i == -1) return;
    _alerts[i] = change(_alerts[i]);
    notifyListeners();
    await _persist();
  }

  @override
  void dispose() {
    stopPolling();
    _incoming.close();
    _caseUpdates.close();
    super.dispose();
  }

  Future<void> _persist() =>
      _storage.writeList(_key, _alerts.map((a) => a.toJson()).toList());

  /// Trae los casos reales del backend (`GET /cases`) y los mezcla con la
  /// lista local. Es la ÚNICA fuente de verdad para el estado de un caso
  /// real: si el `VOICE_CHECKIN` de la Pi u otro cuidador ya lo resolvió, la
  /// próxima sincronización debe reflejarlo aunque el usuario nunca haya
  /// tocado nada en esta app (ver
  /// `docs/BACKEND_ALERTS_PUSH_INTEGRATION.md` §4-5). Nunca lanza: sin
  /// sesión vigente o sin red simplemente no actualiza nada esta vez, el
  /// próximo intento de sync lo resuelve; no hay UI esperando este `Future`
  /// de forma síncrona como para necesitar propagar el error.
  Future<void> syncFromBackend(String idToken) async {
    // Una sola petición a la vez: si el ciclo previo no terminó, se salta.
    if (idToken.isEmpty || _syncing) return;
    _syncing = true;
    try {
      await _syncCases(idToken);
    } finally {
      _syncing = false;
    }
  }

  Future<void> _syncCases(String idToken) async {
    List<CaseSummary> cases;
    try {
      cases = await _api.listCases(idToken: idToken, limit: 20);
    } catch (_) {
      return;
    }
    if (cases.isEmpty) return;

    final fresh = <Alert>[];
    var changed = false;
    for (final c in cases) {
      final incoming = _alertFromCase(c);
      final i = _alerts.indexWhere((a) => a.id == incoming.id);
      if (i == -1) {
        // Caso nuevo: alerta completa (notificación y llamada automática)
        // solo si es reciente y sigue abierto; al abrir la app o emparejar,
        // los casos viejos entran callados.
        if (!c.isCancelled &&
            DateTime.now().difference(c.createdAt) < _freshCase) {
          fresh.add(incoming);
        } else {
          _alerts.add(incoming);
          changed = true;
        }
        continue;
      }
      final current = _alerts[i];
      // Mismo caseId y mismo updatedAt/estado: nada cambió.
      if (_caseVersion(current.data) == _caseVersion(incoming.data)) continue;
      // Nunca regresar una alerta ya marcada `viewed` localmente a `active`
      // sólo porque el backend todavía no la resuelva: "vista" es una
      // decisión local del cuidador que el backend no modela. La llamada
      // automática que hizo esta app también se conserva.
      final keepViewed = current.status == AlertStatus.viewed &&
          incoming.status == AlertStatus.active;
      _alerts[i] = incoming.copyWith(
        status: keepViewed ? AlertStatus.viewed : null,
        calledTo: current.calledTo,
        calledAt: current.calledAt,
      );
      changed = true;
      _caseUpdates.add('Caso actualizado: ${incoming.title} · ${_whatChanged(c)}');
    }
    if (changed) {
      notifyListeners();
      await _persist();
    }
    for (final alert in fresh) {
      await receiveIncoming(alert);
    }
  }

  /// `updatedAt` más los estados del contrato: por si un caso cambia sin que
  /// el backend mande `updatedAt` (los campos opcionales pueden faltar).
  String _caseVersion(Map<String, dynamic> d) => [
        d['updatedAt'],
        d['humanDecision'],
        d['dialStatus'],
        d['status'],
        d['notificationStatus'],
      ].join('|');

  /// Texto corto del estado de un caso actualizado. La llamada del sistema
  /// solo se menciona si `dialStatus` la confirma (contrato de polling).
  String _whatChanged(CaseSummary c) {
    if (c.isCancelled) return 'cancelado';
    if (c.isEscalated) return 'escalado';
    if (c.isDialing) return 'el sistema está marcando';
    if (c.wasCalled) return 'el sistema realizó la llamada';
    return 'nuevo estado';
  }

  /// Polling de `GET /cases` (contrato: cada 5 s con la app al frente, una
  /// sola petición a la vez). Lo arranca y lo pausa `HomeShell` según el
  /// ciclo de vida de la app; sin IdToken no consulta nada.
  void startPolling() {
    _pollTimer?.cancel();
    unawaited(refreshCases());
    _pollTimer = Timer.periodic(pollInterval, (_) => refreshCases());
  }

  void stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  /// Una consulta de `GET /cases` con el IdToken vigente.
  Future<void> refreshCases() async {
    final token = _tokenProvider();
    if (token == null || token.isEmpty) return;
    await syncFromBackend(token);
  }

  /// Línea de tiempo del caso (`GET /cases/{id}/events`): se pide al abrir
  /// el detalle, no en cada ciclo. Vacía si falla (el detalle no se traba).
  Future<List<CaseEvent>> caseEvents(String caseId) async {
    final token = _tokenProvider();
    if (token == null || token.isEmpty) return const [];
    try {
      return await _api.getCaseEvents(caseId: caseId, idToken: token);
    } catch (_) {
      return const [];
    }
  }

  /// Mapea un caso del backend a una alerta "especializada": el título dice
  /// qué detectó el dispositivo (p. ej. una persona en el suelo sin moverse)
  /// y el texto, el estado real del caso. `id` = `caseId` (así
  /// [cancel]/[escalate] recuperan el caso desde `Alert.data`, que guarda el
  /// `CaseSummary` completo).
  ///
  /// Severidad: la del backend; sin ella, `warning` (nunca `critical` sin que
  /// el backend lo diga, para no sobre-alarmar). Estado: cancelado si hubo
  /// `humanDecision: CANCELLED`; si no, activo.
  Alert _alertFromCase(CaseSummary c) {
    final severity = switch (c.severity) {
      'critical' => AlertSeverity.critical,
      'info' => AlertSeverity.info,
      _ => AlertSeverity.warning,
    };
    final (title, what) = _describeCase(c);
    final details = [
      what,
      'Dispositivo ${c.deviceId}',
      if (c.isDialing) 'El sistema está marcando al contacto',
      if (c.wasCalled) 'El sistema realizó una llamada',
      if (c.isEscalated) 'Caso escalado',
      if (c.isCancelled) 'Caso cancelado',
      if (c.evidenceStatus == 'AVAILABLE') 'Evidencia disponible',
      if (c.analysisStatus == 'COMPLETED') 'Análisis completado',
    ];
    return Alert(
      id: c.caseId,
      title: title,
      body: details.join(' · '),
      severity: severity,
      status: c.isCancelled ? AlertStatus.canceled : AlertStatus.active,
      timestamp: c.createdAt,
      data: c.toJson(),
    );
  }

  /// Cancela una alerta. Para un caso real del backend, llama
  /// `SenseCareApiService.cancelCase` y reconcilia con la respuesta (ver
  /// [_decide]); para una alerta puramente local (`seed-*`/`sim-*` de demo)
  /// sólo cambia el estado local, como siempre.
  Future<CaseDecisionResult?> cancel(String id) => _decide(id, escalate: false);

  /// Escala una alerta. Sólo tiene efecto contra el backend si la alerta
  /// viene de un caso real (`Alert.data['caseId']`); una alerta puramente
  /// local no tiene contraparte que escalar, así que no hace nada.
  Future<CaseDecisionResult?> escalate(String id) => _decide(id, escalate: true);

  /// Núcleo compartido de `cancel`/`escalate` contra el backend. Antes de
  /// tocar el estado local, llama al backend y sólo aplica lo que éste
  /// confirme -- incluido un 409, donde [_applyDecision] refleja el
  /// `alertStatus` REAL en vez de lo que el usuario pidió (ver
  /// `CaseDecisionResult`). Devuelve `null` cuando no hubo nada que
  /// confirmar contra el backend (alerta local) o cuando falló la llamada
  /// (mensaje queda en [decisionError]); devuelve el [CaseDecisionResult]
  /// cuando sí se llamó al backend, con o sin conflicto, para que la UI
  /// pueda mostrar el resultado exacto.
  Future<CaseDecisionResult?> _decide(String id, {required bool escalate}) async {
    _decisionError = null;
    final i = _alerts.indexWhere((a) => a.id == id);
    if (i == -1) return null;
    final alert = _alerts[i];
    final caseId = alert.data['caseId'] as String?;

    if (caseId == null || caseId.isEmpty) {
      // Alerta puramente local: no existe como caso en el backend. Cancelar
      // sigue funcionando como antes (siempre disponible en la demo);
      // "escalar" no tiene contraparte local que aplicar.
      if (!escalate) await _updateStatus(id, AlertStatus.canceled);
      return null;
    }

    final token = _tokenProvider();
    if (token == null || token.isEmpty) {
      _decisionError = 'Tu sesión expiró. Vuelve a iniciar sesión.';
      notifyListeners();
      return null;
    }

    try {
      final result = escalate
          ? await _api.escalateCase(caseId: caseId, idToken: token)
          : await _api.cancelCase(caseId: caseId, idToken: token);
      _applyDecision(id, result);
      // Contrato: tras cancelar/escalar (o un 409) se refresca /cases ya.
      unawaited(syncFromBackend(token));
      return result;
    } on ApiException catch (e) {
      _decisionError = e.message;
      notifyListeners();
      return null;
    }
  }

  /// Aplica el `alertStatus` REAL devuelto por el backend (haya habido
  /// conflicto o no) al estado local, y guarda ese `alertStatus` en
  /// `data` para que quede visible aunque `AlertStatus` no distinga
  /// "escalado" de "activo".
  void _applyDecision(String id, CaseDecisionResult result) {
    final i = _alerts.indexWhere((a) => a.id == id);
    if (i == -1) return;
    final status = switch (result.alertStatus) {
      'CANCELLED' => AlertStatus.canceled,
      _ => AlertStatus.active,
    };
    final current = _alerts[i];
    _alerts[i] = current.copyWith(
      status: status,
      data: {...current.data, 'alertStatus': result.alertStatus},
    );
    notifyListeners();
    unawaited(_persist());
  }

  /// Datos de ejemplo para que la lista no esté vacía en el primer arranque.
  List<Alert> _seed() {
    final now = DateTime.now();
    return [
      Alert(
        id: 'seed-1',
        title: 'Caída detectada',
        body: 'El sensor detectó una posible caída en la habitación.',
        severity: AlertSeverity.critical,
        timestamp: now.subtract(const Duration(minutes: 5)),
      ),
      Alert(
        id: 'seed-2',
        title: 'Medicación no tomada',
        body: 'No se registró la toma de las 8:00 a.m.',
        severity: AlertSeverity.warning,
        status: AlertStatus.viewed,
        timestamp: now.subtract(const Duration(hours: 3)),
      ),
      Alert(
        id: 'seed-3',
        title: 'Puerta abierta',
        body: 'La puerta principal permaneció abierta 10 minutos.',
        severity: AlertSeverity.info,
        status: AlertStatus.canceled,
        timestamp: now.subtract(const Duration(days: 1)),
      ),
    ];
  }
}

/// Título y descripción según lo que detectó el dispositivo. "Caída" en el
/// título hace que la voz de la llamada automática diga "se cayó".
(String, String) _describeCase(CaseSummary c) => switch (c.anomalyType) {
      'PERSON_PRONE_INACTIVE' => (
          'Posible caída detectada',
          'Persona en el suelo sin moverse'
        ),
      'FALL_DETECTED' => ('Caída detectada', 'El dispositivo detectó una caída'),
      _ => (
          switch (c.eventType) {
            'VISUAL_ANOMALY' => 'Anomalía visual detectada',
            'SENSOR_ANOMALY' => 'Anomalía de sensor detectada',
            _ => 'Caso detectado',
          },
          _humanize(c.anomalyType),
        ),
    };

String _humanize(String code) {
  if (code.isEmpty) return 'Sin detalle';
  final text = code.toLowerCase().replaceAll('_', ' ');
  return text[0].toUpperCase() + text.substring(1);
}
