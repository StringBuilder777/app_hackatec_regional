import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/services/phone_call_service.dart';
import '../core/services/voice_service.dart';
import '../models/alert.dart';
import '../models/care_profile.dart';
import '../models/emergency_call.dart';
import 'alerts_provider.dart';
import 'profiles_provider.dart';

enum AutoCallState { countdown, queued, calling, failed }

/// Llamada automática de una alerta: en cuenta regresiva, esperando a que
/// termine otra llamada, marcando o fallida.
class AutoCall {
  final Alert alert;
  final CareProfile profile;
  final CallTarget target;
  final int totalSeconds;
  int secondsLeft;
  AutoCallState state = AutoCallState.countdown;

  /// En llamada, la voz ya terminó (o se detuvo): solo falta que cuelguen.
  bool voiceDone = false;

  AutoCall({
    required this.alert,
    required this.profile,
    required this.target,
    required this.totalSeconds,
  }) : secondsLeft = totalSeconds;
}

/// Llamada automática de emergencia: si una alerta es grave o nadie la
/// atiende, marca al responsable (o al contacto de emergencia si el usuario es
/// el responsable) y una voz explica la situación dentro de la llamada.
class EmergencyCallProvider extends ChangeNotifier {
  /// Espera antes de hablar (no se sabe cuándo contestan) y repeticiones.
  static const _ringTime = Duration(seconds: 6);
  static const _maxRepeats = 5;

  /// Tope para esperar a que cuelguen, por si Android no reporta el fin.
  static const _maxCall = Duration(minutes: 30);

  final AlertsProvider _alerts;
  final ProfilesProvider _profiles;
  final PhoneCallService _phone;
  final VoiceService _voice;

  final Map<String, AutoCall> _calls = {};
  late final StreamSubscription<Alert> _incomingSub;
  Timer? _ticker;
  Future<void> _dialQueue = Future.value();
  bool _voiceStopped = false;
  String? _notice;

  EmergencyCallProvider(this._alerts, this._profiles, this._phone, this._voice) {
    _incomingSub = _alerts.incoming.listen(_schedule);
    _alerts.addListener(_onAlertsChanged);
  }

  List<AutoCall> get calls => List.unmodifiable(_calls.values);

  /// Aviso cuando una alerta debió llamar y no pudo (p. ej. sin teléfono).
  String? get notice => _notice;

  Future<bool> requestPermission() => _phone.requestPermission();

  bool get _inCall =>
      _calls.values.any((c) => c.state == AutoCallState.calling);

  void _schedule(Alert alert) {
    final delay = autoCallDelay(alert.severity);
    if (delay == null) return;
    final profile = _profileFor(alert);
    final target =
        profile != null && profile.enabled ? callTargetFor(profile) : null;
    if (profile == null || target == null) {
      _notice = _missingTargetNotice(alert, profile);
      notifyListeners();
      return;
    }
    final call = AutoCall(
        alert: alert,
        profile: profile,
        target: target,
        totalSeconds: delay.inSeconds);
    _calls[alert.id] = call;
    _syncTicker();
    notifyListeners();
    // Se pide ahora, con la app al frente; al marcar ya no hay quien lo acepte.
    unawaited(_phone.requestPermission());
    // Con una llamada en curso, el aviso se oiría dentro de ella.
    if (alert.severity == AlertSeverity.critical && !_inCall) {
      unawaited(_voice.speak(
          countdownAnnouncement(alert, profile, target, call.secondsLeft)));
    }
  }

  /// El perfil de la alerta (`profileId` del push) o, si no lo trae, el primer
  /// perfil activo.
  CareProfile? _profileFor(Alert alert) {
    final id = alert.profileId;
    if (id != null) return _profiles.byId(id);
    return _profiles.profiles.where((p) => p.enabled).firstOrNull;
  }

  String _missingTargetNotice(Alert alert, CareProfile? profile) {
    const prefix = 'Alerta sin llamada automática: ';
    if (profile == null) {
      return alert.profileId != null
          ? '${prefix}no se encontró el perfil de la alerta.'
          : '${prefix}crea un perfil activo en Perfil.';
    }
    if (!profile.enabled) {
      return '${prefix}el perfil "${profile.name}" está pausado.';
    }
    final who = profile.userIsResponsible
        ? 'de tu contacto de emergencia'
        : 'del responsable';
    return '${prefix}en Perfil, agrega el teléfono $who en "${profile.name}".';
  }

  /// Una alerta cancelada (falsa alarma) nunca llama; una advertencia deja de
  /// llamar en cuanto alguien la atiende. Las graves llaman aunque se vean.
  bool _stillNeeded(AutoCall call) {
    final status = _alerts.byId(call.alert.id)?.status ?? AlertStatus.canceled;
    if (status == AlertStatus.canceled) return false;
    return call.alert.severity == AlertSeverity.critical ||
        status == AlertStatus.active;
  }

  /// Quita las llamadas que ya no hacen falta: en cuenta regresiva, en espera
  /// de turno o fallidas. La que está en curso ya no se puede deshacer.
  void _onAlertsChanged() {
    final stale = [
      for (final c in _calls.values)
        if (c.state != AutoCallState.calling && !_stillNeeded(c)) c.alert.id,
    ];
    if (stale.isEmpty) return;
    stale.forEach(_calls.remove);
    _stopVoiceIfIdle();
    _syncTicker();
    notifyListeners();
  }

