import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/services/sensecare_api_service.dart';
import '../core/services/storage_service.dart';
import '../models/paired_device.dart';

/// Cuánto tiempo sin una lectura nueva se considera "obsoleta" (ya no en
/// vivo). Requisito de producto: nunca mostrar un dato viejo como si fuera
/// en tiempo real.
const staleAfter = Duration(seconds: 15);

const _pollInterval = Duration(seconds: 4);

/// Dispositivos emparejados por este usuario: lista persistida localmente,
/// emparejamiento por QR/código manual, y polling de la última lectura
/// mientras se ve el detalle de un dispositivo.
class DevicesProvider extends ChangeNotifier {
  static const _key = 'paired_devices';

  final SenseCareApiService _api;
  final StorageService _storage;
  String? Function() _tokenProvider;

  final List<PairedDevice> _devices = [];
  Timer? _pollTimer;
  String? _polledDeviceId;

  bool _pairing = false;
  String? _pairError;

  /// Motivo por el que el último `refreshLatest` del polling no trajo datos
  /// nuevos (sesión expirada, pairing revocado, sin red, 5xx…). Antes se
  /// tragaba en silencio; ahora se expone para que la pantalla de detalle
  /// pueda distinguir "todavía no llegó la siguiente lectura" de "algo
  /// impide refrescar" -- que se veían idénticos y parecían un dispositivo
  /// que dejó de actualizarse.
  String? _pollError;

  DevicesProvider(this._api, this._storage, String? Function() tokenProvider)
      : _tokenProvider = tokenProvider {
    _load();
  }

  /// Permite refrescar de dónde se lee el IdToken vigente (p. ej. cuando
  /// [AuthProvider] cambia tras un login/logout). Ver el
  /// `ChangeNotifierProxyProvider` en `main.dart`.
  void updateTokenProvider(String? Function() tokenProvider) {
    _tokenProvider = tokenProvider;
  }

  List<PairedDevice> get devices => List.unmodifiable(_devices);
  bool get pairing => _pairing;
  String? get pairError => _pairError;
  String? get pollError => _pollError;

  void _load() {
    final stored = _storage.readList(_key);
    _devices.addAll(stored.map(PairedDevice.fromJson));
  }

  Future<void> _persist() =>
      _storage.writeList(_key, _devices.map((d) => d.toJson()).toList());

  PairedDevice? byId(String deviceId) {
    final i = _devices.indexWhere((d) => d.deviceId == deviceId);
    return i == -1 ? null : _devices[i];
  }

  bool isPaired(String deviceId) => _devices.any((d) => d.deviceId == deviceId);

  /// Empareja un dispositivo nuevo (o reconfirma uno existente) con su
  /// `pairingCode` (del QR o escrito a mano). Devuelve `true` en éxito; en
  /// error deja el mensaje en [pairError].
  Future<bool> pairDevice(String deviceId, String pairingCode) async {
    final id = deviceId.trim();
    final code = pairingCode.trim();
    if (id.isEmpty || code.isEmpty) {
      _pairError = 'Faltan datos: deviceId y código son obligatorios.';
      notifyListeners();
      return false;
    }

    final token = _tokenProvider();
    if (token == null || token.isEmpty) {
      _pairError = 'Tu sesión expiró. Vuelve a iniciar sesión.';
      notifyListeners();
      return false;
    }

    _pairing = true;
    _pairError = null;
    notifyListeners();
    try {
      await _api.pairDevice(deviceId: id, pairingCode: code, idToken: token);
      if (!isPaired(id)) {
        _devices.add(PairedDevice(deviceId: id, pairedAt: DateTime.now()));
        await _persist();
      }
      _pairing = false;
      notifyListeners();
      return true;
    } on ApiException catch (e) {
      _pairError = e.message;
      _pairing = false;
      notifyListeners();
      return false;
    } catch (_) {
      _pairError = 'No se pudo emparejar el dispositivo. Intenta de nuevo.';
      _pairing = false;
      notifyListeners();
      return false;
    }
  }

  void clearPairError() {
    _pairError = null;
    notifyListeners();
  }

  Future<void> removeDevice(String deviceId) async {
    _devices.removeWhere((d) => d.deviceId == deviceId);
    if (_polledDeviceId == deviceId) stopPolling();
    await _persist();
    notifyListeners();
  }

  /// Pide `GET /devices/{deviceId}/latest` una sola vez. Nunca lanza (el
  /// timer de polling reintenta solo); en error deja el mensaje en
  /// [pollError] en vez de tragárselo en silencio, para no confundir
  /// "todavía no llegó la siguiente lectura" con "algo impide refrescar"
  /// (sesión expirada, pairing revocado, sin red).
  Future<void> refreshLatest(String deviceId) async {
    final token = _tokenProvider();
    if (token == null || token.isEmpty) {
      _pollError = 'Tu sesión expiró. Vuelve a iniciar sesión.';
      notifyListeners();
      return;
    }
    try {
      final result =
          await _api.getDeviceLatest(deviceId: deviceId, idToken: token);
      final i = _devices.indexWhere((d) => d.deviceId == deviceId);
      if (i == -1) return;
      _devices[i] = _devices[i].copyWith(
        lastSeenAt: result.lastSeenAt,
        latestTelemetry: result.latestTelemetry,
      );
      _pollError = null;
      notifyListeners();
    } on ForbiddenException {
      _pollError = 'Perdiste el acceso a este dispositivo. Vuelve a emparejarlo.';
      notifyListeners();
    } on ApiException catch (e) {
      _pollError = e.message;
      notifyListeners();
    } catch (_) {
      _pollError = 'No se pudo actualizar. Reintentando…';
      notifyListeners();
    }
  }

  /// Inicia el polling de un dispositivo (p. ej. al entrar a su pantalla de
  /// detalle). Llamar [stopPolling] al salir de la pantalla para no gastar
  /// batería/datos en segundo plano.
  void startPolling(String deviceId) {
    if (_polledDeviceId == deviceId && _pollTimer != null) return;
    stopPolling();
    _polledDeviceId = deviceId;
    _pollError = null;
    unawaited(refreshLatest(deviceId));
    _pollTimer = Timer.periodic(_pollInterval, (_) => refreshLatest(deviceId));
  }

  void stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
    _polledDeviceId = null;
  }

  @override
  void dispose() {
    stopPolling();
    super.dispose();
  }
}
