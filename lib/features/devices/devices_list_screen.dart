import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/paired_device.dart';
import '../../providers/devices_provider.dart';
import '../pairing/qr_scan_screen.dart';
import 'device_detail_screen.dart';
import 'freshness.dart';

/// Lista de dispositivos que este usuario ya emparejó. Punto de entrada para
/// emparejar uno nuevo (FAB -> escáner QR) y para ver el detalle en vivo de
/// cada uno.
class DevicesListScreen extends StatelessWidget {
  const DevicesListScreen({super.key});

  Future<void> _openScanner(BuildContext context) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const QrScanScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final devices = context.watch<DevicesProvider>().devices;
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Dispositivos')),
      body: devices.isEmpty
          ? _EmptyDevices(onScan: () => _openScanner(context))
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
              children: [
                Text(
                  'Dispositivos emparejados con tu cuenta. Toca uno para ver '
                  'sus sensores en vivo.',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.outline),
                ),
                const SizedBox(height: 12),
                for (final d in devices) _DeviceCard(device: d),
              ],
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openScanner(context),
        icon: const Icon(Icons.qr_code_scanner),
        label: const Text('Emparejar dispositivo'),
      ),
    );
  }
}

class _EmptyDevices extends StatelessWidget {
  final VoidCallback onScan;
  const _EmptyDevices({required this.onScan});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.sensors_outlined,
                size: 64, color: theme.colorScheme.outline),
            const SizedBox(height: 16),
            Text('Aún no has emparejado ningún dispositivo',
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              'Escanea el QR junto al dispositivo (o en la pantalla del '
              'simulador) para empezar a ver sus lecturas.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.outline),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: onScan,
              icon: const Icon(Icons.qr_code_scanner),
              label: const Text('Emparejar dispositivo'),
            ),
          ],
        ),
      ),
    );
  }
}

class _DeviceCard extends StatelessWidget {
  final PairedDevice device;
  const _DeviceCard({required this.device});

  Future<void> _confirmRemove(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Quitar dispositivo'),
        content: Text(
            '¿Dejar de ver "${device.deviceId}"? Podrás volver a emparejarlo '
            'escaneando su QR de nuevo.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Quitar')),
        ],
      ),
    );
    if (ok == true && context.mounted) {
      context.read<DevicesProvider>().removeDevice(device.deviceId);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fresh = isFresh(device.lastSeenAt);
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => DeviceDetailScreen(deviceId: device.deviceId),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: fresh
                    ? theme.colorScheme.primaryContainer
                    : theme.colorScheme.surfaceContainerHighest,
                child: Icon(Icons.sensors,
                    color: fresh
                        ? theme.colorScheme.onPrimaryContainer
                        : theme.colorScheme.outline),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(device.deviceId,
                        style: theme.textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 2),
                    Text(
                      lastSeenLabel(device.lastSeenAt),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: fresh
                            ? theme.colorScheme.primary
                            : theme.colorScheme.outline,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close),
                tooltip: 'Quitar dispositivo',
                onPressed: () => _confirmRemove(context),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
