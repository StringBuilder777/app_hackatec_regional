import 'package:flutter/foundation.dart';

import '../core/services/notification_service.dart';
import '../core/services/storage_service.dart';
import '../models/alert.dart';

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

  final List<Alert> _alerts = [];
  AlertFilter _filter = AlertFilter.all;

  AlertsProvider(this._storage, this._notifications) {
    _load();
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

  /// Punto único de entrada de una alerta (simulada o desde AWS SNS -> FCM):
  /// la guarda y dispara la notificación rica.
  Future<void> receiveIncoming(Alert alert) async {
    _alerts.add(alert);
    notifyListeners();
    await _persist();
    await _notifications.showAlert(alert);
  }

  Future<void> markViewed(String id) => _updateStatus(id, AlertStatus.viewed);
  Future<void> cancel(String id) => _updateStatus(id, AlertStatus.canceled);

  Future<void> _updateStatus(String id, AlertStatus status) async {
    final i = _alerts.indexWhere((a) => a.id == id);
    if (i == -1) return;
    _alerts[i] = _alerts[i].copyWith(status: status);
    notifyListeners();
    await _persist();
  }

  Future<void> _persist() =>
      _storage.writeList(_key, _alerts.map((a) => a.toJson()).toList());

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
