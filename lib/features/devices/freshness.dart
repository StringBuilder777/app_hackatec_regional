import '../../providers/devices_provider.dart';

/// `true` si [lastSeenAt] existe y cayó dentro de la ventana [staleAfter]
/// (requisito de producto: nunca presentar un dato viejo como "en vivo").
bool isFresh(DateTime? lastSeenAt) {
  if (lastSeenAt == null) return false;
  return DateTime.now().toUtc().difference(lastSeenAt.toUtc()) <= staleAfter;
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
