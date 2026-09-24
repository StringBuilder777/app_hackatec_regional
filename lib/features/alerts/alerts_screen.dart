import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../models/alert.dart';
import '../../models/case_summary.dart';
import '../../providers/alerts_provider.dart';
import '../../providers/auth_provider.dart';

/// Pantalla de Alertas: la última arriba y, encima, filtros (todas / activas /
/// vistas / canceladas). Incluye "simular alerta" para probar la notificación.
class AlertsScreen extends StatefulWidget {
  const AlertsScreen({super.key});

  @override
  State<AlertsScreen> createState() => _AlertsScreenState();
}

class _AlertsScreenState extends State<AlertsScreen> {
  @override
  void initState() {
    super.initState();
    // Se dispara tras el primer frame para no llamar notifyListeners()
    // durante el build inicial de este widget (mismo patrón que
    // `DeviceDetailScreen.startPolling`). Sin sesión con IdToken real (login
    // mock, o sesión expirada) simplemente no sincroniza: la lista local
    // sigue mostrándose igual que hoy.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final idToken = context.read<AuthProvider>().idToken;
      if (idToken != null) {
        context.read<AlertsProvider>().syncFromBackend(idToken);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AlertsProvider>();
    final alerts = provider.visibleAlerts;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Alertas'),
        actions: [
          IconButton(
            tooltip: 'Simular alerta',
            icon: const Icon(Icons.notification_add_outlined),
            onPressed: () => _simulateAlert(context),
          ),
        ],
      ),
      body: Column(
        children: [
          _FilterBar(current: provider.filter, onChanged: provider.setFilter),
          Expanded(
            child: alerts.isEmpty
                ? const _EmptyAlerts()
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 4, 12, 96),
                    itemCount: alerts.length,
                    itemBuilder: (_, i) => _AlertCard(
                      alert: alerts[i],
                      highlighted:
                          i == 0 && provider.filter == AlertFilter.all,
                    ),
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _simulateAlert(context),
        icon: const Icon(Icons.notifications_active),
        label: const Text('Simular alerta'),
      ),
    );
  }
}

/// Simula la caída de la persona cuidada (la alerta de la demo): pasa por el
/// mismo flujo que usará AWS SNS -> FCM y dispara la llamada automática.
Future<void> _simulateAlert(BuildContext context) async {
  final now = DateTime.now();
  final alert = Alert(
    id: 'sim-${now.millisecondsSinceEpoch}',
    title: 'Caída detectada',
    body: 'Posible caída en la habitación principal. Verifica de inmediato.',
    severity: AlertSeverity.critical,
    imageUrl:
        'https://picsum.photos/seed/${now.millisecondsSinceEpoch}/600/320',
    timestamp: now,
  );
  await context.read<AlertsProvider>().receiveIncoming(alert);
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Alerta de caída enviada')),
    );
  }
}

class _FilterBar extends StatelessWidget {
  final AlertFilter current;
  final ValueChanged<AlertFilter> onChanged;
  const _FilterBar({required this.current, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          for (final f in AlertFilter.values)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(f.label),
                selected: current == f,
                onSelected: (_) => onChanged(f),
              ),
            ),
        ],
      ),
    );
  }
}

