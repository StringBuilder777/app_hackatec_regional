import 'package:flutter/foundation.dart';

import '../core/services/notification_service.dart';
import '../core/services/storage_service.dart';
import '../models/care_profile.dart';

/// Maneja los perfiles de configuración de cuidados y sincroniza los
/// recordatorios de medicación con el sistema de notificaciones.
class ProfilesProvider extends ChangeNotifier {
  static const _key = 'care_profiles';

  final StorageService _storage;
  final NotificationService _notifications;

  final List<CareProfile> _profiles = [];

  ProfilesProvider(this._storage, this._notifications) {
    _load();
    // Reagenda al arrancar: robustez ante reinicios del teléfono y ante
    // permisos de alarma exacta concedidos después.
    _rescheduleAll();
  }

  Future<void> _rescheduleAll() async {
    for (final p in _profiles) {
      await _scheduleMeds(p);
    }
  }

  List<CareProfile> get profiles => List.unmodifiable(_profiles);
  bool get isEmpty => _profiles.isEmpty;

  void _load() {
    final stored = _storage.readList(_key);
    _profiles.addAll(stored.map(CareProfile.fromJson));
  }

  CareProfile? byId(String id) {
    for (final p in _profiles) {
      if (p.id == id) return p;
    }
    return null;
  }

  Future<void> upsert(CareProfile profile) async {
    final i = _profiles.indexWhere((p) => p.id == profile.id);
    if (i == -1) {
      _profiles.add(profile);
    } else {
      // Cancela los recordatorios previos antes de reprogramar.
      await _cancelMeds(_profiles[i]);
      _profiles[i] = profile;
    }
    notifyListeners();
    await _persist();
    await _scheduleMeds(profile);
  }

  Future<void> remove(String id) async {
    final i = _profiles.indexWhere((p) => p.id == id);
    if (i == -1) return;
    await _cancelMeds(_profiles[i]);
    _profiles.removeAt(i);
    notifyListeners();
    await _persist();
  }

  Future<void> _scheduleMeds(CareProfile p) async {
    if (!p.enabled) return;
    for (final med in p.medications) {
      await _notifications.scheduleMedication(med, profileName: p.name);
    }
  }

  Future<void> _cancelMeds(CareProfile p) async {
    for (final med in p.medications) {
      await _notifications.cancelMedication(med.id);
    }
  }

  Future<void> _persist() =>
      _storage.writeList(_key, _profiles.map((p) => p.toJson()).toList());
}
