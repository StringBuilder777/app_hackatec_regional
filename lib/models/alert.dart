import 'package:flutter/material.dart';

/// Gravedad de una alerta. Determina canal, color, sonido y si dispara
/// flash + pantalla completa.
enum AlertSeverity { info, warning, critical }

/// Estado de una alerta dentro de la app.
enum AlertStatus { active, viewed, canceled }

extension AlertSeverityX on AlertSeverity {
  String get label => switch (this) {
        AlertSeverity.info => 'Información',
        AlertSeverity.warning => 'Advertencia',
        AlertSeverity.critical => 'Crítica',
      };

  Color get color => switch (this) {
        AlertSeverity.info => const Color(0xFF2E7D9A),
        AlertSeverity.warning => const Color(0xFFE08600),
        AlertSeverity.critical => const Color(0xFFD32F2F),
      };

  IconData get icon => switch (this) {
        AlertSeverity.info => Icons.info_outline,
        AlertSeverity.warning => Icons.warning_amber_rounded,
        AlertSeverity.critical => Icons.emergency_outlined,
      };
}

extension AlertStatusX on AlertStatus {
  String get label => switch (this) {
        AlertStatus.active => 'Activa',
        AlertStatus.viewed => 'Vista',
        AlertStatus.canceled => 'Cancelada',
      };
}

/// Una alerta recibida. Hoy se genera localmente (simulada); mañana llegará
/// vía AWS SNS -> FCM con el mismo formato de `data`.
class Alert {
  final String id;
  final String title;
  final String body;
  final String? imageUrl;
  final AlertSeverity severity;
  final DateTime timestamp;
  final AlertStatus status;

  /// Datos extra del payload (mensaje data-only de SNS/FCM) o del caso tal
  /// como lo devolvió el backend (`CaseSummary.toJson`, ver
  /// `AlertsProvider.syncFromBackend`). Cuando trae `caseId`, esta alerta
  /// representa un caso real del backend y `cancel`/`escalate` lo usan para
  /// llamar `SenseCareApiService`; si no, es una alerta puramente local
  /// (`seed-*`/`sim-*` de demo).
  final Map<String, dynamic> data;

  const Alert({
    required this.id,
    required this.title,
    required this.body,
    required this.timestamp,
    this.imageUrl,
    this.severity = AlertSeverity.info,
    this.status = AlertStatus.active,
    this.data = const {},
  });

  bool get hasImage => imageUrl != null && imageUrl!.isNotEmpty;

  Alert copyWith({AlertStatus? status, Map<String, dynamic>? data}) => Alert(
        id: id,
        title: title,
        body: body,
        imageUrl: imageUrl,
        severity: severity,
        timestamp: timestamp,
        status: status ?? this.status,
        data: data ?? this.data,
      );

  factory Alert.fromJson(Map<String, dynamic> json) => Alert(
        id: json['id'] as String,
        title: json['title'] as String? ?? '',
        body: json['body'] as String? ?? '',
        imageUrl: json['imageUrl'] as String?,
        severity:
            AlertSeverity.values.asNameMap()[json['severity'] as String?] ??
                AlertSeverity.info,
        status: AlertStatus.values.asNameMap()[json['status'] as String?] ??
            AlertStatus.active,
        timestamp: DateTime.tryParse(json['timestamp'] as String? ?? '') ??
            DateTime.now(),
        data: (json['data'] as Map?)?.cast<String, dynamic>() ?? const {},
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'body': body,
        'imageUrl': imageUrl,
        'severity': severity.name,
        'status': status.name,
        'timestamp': timestamp.toIso8601String(),
        'data': data,
      };

  /// Normaliza el payload `data` que enviaría AWS SNS -> FCM (todo strings).
  factory Alert.fromPushData(Map<String, dynamic> data) => Alert(
        id: (data['id'] as String?) ??
            DateTime.now().millisecondsSinceEpoch.toString(),
        title: (data['title'] as String?) ?? 'Alerta',
        body: (data['body'] as String?) ?? '',
        imageUrl: data['imageUrl'] as String?,
        severity: AlertSeverity.values.asNameMap()[data['severity']] ??
            AlertSeverity.warning,
        timestamp: DateTime.now(),
        data: data,
      );
}
