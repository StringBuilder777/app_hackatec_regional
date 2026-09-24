import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/care_profile.dart';
import '../../providers/auth_provider.dart';
import '../../providers/profiles_provider.dart';

/// Pantalla de Perfil: datos del usuario y sus perfiles de configuración de
/// cuidados (medicación, sueño, presencia en casa, cuidados).
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final profiles = context.watch<ProfilesProvider>().profiles;
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Perfil'),
        actions: [
          IconButton(
            tooltip: 'Cerrar sesión',
            icon: const Icon(Icons.logout),
            onPressed: () => context.read<AuthProvider>().logout(),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
        children: [
          Card(
            child: ListTile(
              leading: CircleAvatar(
                child: Text((auth.user?.email ?? '?')
                    .substring(0, 1)
                    .toUpperCase()),
              ),
              title: Text(auth.user?.email ?? 'Invitado'),
              subtitle: const Text('Cuidador'),
            ),
          ),
          const SizedBox(height: 16),
          Text('Perfiles de configuración',
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(
              'Configura los requerimientos de cada usuario: medicación, sueño, '
              'presencia en casa y cuidados necesarios.',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.outline)),
          const SizedBox(height: 12),
          if (profiles.isEmpty)
            const _EmptyProfiles()
          else
            for (final p in profiles) _ProfileCard(profile: p),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const ProfileFormScreen()),
        ),
        icon: const Icon(Icons.add),
        label: const Text('Nuevo perfil'),
      ),
    );
  }
}

String _fmtTod(TimeOfDay t) =>
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

class _EmptyProfiles extends StatelessWidget {
  const _EmptyProfiles();
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40),
      child: Column(children: [
        Icon(Icons.people_outline, size: 56, color: theme.colorScheme.outline),
        const SizedBox(height: 12),
        const Text('Aún no hay perfiles'),
        const SizedBox(height: 4),
        Text('Crea uno con el botón "Nuevo perfil".',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.outline)),
      ]),
    );
  }
}

class _ProfileCard extends StatelessWidget {
  final CareProfile profile;
  const _ProfileCard({required this.profile});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
              builder: (_) => ProfileFormScreen(profile: profile)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Icon(Icons.person_outline, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(
                    child: Text(profile.name,
                        style: theme.textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold))),
                if (!profile.enabled)
                  const Padding(
                    padding: EdgeInsets.only(right: 4),
                    child: Chip(
                        label: Text('Pausado'),
                        visualDensity: VisualDensity.compact),
                  ),
                IconButton(
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => _confirmDelete(context),
                ),
              ]),
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 8, children: [
                _tag(context, Icons.medication_outlined,
                    '${profile.medications.length} medicamentos'),
                if (profile.sleepWindow != null)
                  _tag(context, Icons.bedtime_outlined,
                      'Duerme ${_fmtTod(profile.sleepWindow!.start)}–${_fmtTod(profile.sleepWindow!.end)}'),
                if (profile.homeWindow != null)
                  _tag(context, Icons.home_outlined,
                      'En casa ${_fmtTod(profile.homeWindow!.start)}–${_fmtTod(profile.homeWindow!.end)}'),
                if (profile.careNeeds.isNotEmpty)
                  _tag(context, Icons.favorite_outline,
                      '${profile.careNeeds.length} cuidados'),
              ]),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Eliminar perfil'),
        content: Text(
            '¿Eliminar "${profile.name}"? Se cancelarán sus recordatorios.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Eliminar')),
        ],
      ),
    );
    if (ok == true && context.mounted) {
      context.read<ProfilesProvider>().remove(profile.id);
    }
  }
}

Widget _tag(BuildContext context, IconData icon, String label) {
  final theme = Theme.of(context);
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: theme.colorScheme.secondaryContainer,
      borderRadius: BorderRadius.circular(20),
    ),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 15, color: theme.colorScheme.onSecondaryContainer),
      const SizedBox(width: 6),
      Text(label,
          style: theme.textTheme.labelMedium
              ?.copyWith(color: theme.colorScheme.onSecondaryContainer)),
    ]),
  );
}

/// Formulario para crear / editar un perfil de configuración de cuidados.
class ProfileFormScreen extends StatefulWidget {
  final CareProfile? profile;
  const ProfileFormScreen({super.key, this.profile});

  @override
  State<ProfileFormScreen> createState() => _ProfileFormScreenState();
}