class _AlertCard extends StatelessWidget {
  final Alert alert;
  final bool highlighted;
  const _AlertCard({required this.alert, this.highlighted = false});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = alert.severity.color;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side:
            highlighted ? BorderSide(color: color, width: 2) : BorderSide.none,
      ),
      child: InkWell(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => AlertDetailScreen(alert: alert)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (highlighted)
              Container(
                width: double.infinity,
                color: color,
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                child: Text('ÚLTIMA ALERTA',
                    style: theme.textTheme.labelSmall?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1)),
              ),
            ListTile(
              leading: CircleAvatar(
                backgroundColor: color.withValues(alpha: 0.15),
                child: Icon(alert.severity.icon, color: color),
              ),
              title: Text(alert.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(alert.body,
                      maxLines: 2, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 6),
                  Row(children: [
                    _StatusChip(status: alert.status),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(_relativeTime(alert.timestamp),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: theme.colorScheme.outline)),
                    ),
                    if (alert.calledTo != null) ...[
                      const SizedBox(width: 8),
                      Icon(Icons.phone_forwarded,
                          size: 14, color: theme.colorScheme.outline),
                    ],
                  ]),
                ],
              ),
              trailing: alert.hasImage
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.network(alert.imageUrl!,
                          width: 52,
                          height: 52,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) =>
                              const SizedBox(width: 52, height: 52)),
                    )
                  : null,
              isThreeLine: true,
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final AlertStatus status;
  const _StatusChip({required this.status});

  @override
  Widget build(BuildContext context) {
    final (color, icon) = switch (status) {
      AlertStatus.active => (const Color(0xFFD32F2F), Icons.circle),
      AlertStatus.viewed => (const Color(0xFF546E7A), Icons.visibility),
      AlertStatus.canceled => (const Color(0xFF9E9E9E), Icons.cancel),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 12, color: color),
        const SizedBox(width: 4),
        Text(status.label,
            style: TextStyle(
                fontSize: 11, color: color, fontWeight: FontWeight.w600)),
      ]),
    );
  }
}

class _EmptyAlerts extends StatelessWidget {
  const _EmptyAlerts();
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.notifications_off_outlined,
            size: 64, color: Theme.of(context).colorScheme.outline),
        const SizedBox(height: 12),
        const Text('No hay alertas en este filtro'),
      ]),
    );
  }
}

/// Detalle de una alerta con imagen y acciones (marcar vista / escalar /
/// cancelar).
class AlertDetailScreen extends StatefulWidget {
  final Alert alert;
  const AlertDetailScreen({super.key, required this.alert});

  @override
  State<AlertDetailScreen> createState() => _AlertDetailScreenState();
}

class _AlertDetailScreenState extends State<AlertDetailScreen> {
  late Alert _alert = widget.alert;

  /// Línea de tiempo del caso (`GET /cases/{id}/events`): se pide al abrir
  /// el detalle y tras decidir, no en cada ciclo de polling.
  Future<List<CaseEvent>>? _events;

  @override
  void initState() {
    super.initState();
    _loadEvents();
  }

  void _loadEvents() {
    final caseId = _alert.data['caseId'] as String?;
    if (caseId == null || caseId.isEmpty) return;
    _events = context.read<AlertsProvider>().caseEvents(caseId);
  }

