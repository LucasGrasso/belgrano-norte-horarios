import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../state/providers.dart';
import 'alerts_screen.dart';
import 'brand.dart';
import 'home_screen.dart';
import 'settings_screen.dart';

class TrenApp extends StatelessWidget {
  const TrenApp({super.key});

  @override
  Widget build(BuildContext context) {
    // fromSeed desaturates everything into pastels; pin the true brand red
    // as primary and keep surfaces neutral so the UI reads red-on-white
    // instead of pink.
    final scheme = ColorScheme.fromSeed(seedColor: kBrandColor).copyWith(
      primary: kBrandColor,
      surface: Colors.white,
    );
    final darkScheme = ColorScheme.fromSeed(
        seedColor: kBrandColor, brightness: Brightness.dark);
    // The app bar is always the brand-red banner (like the official site);
    // scrolledUnderElevation 0 keeps its color stable when content scrolls.
    ThemeData themed(ColorScheme s, {required bool dark}) => ThemeData(
          colorScheme: s,
          fontFamily: 'Segoe UI',
          scaffoldBackgroundColor: dark ? null : const Color(0xFFF6F5F4),
          cardTheme: dark
              ? null
              : const CardThemeData(color: Colors.white, elevation: 1),
          navigationBarTheme: dark
              ? null
              : NavigationBarThemeData(
                  backgroundColor: Colors.white,
                  indicatorColor: kBrandColor.withValues(alpha: 0.12),
                ),
          appBarTheme: const AppBarTheme(
            backgroundColor: kBrandColor,
            foregroundColor: Colors.white,
            scrolledUnderElevation: 0,
          ),
        );
    return MaterialApp(
      title: 'Tren Belgrano Norte',
      theme: themed(scheme, dark: false),
      darkTheme: themed(darkScheme, dark: true),
      home: const _Shell(),
    );
  }
}

/// Site-style banner: white circled train logo + bold two-line wordmark.
class _BrandTitle extends StatelessWidget {
  const _BrandTitle();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SvgPicture.asset('logo.svg', height: 40),
        const SizedBox(width: 10),
        const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Tren',
                style: TextStyle(
                    fontSize: 17, fontWeight: FontWeight.w700, height: 1.1)),
            Text('Belgrano Norte',
                style: TextStyle(
                    fontSize: 17, fontWeight: FontWeight.w700, height: 1.1)),
          ],
        ),
      ],
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
    // Silent monthly timetable check + yearly feriados fetch once the first
    // frame is up.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(timetableProvider.notifier).monthlyCheck();
      ref.read(holidaysProvider.notifier).refresh();
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
        titleSpacing: 16,
        title: const _BrandTitle(),
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
