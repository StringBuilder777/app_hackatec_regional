/// Un caso (alerta) tal como lo regresa el backend en `GET /cases` (cada
/// elemento de `items`). Un caso nace de una anomalia real detectada por un
/// dispositivo (sensor o camara); `alertStatus` es el campo que manda para
/// decidir si sigue activo (`PENDING`/`SENT`/`ESCALATED`) o ya se resolvio
/// (`CANCELLED`) -- puede venir resuelto por esta misma app, por el
/// `VOICE_CHECKIN` de la Pi, o por otro cuidador, asi que nunca se asume
/// nada localmente sin volver a preguntarle al backend (ver
/// `AlertsProvider.syncFromBackend`).
class CaseSummary {
  final String caseId;
  final String deviceId;
  final String eventType;
  final String anomalyType;
  final String? severity;
  final String? status;
  final String? alertStatus;
  final String? evidenceStatus;
  final String? analysisStatus;
  final DateTime createdAt;
  final DateTime? updatedAt;

  const CaseSummary({
    required this.caseId,
    required this.deviceId,
    required this.eventType,
    required this.anomalyType,
    required this.createdAt,
    this.severity,
    this.status,
    this.alertStatus,
    this.evidenceStatus,
    this.analysisStatus,
    this.updatedAt,
  });

  factory CaseSummary.fromJson(Map<String, dynamic> j) => CaseSummary(
        caseId: j['caseId'] as String? ?? '',
        deviceId: j['deviceId'] as String? ?? '',
        eventType: j['eventType'] as String? ?? '',
        anomalyType: j['anomalyType'] as String? ?? '',
        severity: j['severity'] as String?,
        status: j['status'] as String?,
        alertStatus: j['alertStatus'] as String?,
        evidenceStatus: j['evidenceStatus'] as String?,
        analysisStatus: j['analysisStatus'] as String?,
        createdAt:
            DateTime.tryParse(j['createdAt'] as String? ?? '') ?? DateTime.now(),
        updatedAt: j['updatedAt'] == null
            ? null
            : DateTime.tryParse(j['updatedAt'] as String),
      );

  /// Se usa para guardar el caso completo en `Alert.data`, asi
  /// `AlertsProvider.cancel`/`escalate` pueden recuperar el `caseId` real
  /// (y el resto de metadatos) sin tener que volver a pedirlo al backend.
  Map<String, dynamic> toJson() => {
        'caseId': caseId,
        'deviceId': deviceId,
        'eventType': eventType,
        'anomalyType': anomalyType,
        'severity': severity,
        'status': status,
        'alertStatus': alertStatus,
        'evidenceStatus': evidenceStatus,
        'analysisStatus': analysisStatus,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt?.toIso8601String(),
      };
}

/// Una fila de la bitacora de `GET /cases/{caseId}/events`. El backend la
/// documenta como "opaca" (solo garantiza `eventType` + una marca de
/// tiempo, sin fijar el nombre exacto de ese campo ni el resto del
/// contenido), asi que en vez de modelar cada variante posible se guarda
/// todo el row crudo en [raw] -- el mismo patron que `Alert.data` para el
/// payload de push, que tampoco se modela campo por campo.
class CaseEvent {
  final String eventType;
  final DateTime? timestamp;
  final Map<String, dynamic> raw;

  const CaseEvent({
    required this.eventType,
    required this.raw,
    this.timestamp,
  });

  factory CaseEvent.fromJson(Map<String, dynamic> j) {
    // El nombre exacto del campo de tiempo no esta fijado por el contrato;
    // se prueban los alias mas probables en vez de asumir uno solo.
    final ts = j['timestamp'] ?? j['occurredAt'] ?? j['createdAt'] ?? j['ts'];
    return CaseEvent(
      eventType: j['eventType'] as String? ?? '',
      timestamp: ts is String ? DateTime.tryParse(ts) : null,
      raw: j,
    );
  }
}
