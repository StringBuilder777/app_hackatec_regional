import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../features/alerts/alerts_screen.dart';
import '../features/devices/devices_list_screen.dart';
import '../features/profile/profile_screen.dart';
import '../providers/alerts_provider.dart';
import '../providers/devices_provider.dart';

/// Contenedor principal tras el login: navegación entre Alertas,
/// Dispositivos y Perfil.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> with WidgetsBindingObserver {
  int _index = 0;
  late final AlertsProvider _alerts;
  late final DevicesProvider _devices;
  StreamSubscription<String>? _caseUpdates;

  @override
  void initState() {
    super.initState();
    _alerts = context.read<AlertsProvider>();
    _devices = context.read<DevicesProvider>();
    WidgetsBinding.instance.addObserver(this);
    // Contrato de polling: GET /cases cada 5 s mientras hay sesión y la app
    // está al frente. Un caso actualizado se avisa dentro de la app.
    _alerts.startPolling();
    _caseUpdates = _alerts.caseUpdates.listen((message) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(message)));
    });
  }

  /// En segundo plano se pausa el polling; al volver se refresca de inmediato.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _alerts.startPolling();
      _devices.resumePolling();
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      _alerts.stopPolling();
      _devices.pausePolling();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _caseUpdates?.cancel();
    _alerts.stopPolling();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final activeCount = context.watch<AlertsProvider>().activeCount;
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: const [
          AlertsScreen(),
          DevicesListScreen(),
          ProfileScreen(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: [
          NavigationDestination(
            icon: Badge(
              isLabelVisible: activeCount > 0,
              label: Text('$activeCount'),
              child: const Icon(Icons.notifications_outlined),
            ),
            selectedIcon: const Icon(Icons.notifications),
            label: 'Alertas',
          ),
          const NavigationDestination(
            icon: Icon(Icons.sensors_outlined),
            selectedIcon: Icon(Icons.sensors),
            label: 'Dispositivos',
          ),
          const NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: 'Perfil',
          ),
        ],
      ),
    );
  }
}
