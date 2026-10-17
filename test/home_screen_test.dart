import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;
import 'package:tren_bn_horarios/src/data/holiday_service.dart';
import 'package:tren_bn_horarios/src/domain/models.dart';
import 'package:tren_bn_horarios/src/domain/service_calendar.dart';
import 'package:tren_bn_horarios/src/state/providers.dart';
import 'package:tren_bn_horarios/src/ui/home_screen.dart';

class _TimetableController extends TimetableController {
  @override
  Future<Timetable?> build() async => Timetable(
    scheduleNumber: 1,
    validFrom: '2026-01-01',
    fetchedAt: '',
    services: {
      DayType.weekday: {
        Direction.toVillaRosa: [
          _trip(101, 14 * 60 + 35),
          _trip(103, 15 * 60 + 5),
          _trip(105, 23 * 60 + 55),
        ],
      },
      DayType.saturday: {
        Direction.toVillaRosa: [_trip(201, 5)],
      },
    },
  );
}

Trip _trip(int number, int departure) =>
    Trip(number: number, stops: [Stop(0, departure), Stop(22, departure + 90)]);

class _HolidaysController extends HolidaysController {
  @override
  Future<HolidayCalendar> build() async => const HolidayCalendar.empty();
}

String firstTrain(WidgetTester tester) => tester
    .widgetList<Text>(find.byType(Text))
    .map((text) => text.data ?? '')
    .firstWhere((text) => text.startsWith('Tren '));

void main() {
  setUpAll(tzdata.initializeTimeZones);
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> openHome(
    WidgetTester tester,
    tz.TZDateTime Function() now,
  ) async {
    tester.binding.handleAppLifecycleStateChanged(
      AppLifecycleState.resumed,
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          timetableProvider.overrideWith(_TimetableController.new),
          holidaysProvider.overrideWith(_HolidaysController.new),
        ],
        child: MaterialApp(
          home: Scaffold(body: HomeScreen(now: now)),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('resume immediately replaces departures from half an hour ago', (
    tester,
  ) async {
    var now = tz.TZDateTime(argentina, 2026, 7, 6, 14, 30);
    await openHome(tester, () => now);
    expect(firstTrain(tester), 'Tren 101');

    tester.binding.handleAppLifecycleStateChanged(
      AppLifecycleState.paused,
    );
    now = now.add(const Duration(minutes: 30));
    // No timer tick or widget rebuild is needed while in the background.
    tester.binding.handleAppLifecycleStateChanged(
      AppLifecycleState.resumed,
    );
    await tester.pump();
    expect(firstTrain(tester), 'Tren 103');
    expect(find.text('en 5 min'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('foreground refresh updates waits and removes past departures', (
    tester,
  ) async {
    var now = tz.TZDateTime(argentina, 2026, 7, 6, 14, 30);
    await openHome(tester, () => now);
    expect(find.text('en 5 min'), findsOneWidget);

    now = now.add(const Duration(minutes: 1));
    await tester.pump(const Duration(seconds: 30));
    expect(find.text('en 4 min'), findsOneWidget);

    now = now.add(const Duration(minutes: 5));
    await tester.pump(const Duration(seconds: 30));
    expect(firstTrain(tester), 'Tren 103');
    await tester.pumpWidget(const SizedBox.shrink());
    // Disposing cancels the periodic timer and lifecycle observer.
    await tester.pump(const Duration(minutes: 1));
    tester.binding.handleAppLifecycleStateChanged(
      AppLifecycleState.paused,
    );
    tester.binding.handleAppLifecycleStateChanged(
      AppLifecycleState.resumed,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('resume across midnight uses the new service day', (
    tester,
  ) async {
    var now = tz.TZDateTime(argentina, 2026, 7, 10, 23, 50);
    await openHome(tester, () => now);
    expect(firstTrain(tester), 'Tren 105');

    tester.binding.handleAppLifecycleStateChanged(
      AppLifecycleState.paused,
    );
    now = tz.TZDateTime(argentina, 2026, 7, 11, 0, 1);
    tester.binding.handleAppLifecycleStateChanged(
      AppLifecycleState.resumed,
    );
    await tester.pump();
    expect(firstTrain(tester), 'Tren 201');
    expect(find.text('en 4 min'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('custom search stays fixed until returning to Ahora', (
    tester,
  ) async {
    var now = tz.TZDateTime(argentina, 2026, 7, 6, 14, 30);
    await openHome(tester, () => now);
    await tester.tap(find.text('Ahora'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    now = now.add(const Duration(minutes: 30));
    await tester.pump(const Duration(seconds: 30));
    expect(firstTrain(tester), 'Tren 101');
    tester.binding.handleAppLifecycleStateChanged(
      AppLifecycleState.paused,
    );
    tester.binding.handleAppLifecycleStateChanged(
      AppLifecycleState.resumed,
    );
    await tester.pump();
    expect(firstTrain(tester), 'Tren 101');

    await tester.tap(find.byTooltip('Volver a "ahora"'));
    await tester.pump();
    expect(firstTrain(tester), 'Tren 103');
    expect(find.text('Ahora'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
