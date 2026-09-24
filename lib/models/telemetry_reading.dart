/// Una lectura de sensores de un dispositivo, tal como la regresa el backend
/// en `GET /devices/{deviceId}/latest` (campo `latestTelemetry`) y en
/// `GET /devices/{deviceId}/telemetry` (cada elemento de `items`).
class TelemetryReading {
  final String deviceId;
  final DateTime occurredAt;
  final double? temperatureC;
  final double? humidityPct;
  final double? co2Ppm;
  final double? proximityCm;
  final double? dbAvg;
  final double? dbPeak;
  final DateTime? receivedAt;

  const TelemetryReading({
    required this.deviceId,
    required this.occurredAt,
    this.temperatureC,
    this.humidityPct,
    this.co2Ppm,
    this.proximityCm,
    this.dbAvg,
    this.dbPeak,
    this.receivedAt,
  });

  factory TelemetryReading.fromJson(Map<String, dynamic> j) => TelemetryReading(
        deviceId: j['deviceId'] as String? ?? '',
        occurredAt:
            DateTime.tryParse(j['occurredAt'] as String? ?? '')?.toUtc() ??
                DateTime.now().toUtc(),
        temperatureC: (j['temperatureC'] as num?)?.toDouble(),
        humidityPct: (j['humidityPct'] as num?)?.toDouble(),
        co2Ppm: (j['co2Ppm'] as num?)?.toDouble(),
        proximityCm: (j['proximityCm'] as num?)?.toDouble(),
        dbAvg: (j['dbAvg'] as num?)?.toDouble(),
        dbPeak: (j['dbPeak'] as num?)?.toDouble(),
        receivedAt: j['receivedAt'] == null
            ? null
            : DateTime.tryParse(j['receivedAt'] as String)?.toUtc(),
      );

  Map<String, dynamic> toJson() => {
        'deviceId': deviceId,
        'occurredAt': occurredAt.toIso8601String(),
        'temperatureC': temperatureC,
        'humidityPct': humidityPct,
        'co2Ppm': co2Ppm,
        'proximityCm': proximityCm,
        'dbAvg': dbAvg,
        'dbPeak': dbPeak,
        'receivedAt': receivedAt?.toIso8601String(),
      };
}

/// Respuesta completa de `GET /devices/{deviceId}/latest`. `lastSeenAt` y
/// `latestTelemetry` vienen `null` (no es error) si el dispositivo nunca ha
/// reportado.
class DeviceLatestResult {
  final String deviceId;
  final DateTime? lastSeenAt;
  final TelemetryReading? latestTelemetry;

  const DeviceLatestResult({
    required this.deviceId,
    this.lastSeenAt,
    this.latestTelemetry,
  });

  factory DeviceLatestResult.fromJson(Map<String, dynamic> j) => DeviceLatestResult(
        deviceId: j['deviceId'] as String? ?? '',
        lastSeenAt: j['lastSeenAt'] == null
            ? null
            : DateTime.tryParse(j['lastSeenAt'] as String)?.toUtc(),
        latestTelemetry: j['latestTelemetry'] == null
            ? null
            : TelemetryReading.fromJson(
                (j['latestTelemetry'] as Map).cast<String, dynamic>()),
      );
}
