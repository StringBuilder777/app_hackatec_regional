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
    _incoming.close();
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
    if (idToken.isEmpty) return;
    List<CaseSummary> cases;
    try {
      cases = await _api.listCases(idToken: idToken);
    } catch (_) {
      return;
    }
    if (cases.isEmpty) return;

    for (final c in cases) {
      final incoming = _alertFromCase(c);
      final i = _alerts.indexWhere((a) => a.id == incoming.id);
      if (i == -1) {
        _alerts.add(incoming);
        continue;
      }
      final current = _alerts[i];
      // Nunca regresar una alerta ya marcada `viewed` localmente a `active`
      // sólo porque el backend todavía diga PENDING/SENT: "vista" es una
      // decisión local del cuidador que el backend no modela.
      final keepViewed = current.status == AlertStatus.viewed &&
          incoming.status == AlertStatus.active;
      _alerts[i] =
          keepViewed ? incoming.copyWith(status: AlertStatus.viewed) : incoming;
    }
    notifyListeners();
    await _persist();
  }

  /// Mapea un caso del backend a un [Alert] de la UI. `id` = `caseId` (así
  /// [cancel]/[escalate] pueden recuperar el caso real desde `Alert.data`,
  /// que guarda el `CaseSummary` completo).
  ///
  /// Severidad: se usa `severity` si vino; si no, se asume `warning` (nunca
  /// `critical` sin que el backend lo diga explícitamente, para no
  /// sobre-alarmar).
  ///
  /// Estado: `CANCELLED` -> `canceled`; cualquier otro valor
  /// (`PENDING`/`SENT`/`ESCALATED`/`FAILED`/desconocido) -> `active`, porque
  /// todos siguen requiriendo atención o acción del cuidador. `AlertStatus`
  /// no tiene un valor "escalado" propio (no cambia lo que el cuidador debe
  /// hacer: seguir viéndolo como activo); el `alertStatus` real igual queda
  /// disponible en `data['alertStatus']` para quien lo necesite mostrar.
  Alert _alertFromCase(CaseSummary c) {
    final severity = switch (c.severity) {
      'critical' => AlertSeverity.critical,
      'warning' => AlertSeverity.warning,
      _ => AlertSeverity.warning,
    };
    final status = switch (c.alertStatus) {
      'CANCELLED' => AlertStatus.canceled,
      _ => AlertStatus.active,
    };
    return Alert(
      id: c.caseId,
      title: switch (c.eventType) {
        'VISUAL_ANOMALY' => 'Anomalía visual detectada',
        'SENSOR_ANOMALY' => 'Anomalía de sensor detectada',
        _ => 'Caso detectado',
      },
      body: 'Dispositivo ${c.deviceId} · ${c.anomalyType}',
      severity: severity,
      status: status,
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