  /// Núcleo de "Cancelar"/"Escalar": llama a `AlertsProvider.cancel`/
  /// `escalate`, que ya decide internamente si la alerta es local (demo) o
  /// un caso real del backend. El resultado tiene tres formas posibles:
  ///
  /// - `null` + `decisionError == null`: alerta local, se aplicó de
  ///   inmediato (sólo posible para "cancelar"; "escalar" en una alerta
  ///   local no hace nada, ver `AlertsProvider._decide`).
  /// - `null` + `decisionError != null`: falló la llamada al backend
  ///   (sesión expirada, sin red, 403/404...) -- se muestra el mensaje y NO
  ///   se navega, para que el usuario pueda reintentar.
  /// - No nulo: el backend respondió. Si `conflict` es `true`, la decisión
  ///   de este usuario NO se aplicó porque el caso ya estaba resuelto por
  ///   otra vía (otro intento, el `VOICE_CHECKIN` de la Pi, otro cuidador);
  ///   se muestra el `alertStatus` REAL en vez de fingir que se aplicó lo
  ///   pedido.
  Future<void> _handleDecision(BuildContext context,
      {required bool escalate}) async {
    final provider = context.read<AlertsProvider>();
    final result = escalate
        ? await provider.escalate(_alert.id)
        : await provider.cancel(_alert.id);
    if (!context.mounted) return;

    if (result == null) {
      final err = provider.decisionError;
      if (err != null) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(err)));
        return;
      }
      if (!escalate) {
        setState(() => _alert = _alert.copyWith(status: AlertStatus.canceled));
        Navigator.of(context).pop();
      }
      return;
    }

    final status = result.alertStatus == 'CANCELLED'
        ? AlertStatus.canceled
        : AlertStatus.active;
    setState(() {
      _alert = _alert.copyWith(status: status);
      _loadEvents();
    });

    if (result.conflict) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
            'No se aplicó: el caso ya quedó en estado "${result.alertStatus}".'),
      ));
    } else if (escalate) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Alerta escalada.')));
    } else {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = _alert.severity.color;
    // La llamada automática puede registrarse con el detalle abierto.
    final called = context.watch<AlertsProvider>().byId(_alert.id);
    return Scaffold(
      appBar: AppBar(title: Text(_alert.title)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_alert.hasImage)
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Image.network(
                _alert.imageUrl!,
                height: 200,
                width: double.infinity,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => Container(
                  height: 200,
                  color: theme.colorScheme.surfaceContainerHighest,
                  child: const Icon(Icons.broken_image, size: 48),
                ),
                loadingBuilder: (c, child, p) => p == null
                    ? child
                    : Container(
                        height: 200,
                        alignment: Alignment.center,
                        child: const CircularProgressIndicator()),
              ),
            ),
          const SizedBox(height: 16),
          Row(children: [
            Icon(_alert.severity.icon, color: color),
            const SizedBox(width: 8),
            Text(_alert.severity.label,
                style: theme.textTheme.titleMedium
                    ?.copyWith(color: color, fontWeight: FontWeight.bold)),
            const Spacer(),
            _StatusChip(status: _alert.status),
          ]),
          const SizedBox(height: 12),
          Text(_alert.body, style: theme.textTheme.bodyLarge),
          const SizedBox(height: 8),
          Text(
              DateFormat("EEEE d 'de' MMMM, HH:mm", 'es')
                  .format(_alert.timestamp),
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.outline)),
          if (called?.calledTo != null) ...[
            const SizedBox(height: 12),
            Row(children: [
              Icon(Icons.phone_forwarded,
                  size: 18, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text('Llamada automática a ${called!.calledTo}'
                    '${called.calledAt == null ? '' : ' · ${DateFormat('HH:mm').format(called.calledAt!)}'}'),
              ),
            ]),
          ],
          if (_events != null) ...[
            const SizedBox(height: 16),
            Text('Línea de tiempo del caso',
                style: theme.textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.bold)),
            FutureBuilder<List<CaseEvent>>(
              future: _events,
              builder: (context, snap) {
                if (snap.connectionState != ConnectionState.done) {
                  return const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: LinearProgressIndicator());
                }
                final events = snap.data ?? const <CaseEvent>[];
                if (events.isEmpty) {
                  return const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: Text('Sin eventos todavía.'));
                }
                return Column(children: [
                  for (final e in events)
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.circle, size: 10),
                      title: Text(_humanizeEvent(e.eventType)),
                      trailing: e.timestamp == null
                          ? null
                          : Text(DateFormat('HH:mm:ss')
                              .format(e.timestamp!.toLocal())),
                    ),
                ]);
              },
            ),
          ],
          const SizedBox(height: 24),
          if (_alert.status == AlertStatus.active) ...[
            FilledButton.icon(
              onPressed: () {
                context.read<AlertsProvider>().markViewed(_alert.id);
                setState(() =>
                    _alert = _alert.copyWith(status: AlertStatus.viewed));
              },
              icon: const Icon(Icons.visibility),
              label: const Text('Marcar como vista'),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () => _handleDecision(context, escalate: true),
              icon: const Icon(Icons.priority_high),
              label: const Text('Escalar'),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () => _handleDecision(context, escalate: false),
              icon: const Icon(Icons.cancel_outlined),
              label: const Text('Cancelar alerta'),
            ),
          ] else
            OutlinedButton.icon(
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.arrow_back),
              label: const Text('Volver'),
            ),
        ],
      ),
    );
  }
}

String _relativeTime(DateTime t) {
  final diff = DateTime.now().difference(t);
  if (diff.inMinutes < 1) return 'Ahora';
  if (diff.inMinutes < 60) return 'Hace ${diff.inMinutes} min';
  if (diff.inHours < 24) return 'Hace ${diff.inHours} h';
  return DateFormat('d MMM, HH:mm', 'es').format(t);
}

/// "NOTIFICATION_PUBLISHED" -> "Notification published".
String _humanizeEvent(String code) {
  if (code.isEmpty) return 'Evento';
  final text = code.toLowerCase().replaceAll('_', ' ');
  return text[0].toUpperCase() + text.substring(1);
}
