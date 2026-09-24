import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/telemetry_reading.dart';
import '../../providers/devices_provider.dart';
import 'freshness.dart';

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
    final device = context.watch<DevicesProvider>().byId(widget.deviceId);
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
      ),
      _SensorTileData(
        icon: Icons.water_drop_outlined,
        label: 'Humedad',
        value: _fmt(reading.humidityPct, '%'),
      ),
      _SensorTileData(
        icon: Icons.air,
        label: 'CO₂',
        value: _fmt(reading.co2Ppm, ' ppm', decimals: 0),
      ),
      _SensorTileData(
        icon: Icons.straighten,
        label: 'Proximidad',
        value: _fmt(reading.proximityCm, ' cm', decimals: 0),
      ),
      _SensorTileData(
        icon: Icons.volume_up_outlined,
        label: 'Ruido (prom.)',
        value: _fmt(reading.dbAvg, ' dB'),
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
      childAspectRatio: 1.5,
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
  const _SensorTileData(
      {required this.icon, required this.label, required this.value});
}

class _SensorTile extends StatelessWidget {
  final _SensorTileData data;
  const _SensorTile({required this.data});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(data.icon, color: theme.colorScheme.primary),
            const SizedBox(height: 8),
            Text(data.value,
                style: theme.textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.bold)),
            Text(data.label,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.outline)),
          ],
        ),
      ),
    );
  }
}
