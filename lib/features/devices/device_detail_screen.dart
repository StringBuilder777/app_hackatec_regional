import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/telemetry_reading.dart';
import '../../providers/devices_provider.dart';
import 'freshness.dart';
import 'sensor_status.dart';

/// Detalle de un dispositivo emparejado: lecturas de sensores en vivo. Hace
/// polling de `GET /devices/{deviceId}/latest` cada pocos segundos mientras
/// esta pantalla está visible, y se detiene al salir de ella.
class DeviceDetailScreen extends StatefulWidget {
  final String deviceId;
  const DeviceDetailScreen({super.key, required this.deviceId});

  @override
  State<DeviceDetailScreen> createState() => _DeviceDetailScreenState();
}

class _DeviceDetailScreenState extends State<DeviceDetailScreen> {
  @override
  void initState() {
    super.initState();
    // Se dispara tras el primer frame para no llamar notifyListeners()
    // durante el build inicial de este widget.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<DevicesProvider>().startPolling(widget.deviceId);
    });
  }

  @override
  void dispose() {
    // No usar context.read aquí: el widget ya está desmontándose, así que se
    // guarda la referencia al provider en build/didChangeDependencies.
    _devicesProvider?.stopPolling();
    super.dispose();
  }

  DevicesProvider? _devicesProvider;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _devicesProvider = context.read<DevicesProvider>();
  }

  @override
  Widget build(BuildContext context) {
    final devicesProvider = context.watch<DevicesProvider>();
    final device = devicesProvider.byId(widget.deviceId);
    final pollError = devicesProvider.pollError;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(widget.deviceId)),
      body: device == null
          ? const Center(child: Text('Este dispositivo ya no está emparejado.'))
          : RefreshIndicator(
              onRefresh: () =>
                  context.read<DevicesProvider>().refreshLatest(widget.deviceId),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                children: [
                  _FreshnessBanner(lastSeenAt: device.lastSeenAt),
                  if (pollError != null) ...[
                    const SizedBox(height: 8),
                    _PollErrorBanner(message: pollError),
                  ],
                  const SizedBox(height: 16),
                  if (device.latestTelemetry == null)
                    _NoReadingsYet(theme: theme)
                  else
                    _SensorGrid(reading: device.latestTelemetry!),
                ],
              ),
            ),
    );
  }
}

/// Motivo por el que el último intento de refrescar (cada 4s mientras esta
/// pantalla está abierta) no trajo datos nuevos. Antes este error se
/// tragaba en silencio (`DevicesProvider.refreshLatest`); sin esto, un 403
/// por pairing revocado o una sesión expirada se veía igual que "todavía no
/// llegó la siguiente lectura", indistinguible para quien mira la pantalla.
class _PollErrorBanner extends StatelessWidget {
  final String message;
  const _PollErrorBanner({required this.message});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.warning_amber_rounded, color: theme.colorScheme.error, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(message,
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error)),
          ),
        ],
      ),
    );
  }
}

class _FreshnessBanner extends StatelessWidget {
  final DateTime? lastSeenAt;
  const _FreshnessBanner({required this.lastSeenAt});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fresh = isFresh(lastSeenAt);
    final color = fresh ? theme.colorScheme.primary : theme.colorScheme.error;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Icon(fresh ? Icons.sensors : Icons.error_outline, color: color),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  fresh ? 'En vivo' : 'Datos desactualizados',
                  style: theme.textTheme.titleSmall
                      ?.copyWith(color: color, fontWeight: FontWeight.bold),
                ),
                Text(lastSeenLabel(lastSeenAt),
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.outline)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _NoReadingsYet extends StatelessWidget {
  final ThemeData theme;
  const _NoReadingsYet({required this.theme});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40),
      child: Column(
        children: [
          Icon(Icons.hourglass_empty, size: 48, color: theme.colorScheme.outline),
          const SizedBox(height: 12),
          const Text('Este dispositivo todavía no ha reportado datos.'),
        ],
      ),
    );
  }
}

class _SensorGrid extends StatelessWidget {
  final TelemetryReading reading;
  const _SensorGrid({required this.reading});

  @override
  Widget build(BuildContext context) {
    final tiles = <_SensorTileData>[
      _SensorTileData(
        icon: Icons.thermostat_outlined,
        label: 'Temperatura',
        value: _fmt(reading.temperatureC, '°C'),
        status: classifyTemperatura(reading.temperatureC),
      ),
      _SensorTileData(
        icon: Icons.water_drop_outlined,
        label: 'Humedad',
        value: _fmt(reading.humidityPct, '%'),
        status: classifyHumedad(reading.humidityPct),
      ),
      _SensorTileData(
        icon: Icons.air,
        label: 'CO₂',
        value: _fmt(reading.co2Ppm, ' ppm', decimals: 0),
        status: classifyCo2(reading.co2Ppm),
      ),
      _SensorTileData(
        icon: Icons.straighten,
        label: 'Proximidad',
        value: _fmt(reading.proximityCm, ' cm', decimals: 0),
        status: classifyProximidad(reading.proximityCm),
      ),
      _SensorTileData(
        icon: Icons.volume_up_outlined,
        label: 'Ruido (prom.)',
        value: _fmt(reading.dbAvg, ' dB'),
        status: classifyAudio(reading.dbAvg),
      ),
      _SensorTileData(
        icon: Icons.graphic_eq_outlined,
        label: 'Ruido (pico)',
        value: _fmt(reading.dbPeak, ' dB'),
      ),
    ];

    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 1.15,
      children: [for (final t in tiles) _SensorTile(data: t)],
    );
  }

  static String _fmt(double? value, String unit, {int decimals = 1}) {
    if (value == null) return '—';
    return '${value.toStringAsFixed(decimals)}$unit';
  }
}

class _SensorTileData {
  final IconData icon;
  final String label;
  final String value;
  final SensorStatus? status;
  const _SensorTileData(
      {required this.icon, required this.label, required this.value, this.status});
}

class _SensorTile extends StatelessWidget {
  final _SensorTileData data;
  const _SensorTile({required this.data});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = data.status;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Icon(data.icon, color: theme.colorScheme.primary),
                if (status != null)
                  Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: sensorStatusColor(status),
                      shape: BoxShape.circle,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(data.value,
                style: theme.textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.bold)),
            Text(data.label,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.outline)),
            if (status != null) ...[
              const SizedBox(height: 4),
              Text('Estado: ${sensorStatusLabel(status)}',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: sensorStatusColor(status),
                    fontWeight: FontWeight.bold,
                  )),
            ],
          ],
        ),
      ),
    );
  }
}
