import 'telemetry_reading.dart';

/// Un dispositivo que este usuario ya emparejó (existe una fila en
/// `CaregiverAccess` en el backend para su `sub`). Solo `deviceId` y
/// `pairedAt` se persisten localmente; `lastSeenAt`/`latestTelemetry` son
/// estado en memoria que refresca el polling mientras se ve el detalle.
class PairedDevice {
  final String deviceId;
  final DateTime pairedAt;
  final DateTime? lastSeenAt;
  final TelemetryReading? latestTelemetry;

  const PairedDevice({
    required this.deviceId,
    required this.pairedAt,
    this.lastSeenAt,
    this.latestTelemetry,
  });

  /// A diferencia de un `copyWith` típico, aquí [lastSeenAt] y
  /// [latestTelemetry] SIEMPRE se sobrescriben con lo que se pase (incluido
  /// `null`, que el backend usa para decir "este dispositivo nunca ha
  /// reportado"). Usar `??` aquí sería incorrecto: perdería esa señal.
  PairedDevice copyWith({
    DateTime? lastSeenAt,
    TelemetryReading? latestTelemetry,
  }) =>
      PairedDevice(
        deviceId: deviceId,
        pairedAt: pairedAt,
        lastSeenAt: lastSeenAt,
        latestTelemetry: latestTelemetry,
      );

  factory PairedDevice.fromJson(Map<String, dynamic> j) => PairedDevice(
        deviceId: j['deviceId'] as String,
        pairedAt: DateTime.tryParse(j['pairedAt'] as String? ?? '') ??
            DateTime.now(),
      );

  /// Solo persiste la identidad del emparejamiento; las lecturas en vivo se
  /// vuelven a pedir al backend cada vez que se abre el detalle.
  Map<String, dynamic> toJson() => {
        'deviceId': deviceId,
        'pairedAt': pairedAt.toIso8601String(),
      };
}
