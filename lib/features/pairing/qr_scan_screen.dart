import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';

import '../../providers/devices_provider.dart';

/// El QR de emparejamiento codifica un JSON plano
/// `{"deviceId": "...", "pairingCode": "..."}` (ver
/// `docs/DEMO_INGEST_AUTH.md` sección 5.0 del backend). Sin esquema de URL
/// propio: si el texto no es ese JSON, no es un QR de emparejamiento válido.
class QrPairingPayload {
  final String deviceId;
  final String pairingCode;
  const QrPairingPayload({required this.deviceId, required this.pairingCode});

  static QrPairingPayload? tryParse(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final deviceId = decoded['deviceId'];
      final pairingCode = decoded['pairingCode'];
      if (deviceId is! String || pairingCode is! String) return null;
      if (deviceId.trim().isEmpty || pairingCode.trim().isEmpty) return null;
      return QrPairingPayload(
        deviceId: deviceId.trim(),
        pairingCode: pairingCode.trim(),
      );
    } catch (_) {
      return null;
    }
  }
}

/// Escanea el QR de emparejamiento con la cámara. Si la cámara falla o el QR
/// no se puede leer, ofrece un formulario manual de respaldo con los mismos
/// dos campos (deviceId + pairingCode) que codifica el QR.
class QrScanScreen extends StatefulWidget {
  const QrScanScreen({super.key});

  @override
  State<QrScanScreen> createState() => _QrScanScreenState();
}

class _QrScanScreenState extends State<QrScanScreen> {
  final MobileScannerController _controller = MobileScannerController();
  bool _manualMode = false;
  bool _processing = false;

  final _formKey = GlobalKey<FormState>();
  final _deviceIdController = TextEditingController();
  final _pairingCodeController = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    _deviceIdController.dispose();
    _pairingCodeController.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_processing) return;
    final barcodes = capture.barcodes;
    if (barcodes.isEmpty) return;
    final raw = barcodes.first.rawValue;
    if (raw == null) return;

    final payload = QrPairingPayload.tryParse(raw);
    if (payload == null) {
      _showSnack(
          'El QR escaneado no tiene el formato esperado. Intenta de nuevo o usa el ingreso manual.');
      return;
    }
    _pair(payload.deviceId, payload.pairingCode);
  }

  Future<void> _pair(String deviceId, String pairingCode) async {
    setState(() => _processing = true);
    final devices = context.read<DevicesProvider>();
    final ok = await devices.pairDevice(deviceId, pairingCode);
    if (!mounted) return;
    setState(() => _processing = false);
    if (ok) {
      Navigator.of(context).pop(true);
      _showSnack('Dispositivo "$deviceId" emparejado correctamente.');
    } else {
      _showSnack(devices.pairError ?? 'No se pudo emparejar el dispositivo.');
    }
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _submitManual() async {
    if (!_formKey.currentState!.validate()) return;
    await _pair(
        _deviceIdController.text.trim(), _pairingCodeController.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Emparejar dispositivo'),
        actions: [
          IconButton(
            tooltip: _manualMode ? 'Usar cámara' : 'Ingresar código a mano',
            icon: Icon(
                _manualMode ? Icons.qr_code_scanner : Icons.keyboard_outlined),
            onPressed: () => setState(() => _manualMode = !_manualMode),
          ),
        ],
      ),
      body: _manualMode ? _buildManualForm(context) : _buildScanner(context),
    );
  }

  Widget _buildScanner(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        MobileScanner(controller: _controller, onDetect: _onDetect),
        _buildScannerOverlay(context),
        if (_processing)
          const ColoredBox(
            color: Colors.black54,
            child: Center(child: CircularProgressIndicator()),
          ),
      ],
    );
  }

  Widget _buildScannerOverlay(BuildContext context) {
    return SafeArea(
      child: Column(
        children: [
          const Spacer(),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 32),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.black54,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Text(
              'Apunta la cámara al código QR junto al dispositivo (o en la '
              'pantalla del simulador).',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white),
            ),
          ),
          const SizedBox(height: 24),
          TextButton.icon(
            onPressed: () => setState(() => _manualMode = true),
            icon: const Icon(Icons.keyboard_outlined, color: Colors.white),
            label: const Text(
              '¿No puedes escanear? Ingresa el código a mano',
              style: TextStyle(color: Colors.white),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildManualForm(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(Icons.qr_code,
                      size: 64, color: theme.colorScheme.primary),
                  const SizedBox(height: 16),
                  Text('Emparejar manualmente',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.titleLarge
                          ?.copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text(
                    'Úsalo si la cámara falla o no puedes escanear el QR. El '
                    'código no distingue mayúsculas ni espacios.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: theme.colorScheme.outline),
                  ),
                  const SizedBox(height: 24),
                  TextFormField(
                    controller: _deviceIdController,
                    decoration: const InputDecoration(
                      labelText: 'ID del dispositivo',
                      hintText: 'p. ej. pi-demo-01',
                      prefixIcon: Icon(Icons.devices_other_outlined),
                    ),
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'Requerido' : null,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _pairingCodeController,
                    textCapitalization: TextCapitalization.characters,
                    decoration: const InputDecoration(
                      labelText: 'Código de emparejamiento',
                      hintText: 'p. ej. AB12CD',
                      prefixIcon: Icon(Icons.pin_outlined),
                    ),
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'Requerido' : null,
                    onFieldSubmitted: (_) => _submitManual(),
                  ),
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: _processing ? null : _submitManual,
                    child: _processing
                        ? const SizedBox(
                            height: 22,
                            width: 22,
                            child:
                                CircularProgressIndicator(strokeWidth: 2))
                        : const Text('Emparejar'),
                  ),
                  const SizedBox(height: 12),
                  TextButton.icon(
                    onPressed: () => setState(() => _manualMode = false),
                    icon: const Icon(Icons.qr_code_scanner),
                    label: const Text('Volver a la cámara'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
