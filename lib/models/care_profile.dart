import 'package:flutter/material.dart';

/// Recordatorio de medicación: una pastilla a una hora del día.
class MedicationReminder {
  final String id;
  final String name;
  final int hour;
  final int minute;

  const MedicationReminder({
    required this.id,
    required this.name,
    required this.hour,
    required this.minute,
  });

  TimeOfDay get time => TimeOfDay(hour: hour, minute: minute);

  MedicationReminder copyWith({String? name, int? hour, int? minute}) =>
      MedicationReminder(
        id: id,
        name: name ?? this.name,
        hour: hour ?? this.hour,
        minute: minute ?? this.minute,
      );

  factory MedicationReminder.fromJson(Map<String, dynamic> j) =>
      MedicationReminder(
        id: j['id'] as String,
        name: j['name'] as String? ?? 'Medicamento',
        hour: (j['hour'] as num?)?.toInt() ?? 8,
        minute: (j['minute'] as num?)?.toInt() ?? 0,
      );

  Map<String, dynamic> toJson() =>
      {'id': id, 'name': name, 'hour': hour, 'minute': minute};
}

/// Ventana horaria "de X a Y". Usada para "duerme de..." y "en casa de...".
class TimeWindow {
  final int startHour;
  final int startMinute;
  final int endHour;
  final int endMinute;

  const TimeWindow({
    required this.startHour,
    required this.startMinute,
    required this.endHour,
    required this.endMinute,
  });

  TimeOfDay get start => TimeOfDay(hour: startHour, minute: startMinute);
  TimeOfDay get end => TimeOfDay(hour: endHour, minute: endMinute);

  factory TimeWindow.fromJson(Map<String, dynamic> j) => TimeWindow(
        startHour: (j['startHour'] as num?)?.toInt() ?? 22,
        startMinute: (j['startMinute'] as num?)?.toInt() ?? 0,
        endHour: (j['endHour'] as num?)?.toInt() ?? 7,
        endMinute: (j['endMinute'] as num?)?.toInt() ?? 0,
      );

  Map<String, dynamic> toJson() => {
        'startHour': startHour,
        'startMinute': startMinute,
        'endHour': endHour,
        'endMinute': endMinute,
      };
}

/// Perfil de configuración de cuidados de un usuario. Reúne sus requerimientos:
/// medicación (pastillas a cierta hora), sueño, presencia en casa y cuidados.
class CareProfile {
  final String id;
  final String name;
  final List<MedicationReminder> medications;
  final TimeWindow? sleepWindow;
  final TimeWindow? homeWindow;
  final List<String> careNeeds;
  final bool enabled;

  const CareProfile({
    required this.id,
    required this.name,
    this.medications = const [],
    this.sleepWindow,
    this.homeWindow,
    this.careNeeds = const [],
    this.enabled = true,
  });

  CareProfile copyWith({
    String? name,
    List<MedicationReminder>? medications,
    TimeWindow? sleepWindow,
    TimeWindow? homeWindow,
    List<String>? careNeeds,
    bool? enabled,
    bool clearSleep = false,
    bool clearHome = false,
  }) =>
      CareProfile(
        id: id,
        name: name ?? this.name,
        medications: medications ?? this.medications,
        sleepWindow: clearSleep ? null : (sleepWindow ?? this.sleepWindow),
        homeWindow: clearHome ? null : (homeWindow ?? this.homeWindow),
        careNeeds: careNeeds ?? this.careNeeds,
        enabled: enabled ?? this.enabled,
      );

  factory CareProfile.fromJson(Map<String, dynamic> j) => CareProfile(
        id: j['id'] as String,
        name: j['name'] as String? ?? 'Perfil',
        medications: (j['medications'] as List?)
                ?.map((e) => MedicationReminder.fromJson(
                    (e as Map).cast<String, dynamic>()))
                .toList() ??
            const [],
        sleepWindow: j['sleepWindow'] == null
            ? null
            : TimeWindow.fromJson(
                (j['sleepWindow'] as Map).cast<String, dynamic>()),
        homeWindow: j['homeWindow'] == null
            ? null
            : TimeWindow.fromJson(
                (j['homeWindow'] as Map).cast<String, dynamic>()),
        careNeeds:
            (j['careNeeds'] as List?)?.map((e) => e.toString()).toList() ??
                const [],
        enabled: j['enabled'] as bool? ?? true,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'medications': medications.map((e) => e.toJson()).toList(),
        'sleepWindow': sleepWindow?.toJson(),
        'homeWindow': homeWindow?.toJson(),
        'careNeeds': careNeeds,
        'enabled': enabled,
      };
}
