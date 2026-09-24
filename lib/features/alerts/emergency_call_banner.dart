import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/alert.dart';
import '../../providers/emergency_call_provider.dart';

/// Para `MaterialApp.builder`: el aviso de llamada automática flota encima de
/// cualquier pantalla (pestañas, formularios, login).
Widget withEmergencyCallBanner(BuildContext context, Widget? child) =>
    Stack(children: [child!, const EmergencyCallBanner()]);

/// Aviso de la llamada automática: cuenta regresiva ("No llamar" / "Llamar
/// ahora"), en espera, en curso y fallida. Flota arriba de cualquier pantalla
/// para que "No llamar" esté a la mano donde esté el cuidador. Va fuera del
/// Navigator (ver [withEmergencyCallBanner]): por eso no usa Tooltip.
class EmergencyCallBanner extends StatelessWidget {
  const EmergencyCallBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<EmergencyCallProvider>();
    final calls = provider.calls;
    final notice = provider.notice;
    if (calls.isEmpty && notice == null) return const SizedBox.shrink();
    return Positioned(
      top: 0,
      left: 8,
      right: 8,
      child: SafeArea(
        bottom: false,
        child: ConstrainedBox(
          // Con varias llamadas no tapa toda la pantalla: se desplaza.
          constraints:
              BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height / 2),
          child: SingleChildScrollView(
            child: Column(children: [
              for (final c in calls) _CallCard(call: c),
              if (notice != null)
                _NoticeCard(text: notice, onClose: provider.dismissNotice),
            ]),
          ),
        ),
      ),
    );
  }
}

class _CallCard extends StatelessWidget {
  final AutoCall call;
  const _CallCard({required this.call});

  @override
  Widget build(BuildContext context) {
    final provider = context.read<EmergencyCallProvider>();
    final theme = Theme.of(context);
    final color = call.alert.severity.color;
    final id = call.alert.id;
    final who = call.target.label;
    final noCall = TextButton(
        onPressed: () => provider.cancel(id), child: const Text('No llamar'));
    final (title, subtitle, actions) = switch (call.state) {
      AutoCallState.countdown => (
          'Llamaré a $who en ${call.secondsLeft} s',
          call.alert.severity == AlertSeverity.critical
              ? 'Alerta grave: ${call.alert.title}'
              : 'Nadie ha atendido: ${call.alert.title}',
          <Widget>[
            noCall,
            FilledButton.icon(
                onPressed: () => provider.callNow(id),
                icon: const Icon(Icons.call),
                label: const Text('Llamar ahora')),
          ],
        ),
      AutoCallState.queued => (
          'En espera: llamaré a $who',
          'Al terminar la llamada en curso. ${call.alert.title}',
          <Widget>[noCall],
        ),
      AutoCallState.calling when call.voiceDone => (
          'En llamada con $who',
          'La voz terminó; esperando a que cuelguen.',
          <Widget>[],
        ),
      AutoCallState.calling => (
          'Llamando a $who…',
          'Una voz explica la situación en altavoz.',
          <Widget>[
            TextButton.icon(
                onPressed: provider.stopVoice,
                icon: const Icon(Icons.voice_over_off),
                label: const Text('Detener voz')),
          ],
        ),
      AutoCallState.failed => (
          'No se pudo llamar a $who',
          'Revisa el permiso de llamadas de la app y reintenta.',
          <Widget>[
            TextButton(
                onPressed: () => provider.cancel(id),
                child: const Text('Cerrar')),
            FilledButton.icon(
                onPressed: () => provider.callNow(id),
                icon: const Icon(Icons.refresh),
                label: const Text('Reintentar')),
          ],
        ),
    };
    return Card(
      elevation: 6,
      margin: const EdgeInsets.symmetric(vertical: 4),
      // Opaco: flota sobre el contenido de la pantalla.
      color: Color.alphaBlend(
          color.withValues(alpha: 0.08), theme.colorScheme.surface),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: color, width: 1.5),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(Icons.phone_in_talk, color: color),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: theme.textTheme.titleSmall
                            ?.copyWith(fontWeight: FontWeight.bold)),
                    Text(subtitle, style: theme.textTheme.bodySmall),
                  ],
                ),
              ),
            ]),
            if (call.state == AutoCallState.countdown) ...[
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: LinearProgressIndicator(
                  value: call.secondsLeft / call.totalSeconds,
                  color: color,
                  backgroundColor: color.withValues(alpha: 0.15),
                ),
              ),
            ],
            OverflowBar(
              alignment: MainAxisAlignment.end,
              spacing: 8,
              children: actions,
            ),
          ],
        ),
      ),
    );
  }
}

class _NoticeCard extends StatelessWidget {
  final String text;
  final VoidCallback onClose;
  const _NoticeCard({required this.text, required this.onClose});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 6,
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
        child: Row(children: [
          const Icon(Icons.phone_disabled_outlined),
          const SizedBox(width: 12),
          Expanded(
            child: Text(text, style: Theme.of(context).textTheme.bodyMedium),
          ),
          TextButton(onPressed: onClose, child: const Text('Cerrar')),
        ]),
      ),
    );
  }
}
