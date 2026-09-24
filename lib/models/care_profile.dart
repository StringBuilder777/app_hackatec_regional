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

/// Persona a la que la app puede llamar en una emergencia.
class CareContact {
  final String name;
  final String phone;

  const CareContact({this.name = '', this.phone = ''});

  bool get hasPhone => phone.trim().isNotEmpty;

  factory CareContact.fromJson(Map<String, dynamic> j) => CareContact(
        name: j['name'] as String? ?? '',
        phone: j['phone'] as String? ?? '',
      );

  Map<String, dynamic> toJson() => {'name': name, 'phone': phone};
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

  /// Dirección de la persona; se dicta en la llamada de emergencia.
  final String address;

  /// A quién llama la app si una alerta es grave o nadie la atiende: al
  /// responsable o, si el usuario de la app es el responsable, a su contacto
  /// de emergencia.
  final CareContact responsible;
  final bool userIsResponsible;
  final CareContact emergencyContact;

  const CareProfile({
    required this.id,
    required this.name,
    this.medications = const [],
    this.sleepWindow,
    this.homeWindow,
    this.careNeeds = const [],
    this.enabled = true,
    this.address = '',
    this.responsible = const CareContact(),
    this.userIsResponsible = false,
    this.emergencyContact = const CareContact(),
  });

  CareProfile copyWith({
    String? name,
    List<MedicationReminder>? medications,
    TimeWindow? sleepWindow,
    TimeWindow? homeWindow,
    List<String>? careNeeds,
    bool? enabled,
    String? address,
    CareContact? responsible,
    bool? userIsResponsible,
    CareContact? emergencyContact,
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
        address: address ?? this.address,
        responsible: responsible ?? this.responsible,
        userIsResponsible: userIsResponsible ?? this.userIsResponsible,
        emergencyContact: emergencyContact ?? this.emergencyContact,
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
        address: j['address'] as String? ?? '',
        responsible: j['responsible'] == null
            ? const CareContact()
            : CareContact.fromJson(
                (j['responsible'] as Map).cast<String, dynamic>()),
        userIsResponsible: j['userIsResponsible'] as bool? ?? false,
        emergencyContact: j['emergencyContact'] == null
            ? const CareContact()
            : CareContact.fromJson(
                (j['emergencyContact'] as Map).cast<String, dynamic>()),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'medications': medications.map((e) => e.toJson()).toList(),
        'sleepWindow': sleepWindow?.toJson(),
        'homeWindow': homeWindow?.toJson(),
        'careNeeds': careNeeds,
        'enabled': enabled,
        'address': address,
        'responsible': responsible.toJson(),
        'userIsResponsible': userIsResponsible,
        'emergencyContact': emergencyContact.toJson(),
      };
}
