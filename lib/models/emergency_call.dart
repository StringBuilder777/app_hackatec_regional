import 'alert.dart';
import 'care_profile.dart';

/// A quién llama la app: al responsable o, si el usuario de la app es el
/// responsable, a su contacto de emergencia.
enum CallTargetKind { responsible, emergencyContact }

extension CallTargetKindX on CallTargetKind {
  String get label => switch (this) {
        CallTargetKind.responsible => 'responsable',
        CallTargetKind.emergencyContact => 'contacto de emergencia',
      };
}

/// Persona a la que se marcará por una alerta.
class CallTarget {
  final CallTargetKind kind;
  final CareContact contact;

  const CallTarget(this.kind, this.contact);

  /// Nombre para la voz y la interfaz; si no se capturó, el rol.
  String get name =>
      contact.name.trim().isEmpty ? kind.label : contact.name.trim();

  /// "Ana (responsable)": para el aviso y el historial de la alerta.
  String get label => '$name (${kind.label})';
}

/// A quién llamar por las alertas de [profile]; `null` si falta el teléfono.
CallTarget? callTargetFor(CareProfile profile) {
  final target = profile.userIsResponsible
      ? CallTarget(CallTargetKind.emergencyContact, profile.emergencyContact)
      : CallTarget(CallTargetKind.responsible, profile.responsible);
  return target.contact.hasPhone ? target : null;
}

/// Cuánto esperar antes de marcar: las graves casi de inmediato (margen para
/// cancelar una falsa alarma); las advertencias, si nadie las atiende. Las
/// informativas nunca llaman.
Duration? autoCallDelay(AlertSeverity severity) => switch (severity) {
      AlertSeverity.critical => const Duration(seconds: 15),
      AlertSeverity.warning => const Duration(seconds: 60),
      AlertSeverity.info => null,
    };

/// "Caída" o "se cayó" como palabra completa: no "recaída". (`\b` de Dart no
/// entiende acentos, por eso los lookarounds.)
final _fallWords = RegExp(
    r'(?<![a-záéíóúüñ])(caída|caida|cayó|cayo)(?![a-záéíóúüñ])');

/// Si la alerta es una caída (y no un "riesgo de caída").
bool isFall(Alert alert) {
  final text = '${alert.title} ${alert.body}'.toLowerCase();
  return _fallWords.hasMatch(text) && !text.contains('riesgo');
}

/// Qué le pasó a la persona, dicho en voz: "se cayó" o el título de la alerta.
String situationOf(Alert alert) {
  if (isFall(alert)) return 'se cayó';
  return alert.severity == AlertSeverity.critical
      ? 'tiene una emergencia: ${alert.title}'
      : 'tiene una alerta sin atender: ${alert.title}';
}

/// Lo que dice la voz dentro de la llamada. Al responsable le cuenta qué pasó
/// y le pide ir; al contacto de emergencia le da los datos para auxiliar:
/// quién es, qué pasó y la dirección. Solo una alerta grave pide llamar a
/// emergencias ("9 1 1" separado para que la voz lo diga dígito por dígito).
String callScript(Alert alert, CareProfile profile, CallTarget target) {
  final name = profile.name.trim();
  final grave = alert.severity == AlertSeverity.critical;
  switch (target.kind) {
    case CallTargetKind.responsible:
      final what =
          isFall(alert) ? 'tuvo un accidente: se cayó' : situationOf(alert);
      return 'Hola, ${target.name}. Te llamo de Sense Care. $name $what. '
          '${grave ? '¿Puedes llegar para ayudarle? Si no puedes, llama a '
              'emergencias al 9 1 1.' : 'Por favor, comunícate o ve a revisar.'}';
    case CallTargetKind.emergencyContact:
      final address = profile.address.trim();
      return 'Esta es una llamada automática de Sense Care. '
          '$name ${situationOf(alert)}. Es una persona adulta mayor y '
          '${grave ? 'necesita ayuda' : 'nadie ha respondido'}. '
          '${address.isEmpty ? '' : 'La dirección es: $address. '}'
          '${grave ? 'Por favor, acude o llama a emergencias al 9 1 1.' : 'Por favor, comunícate o acude a revisar.'}';
  }
}

/// Aviso en voz en este teléfono al empezar la cuenta regresiva de una
/// alerta grave, por si nadie está mirando la pantalla.
String countdownAnnouncement(
        Alert alert, CareProfile profile, CallTarget target, int seconds) =>
    'Alerta grave. ${profile.name.trim()} ${situationOf(alert)}. '
    'Llamaré a ${target.name} en $seconds segundos. '
    'Toca No llamar para cancelar.';