class _ProfileFormScreenState extends State<ProfileFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _careController = TextEditingController();
  late final TextEditingController _name;
  late List<MedicationReminder> _meds;
  late List<String> _careNeeds;
  TimeWindow? _sleep;
  TimeWindow? _home;
  bool _enabled = true;

  bool get _isEdit => widget.profile != null;

  @override
  void initState() {
    super.initState();
    final p = widget.profile;
    _name = TextEditingController(text: p?.name ?? '');
    _meds = [...?p?.medications];
    _careNeeds = [...?p?.careNeeds];
    _sleep = p?.sleepWindow;
    _home = p?.homeWindow;
    _enabled = p?.enabled ?? true;
  }

  @override
  void dispose() {
    _name.dispose();
    _careController.dispose();
    super.dispose();
  }

  Future<TimeOfDay?> _pickTime(TimeOfDay initial) =>
      showTimePicker(context: context, initialTime: initial);

  Future<void> _addMedication() async {
    final t = await _pickTime(const TimeOfDay(hour: 8, minute: 0));
    if (t == null) return;
    setState(() {
      _meds.add(MedicationReminder(
        id: 'med-${DateTime.now().microsecondsSinceEpoch}',
        name: '',
        hour: t.hour,
        minute: t.minute,
      ));
    });
  }

  void _addCareNeed() {
    final v = _careController.text.trim();
    if (v.isEmpty) return;
    setState(() {
      _careNeeds.add(v);
      _careController.clear();
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final id = widget.profile?.id ??
        'profile-${DateTime.now().millisecondsSinceEpoch}';
    final profile = CareProfile(
      id: id,
      name: _name.text.trim(),
      medications: _meds,
      sleepWindow: _sleep,
      homeWindow: _home,
      careNeeds: _careNeeds,
      enabled: _enabled,
    );
    await context.read<ProfilesProvider>().upsert(profile);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar:
          AppBar(title: Text(_isEdit ? 'Editar perfil' : 'Nuevo perfil')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
          children: [
            TextFormField(
              controller: _name,
              decoration: const InputDecoration(
                labelText: 'Nombre del perfil',
                hintText: 'p. ej. Abuela María',
                prefixIcon: Icon(Icons.badge_outlined),
              ),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Ponle un nombre' : null,
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Perfil activo'),
              subtitle:
                  const Text('Si se pausa, no se programan recordatorios'),
              value: _enabled,
              onChanged: (v) => setState(() => _enabled = v),
            ),
            const Divider(),
            _sectionTitle(theme, Icons.medication_outlined,
                'Medicación (pastillas a cierta hora)'),
            for (var i = 0; i < _meds.length; i++) _medRow(i),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _addMedication,
                icon: const Icon(Icons.add),
                label: const Text('Agregar medicamento'),
              ),
            ),
            const Divider(),
            _windowSection(
              label: 'Duerme de',
              icon: Icons.bedtime_outlined,
              window: _sleep,
              defaults: const TimeWindow(
                  startHour: 22, startMinute: 0, endHour: 7, endMinute: 0),
              onChanged: (w) => setState(() => _sleep = w),
            ),
            const Divider(),
            _windowSection(
              label: 'En casa de',
              icon: Icons.home_outlined,
              window: _home,
              defaults: const TimeWindow(
                  startHour: 9, startMinute: 0, endHour: 18, endMinute: 0),
              onChanged: (w) => setState(() => _home = w),
            ),
            const Divider(),
            _sectionTitle(
                theme, Icons.favorite_outline, 'Cuidados necesarios'),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (var i = 0; i < _careNeeds.length; i++)
                  InputChip(
                    label: Text(_careNeeds[i]),
                    onDeleted: () => setState(() => _careNeeds.removeAt(i)),
                  ),
              ],
            ),
            Row(children: [
              Expanded(
                child: TextField(
                  controller: _careController,
                  decoration: const InputDecoration(
                    labelText: 'Agregar cuidado',
                    hintText: 'p. ej. Silla de ruedas',
                    isDense: true,
                  ),
                  onSubmitted: (_) => _addCareNeed(),
                ),
              ),
              IconButton(
                  onPressed: _addCareNeed,
                  icon: const Icon(Icons.add_circle_outline)),
            ]),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _save,
              icon: const Icon(Icons.save_outlined),
              label: Text(_isEdit ? 'Guardar cambios' : 'Crear perfil'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionTitle(ThemeData theme, IconData icon, String label) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(children: [
        Icon(icon, size: 20, color: theme.colorScheme.primary),
        const SizedBox(width: 8),
        Expanded(
          child: Text(label,
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.bold)),
        ),
      ]),
    );
  }

  Widget _medRow(int i) {
    final med = _meds[i];
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(children: [
        Expanded(
          child: TextFormField(
            initialValue: med.name,
            decoration: const InputDecoration(
                labelText: 'Medicamento', isDense: true),
            onChanged: (v) => _meds[i] = med.copyWith(name: v),
            validator: (v) =>
                (v == null || v.trim().isEmpty) ? 'Requerido' : null,
          ),
        ),
        TextButton.icon(
          onPressed: () async {
            final t = await _pickTime(_meds[i].time);
            if (t != null) {
              setState(() => _meds[i] =
                  _meds[i].copyWith(hour: t.hour, minute: t.minute));
            }
          },
          icon: const Icon(Icons.schedule, size: 18),
          label: Text(_fmtTod(med.time)),
        ),
        IconButton(
          icon: const Icon(Icons.remove_circle_outline),
          onPressed: () => setState(() => _meds.removeAt(i)),
        ),
      ]),
    );
  }

  Widget _windowSection({
    required String label,
    required IconData icon,
    required TimeWindow? window,
    required TimeWindow defaults,
    required ValueChanged<TimeWindow?> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Row(children: [
            Icon(icon, size: 20),
            const SizedBox(width: 8),
            Text(label),
          ]),
          value: window != null,
          onChanged: (on) => onChanged(on ? defaults : null),
        ),
        if (window != null)
          Row(children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () async {
                  final t = await _pickTime(window.start);
                  if (t != null) {
                    onChanged(TimeWindow(
                        startHour: t.hour,
                        startMinute: t.minute,
                        endHour: window.endHour,
                        endMinute: window.endMinute));
                  }
                },
                child: Text('Desde ${_fmtTod(window.start)}'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton(
                onPressed: () async {
                  final t = await _pickTime(window.end);
                  if (t != null) {
                    onChanged(TimeWindow(
                        startHour: window.startHour,
                        startMinute: window.startMinute,
                        endHour: t.hour,
                        endMinute: t.minute));
                  }
                },
                child: Text('Hasta ${_fmtTod(window.end)}'),
              ),
            ),
          ]),
      ],
    );
  }
}
