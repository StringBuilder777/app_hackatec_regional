import 'package:flutter/material.dart';

/// Estado de un sensor frente a su rango esperado. Mismas 3 bandas que usa
/// el frontend web (`realDeviceMapping.ts`) para no divergir en el criterio
/// de "cuándo alertar" entre plataformas.
enum SensorStatus { normal, anormal, critico }

class _Band {
  final double baseline;
  final double anormalWidth;
  final double criticoWidth;
  const _Band(this.baseline, this.anormalWidth, this.criticoWidth);
}

/// Umbrales fijos alineados con `edge/config/example.yaml`
/// (`thresholdC: 38`, `thresholdPpm: 1200`), igual que en el frontend web.
/// `proximidad` usa cm (a diferencia del frontend web, que convierte a mm)
/// porque `TelemetryReading.proximityCm` ya viene en cm.
const _temperatura = _Band(24, 6, 14);
const _humedad = _Band(50, 20, 35);
const _co2 = _Band(600, 400, 600);
const _proximidad = _Band(100, 70, 95);
const _audio = _Band(50, 25, 50);

SensorStatus _classify(_Band band, double value) {
  final deviation = (value - band.baseline).abs();
  if (deviation >= band.criticoWidth) return SensorStatus.critico;
  if (deviation >= band.anormalWidth) return SensorStatus.anormal;
  return SensorStatus.normal;
}

SensorStatus? classifyTemperatura(double? v) => v == null ? null : _classify(_temperatura, v);
SensorStatus? classifyHumedad(double? v) => v == null ? null : _classify(_humedad, v);
SensorStatus? classifyCo2(double? v) => v == null ? null : _classify(_co2, v);
SensorStatus? classifyProximidad(double? v) => v == null ? null : _classify(_proximidad, v);
SensorStatus? classifyAudio(double? v) => v == null ? null : _classify(_audio, v);

Color sensorStatusColor(SensorStatus status) {
  switch (status) {
    case SensorStatus.normal:
      return const Color(0xFF3B9E5F);
    case SensorStatus.anormal:
      return const Color(0xFFE0A62B);
    case SensorStatus.critico:
      return const Color(0xFFD64545);
  }
}

String sensorStatusLabel(SensorStatus status) {
  switch (status) {
    case SensorStatus.normal:
      return 'Normal';
    case SensorStatus.anormal:
      return 'Anormal';
    case SensorStatus.critico:
      return 'Crítico';
  }
}
