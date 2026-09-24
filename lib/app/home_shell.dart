import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../features/alerts/alerts_screen.dart';
import '../features/profile/profile_screen.dart';
import '../providers/alerts_provider.dart';

/// Contenedor principal tras el login: navegación entre Alertas y Perfil.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final activeCount = context.watch<AlertsProvider>().activeCount;
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: const [AlertsScreen(), ProfileScreen()],
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
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: 'Perfil',
          ),
        ],
      ),
    );
  }
}
