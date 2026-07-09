import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/providers.dart';
import 'alerts_screen.dart';
import 'home_screen.dart';
import 'settings_screen.dart';

class TrenApp extends StatelessWidget {
  const TrenApp({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.fromSeed(seedColor: const Color(0xFFC8102E));
    final darkScheme = ColorScheme.fromSeed(
        seedColor: const Color(0xFFC8102E), brightness: Brightness.dark);
    return MaterialApp(
      title: 'Tren Belgrano Norte',
      theme: ThemeData(colorScheme: scheme),
      darkTheme: ThemeData(colorScheme: darkScheme),
      home: const _Shell(),
    );
  }
}

class _Shell extends ConsumerStatefulWidget {
  const _Shell();

  @override
  ConsumerState<_Shell> createState() => _ShellState();
}

class _ShellState extends ConsumerState<_Shell> {
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    // Silent monthly check once the first frame is up.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(timetableProvider.notifier).monthlyCheck();
    });
  }

  @override
  Widget build(BuildContext context) {
    final timetable = ref.watch(timetableProvider);

    final body = timetable.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => FirstRunScreen(error: e),
      data: (t) {
        if (t == null) return const FirstRunScreen();
        return switch (_tab) {
          0 => const HomeScreen(),
          1 => const AlertsScreen(),
          _ => const SettingsScreen(),
        };
      },
    );

    final hasData = timetable.value != null;

    return Scaffold(
      appBar: AppBar(
        title: Text(switch (_tab) {
          0 => 'Tren Belgrano Norte',
          1 => 'Alertas',
          _ => 'Ajustes',
        }),
      ),
      body: body,
      bottomNavigationBar: hasData
          ? NavigationBar(
              selectedIndex: _tab,
              onDestinationSelected: (i) => setState(() => _tab = i),
              destinations: const [
                NavigationDestination(
                    icon: Icon(Icons.search), label: 'Buscar'),
                NavigationDestination(
                    icon: Icon(Icons.notifications_outlined),
                    selectedIcon: Icon(Icons.notifications),
                    label: 'Alertas'),
                NavigationDestination(
                    icon: Icon(Icons.settings_outlined),
                    selectedIcon: Icon(Icons.settings),
                    label: 'Ajustes'),
              ],
            )
          : null,
    );
  }
}
