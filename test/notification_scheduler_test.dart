import 'dart:async';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;
import 'package:tren_bn_horarios/src/domain/models.dart';
import 'package:tren_bn_horarios/src/domain/service_calendar.dart';
import 'package:tren_bn_horarios/src/notifications/alert.dart';
import 'package:tren_bn_horarios/src/notifications/notification_plan.dart';
import 'package:tren_bn_horarios/src/notifications/notification_scheduler.dart';

final timetable = Timetable(
  scheduleNumber: 1,
  validFrom: '',
  fetchedAt: '',
  services: {
    for (final type in DayType.values)
      type: {
        Direction.toVillaRosa: [
          Trip(
            number: 101,
            stops: [
              Stop(0, (type == DayType.sundayHoliday ? 11 : 8) * 60),
              Stop(22, (type == DayType.sundayHoliday ? 12 : 9) * 60),
            ],
          ),
        ],
      },
  },
);

Alert alert(
  int id, {
  int hour = 7,
  Set<int> days = const {1, 2, 3, 4, 5, 6, 7},
  bool enabled = true,
}) => Alert(
  id: id,
  from: 0,
  to: 22,
  hour: hour,
  minute: 0,
  weekdays: days,
  enabled: enabled,
);

class _Plugin extends Fake implements FlutterLocalNotificationsPlugin {
  final scheduled =
      <
        ({int id, tz.TZDateTime date, String? body, DateTimeComponents? repeat})
      >[];
  int cancelled = 0;
  Completer<void>? gate;

  @override
  T? resolvePlatformSpecificImplementation<
    T extends FlutterLocalNotificationsPlatform
  >() => null;

  @override
  Future<void> cancelAllPendingNotifications() async {
    cancelled++;
    scheduled.clear();
    if (gate != null) await gate!.future;
  }

  @override
  Future<void> zonedSchedule({
    required int id,
    required tz.TZDateTime scheduledDate,
    required NotificationDetails notificationDetails,
    required AndroidScheduleMode androidScheduleMode,
    String? title,
    String? body,
    String? payload,
    DateTimeComponents? matchDateTimeComponents,
  }) async {
    scheduled.add((
      id: id,
      date: scheduledDate,
      body: body,
      repeat: matchDateTimeComponents,
    ));
  }
}

void main() {
  setUpAll(tzdata.initializeTimeZones);
  tz.TZDateTime at(int day, [int hour = 6]) =>
      tz.TZDateTime(argentina, 2026, 7, day, hour);

  test('holiday and next normal week each get their own departures', () {
    final planned = planNotifications(
      [
        alert(1, days: {DateTime.thursday}),
      ],
      timetable,
      now: at(8),
      isHoliday: (d) => d.month == 7 && d.day == 9,
    );
    expect(planned[0].fireAt, at(9, 7));
    expect(planned[0].body, startsWith('11:00'));
    expect(planned[1].fireAt, at(16, 7));
    expect(planned[1].body, startsWith('08:00'));
  });

  test('normal week then holiday is also computed separately', () {
    final planned = planNotifications(
      [
        alert(1, days: {DateTime.thursday}),
      ],
      timetable,
      now: at(8),
      isHoliday: (d) => d.month == 7 && d.day == 16,
    );
    expect(planned[0].body, startsWith('08:00'));
    expect(planned[1].body, startsWith('11:00'));
  });

  test('New Year and Argentina dates stay correct across device timezones', () {
    final now = tz.TZDateTime.from(DateTime.utc(2026, 12, 31, 3), argentina);
    final planned = planNotifications(
      [alert(1)],
      timetable,
      now: now,
      isHoliday: (d) => d.month == 1 && d.day == 1,
    );
    final newYear = planned.firstWhere(
      (p) => p.fireAt.month == 1 && p.fireAt.day == 1,
    );
    expect(newYear.fireAt.year, 2027);
    expect(newYear.fireAt.hour, 7);
    expect(newYear.body, startsWith('11:00'));
    expect(newYear.fireAt.toUtc().hour, 10);
  });

  test(
    'capacity applies across all alerts and retains earliest occurrences',
    () {
      final planned = planNotifications(
        [alert(2, hour: 9), alert(1)],
        timetable,
        now: at(8),
        maxPending: 64,
        isHoliday: (_) => false,
      );
      expect(planned, hasLength(64));
      expect(planned.map((p) => p.id).toSet(), hasLength(64));
      expect(planned[0].fireAt.hour, 7);
      expect(planned[1].fireAt.hour, 9);
      for (var i = 1; i < planned.length; i++) {
        expect(planned[i].fireAt.isBefore(planned[i - 1].fireAt), isFalse);
      }
      expect(planned.last.id, 0);
      expect(planned.last.title, contains('Renová'));
    },
  );

  test('disabled, invalid, empty and past occurrences are omitted', () {
    expect(
      planNotifications(
        [alert(1, enabled: false), alert(2, days: {})],
        timetable,
        now: at(8),
      ),
      isEmpty,
    );
    expect(
      planNotifications([alert(1).copyWith(from: -1)], timetable, now: at(8)),
      isEmpty,
    );
    final planned = planNotifications([alert(1)], timetable, now: at(8, 7));
    expect(planned.first.fireAt.day, 9);
    expect(
      planNotifications([alert(1)], timetable, now: at(8), maxPending: 1),
      isEmpty,
    );
  });

  test('unknown holiday coverage is disclosed in alert content', () {
    final planned = planNotifications([alert(1)], timetable, now: at(8));
    expect(planned.first.body, contains('Feriados sin verificar'));
  });

  test(
    'scheduler replaces legacy pending alerts with non-repeating dated ones',
    () async {
      final plugin = _Plugin();
      final scheduler = NotificationScheduler(
        plugin,
        now: () => at(8),
        maxPending: 64,
      );
      await scheduler.rescheduleAll(
        [alert(1)],
        timetable,
        isHoliday: (_) => false,
      );
      expect(plugin.cancelled, 1);
      expect(plugin.scheduled, isNotEmpty);
      expect(plugin.scheduled.every((p) => p.repeat == null), isTrue);
      await scheduler.rescheduleAll([], timetable);
      expect(plugin.cancelled, 2);
      expect(plugin.scheduled, isEmpty);
    },
  );

  test('overlapping reschedules are serialized and newest edit wins', () async {
    final plugin = _Plugin()..gate = Completer<void>();
    final scheduler = NotificationScheduler(plugin, now: () => at(8));
    final first = scheduler.rescheduleAll([alert(1)], timetable);
    await Future<void>.delayed(Duration.zero);
    final second = scheduler.rescheduleAll([], timetable);
    await Future<void>.delayed(Duration.zero);
    expect(plugin.cancelled, 1);
    plugin.gate!.complete();
    await Future.wait([first, second]);
    expect(plugin.cancelled, 2);
    expect(plugin.scheduled, isEmpty);
  });
}