  void _syncTicker() {
    final counting =
        _calls.values.any((c) => c.state == AutoCallState.countdown);
    if (counting) {
      _ticker ??= Timer.periodic(const Duration(seconds: 1), (_) => _tick());
    } else {
      _ticker?.cancel();
      _ticker = null;
    }
  }

  void _tick() {
    for (final call in [..._calls.values]) {
      if (call.state != AutoCallState.countdown) continue;
      call.secondsLeft--;
      if (call.secondsLeft <= 0) _startDialing(call);
    }
    _syncTicker();
    notifyListeners();
  }

  void _startDialing(AutoCall call) {
    // Una a la vez: el teléfono no puede sostener dos llamadas salientes. En
    // la cola sigue cancelable ("No llamar" o si su alerta se atiende).
    call.state = AutoCallState.queued;
    _dialQueue = _dialQueue
        .then((_) => _dial(call))
        .catchError((Object e, StackTrace stack) {
      // Nada en _dial debería lanzar; si pasa, que no trabe la cola, pero que
      // el error se vea con su stack en vez de tragárselo.
      FlutterError.reportError(FlutterErrorDetails(
          exception: e, stack: stack, library: 'llamada automática'));
      call.state = AutoCallState.failed;
      notifyListeners();
    });
  }

  Future<void> _dial(AutoCall call) async {
    // Si el teléfono ya está en otra llamada, espera en la cola (cancelable).
    await _waitWhileInCall(() => _calls[call.alert.id] == call);
    if (_calls[call.alert.id] != call) return; // Se canceló en la cola.
    call.state = AutoCallState.calling;
    call.voiceDone = false;
    _voiceStopped = false;
    notifyListeners();
    // Sin esperar a la voz: marcar no puede depender del motor de voz.
    unawaited(_voice.speak('Llamando a ${call.target.name}.'));
    if (!await _phone.placeCall(call.target.contact.phone)) {
      call.state = AutoCallState.failed;
      notifyListeners();
      return;
    }
    try {
      await _alerts.recordCall(call.alert.id, call.target.label);
    } catch (e) {
      // La llamada ya salió: que un fallo al guardar no la dé por fallida.
      debugPrint('No se pudo registrar la llamada: $e');
    }
    await _speakDuringCall(callScript(call.alert, call.profile, call.target));
    call.voiceDone = true;
    notifyListeners();
    // El turno se libera cuando cuelgan, no cuando calla la voz.
    await _waitWhileInCall();
    if (_calls[call.alert.id] == call) _calls.remove(call.alert.id);
    notifyListeners();
  }

  /// Espera a que el teléfono cuelgue (máx. [_maxCall]) mientras
  /// [keepWaiting] siga siendo cierto.
  Future<void> _waitWhileInCall([bool Function()? keepWaiting]) async {
    for (var s = 0; s < _maxCall.inSeconds; s++) {
      if (keepWaiting != null && !keepWaiting()) return;
      if (!await _phone.isInCall()) return;
      await Future<void>.delayed(const Duration(seconds: 1));
    }
  }

  /// Android no avisa a las apps cuándo contestan: espera el timbre y repite
  /// el mensaje mientras siga la llamada. Si cuelgan a media frase, calla.
  Future<void> _speakDuringCall(String script) async {
    await Future<void>.delayed(_ringTime);
    final hangUpWatcher = Timer.periodic(const Duration(seconds: 1), (_) async {
      if (!await _phone.isInCall()) unawaited(_voice.stop());
    });
    try {
      for (var i = 0; i < _maxRepeats && !_voiceStopped; i++) {
        if (!await _phone.isInCall()) break;
        await _voice.speak(i == 0 ? script : 'Repito. $script');
        await Future<void>.delayed(const Duration(seconds: 1));
      }
    } finally {
      hangUpWatcher.cancel();
    }
  }

  /// "Llamar ahora" en la cuenta regresiva, o "Reintentar" tras un fallo.
  Future<void> callNow(String alertId) async {
    final call = _calls[alertId];
    if (call == null ||
        call.state == AutoCallState.queued ||
        call.state == AutoCallState.calling) {
      return;
    }
    if (call.state == AutoCallState.failed) {
      await _phone.requestPermission();
      // Pudo cerrarse, reintentarse o atenderse con el diálogo abierto.
      if (_calls[alertId] != call || call.state != AutoCallState.failed) {
        return;
      }
    }
    _startDialing(call);
    _syncTicker();
    notifyListeners();
  }

  /// "No llamar" (falsa alarma), también en la cola, o cerrar una fallida.
  void cancel(String alertId) {
    final call = _calls[alertId];
    if (call == null || call.state == AutoCallState.calling) return;
    _calls.remove(alertId);
    _stopVoiceIfIdle();
    _syncTicker();
    notifyListeners();
  }

  /// Calla la voz de la llamada en curso (la llamada sigue).
  Future<void> stopVoice() async {
    _voiceStopped = true;
    await _voice.stop();
  }

  void dismissNotice() {
    _notice = null;
    notifyListeners();
  }

  /// Calla el aviso de la cuenta regresiva si ya nadie lo necesita: sin otra
  /// cuenta regresiva (su aviso) ni una llamada en curso (su mensaje).
  void _stopVoiceIfIdle() {
    final busy = _calls.values.any((c) =>
        c.state == AutoCallState.countdown ||
        c.state == AutoCallState.calling);
    if (!busy) unawaited(_voice.stop());
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _incomingSub.cancel();
    _alerts.removeListener(_onAlertsChanged);
    super.dispose();
  }
}
