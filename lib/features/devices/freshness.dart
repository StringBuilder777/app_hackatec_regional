import '../../providers/devices_provider.dart';

/// `true` si [lastSeenAt] existe y cayó dentro de la ventana [staleAfter]
/// (requisito de producto: nunca presentar un dato viejo como "en vivo").
/// [now] permite probar el límite exacto; por defecto es la hora actual.
bool isFresh(DateTime? lastSeenAt, {DateTime? now}) {
  if (lastSeenAt == null) return false;
  final reference = (now ?? DateTime.now()).toUtc();
  return reference.difference(lastSeenAt.toUtc()) <= staleAfter;
}

/// Texto legible de "hace cuánto" se vio por última vez el dispositivo.
String lastSeenLabel(DateTime? lastSeenAt) {
  if (lastSeenAt == null) return 'Sin lecturas todavía';
  final diff = DateTime.now().toUtc().difference(lastSeenAt.toUtc());
  if (diff.isNegative || diff.inSeconds < 5) return 'Actualizado justo ahora';
  if (diff.inSeconds < 60) return 'Actualizado hace ${diff.inSeconds} s';
  if (diff.inMinutes < 60) return 'Actualizado hace ${diff.inMinutes} min';
  if (diff.inHours < 24) return 'Actualizado hace ${diff.inHours} h';
  return 'Actualizado hace ${diff.inDays} d';
}
