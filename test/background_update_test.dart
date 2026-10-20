import 'package:flutter_test/flutter_test.dart';
import 'package:tren_bn_horarios/src/background/update_worker.dart';
import 'package:tren_bn_horarios/src/data/holiday_service.dart';
import 'package:tren_bn_horarios/src/data/timetable_service.dart';
import 'package:tren_bn_horarios/src/domain/models.dart';
import 'package:tren_bn_horarios/src/domain/trip_finder.dart';
import 'package:tren_bn_horarios/src/notifications/alert.dart';
import 'package:tren_bn_horarios/src/notifications/notification_scheduler.dart';

const timetable = Timetable(
  scheduleNumber: 1,
  validFrom: '',
  fetchedAt: '',
  services: {},
);

class _Service extends Fake implements TimetableService {
  @override
  Future<Timetable?> loadStored() async => timetable;
  @override
  Future<Timetable?> updateIfNewMonth() async => null; // same month / offline
}

class _Holidays extends Fake implements HolidayService {
  @override
  Future<HolidayCalendar> load() async =>
      const HolidayCalendar(loadedYears: {2026}, dates: {});
  @override
  Future<HolidayCalendar> ensureCurrentYears() async =>
      const HolidayCalendar(loadedYears: {2026}, dates: {'2026-07-09'});
}

class _Scheduler extends Fake implements NotificationScheduler {
  final holidays = <bool?>[];
  final alertCounts = <int>[];
  @override
  Future<void> rescheduleAll(
    List<Alert> alerts,
    Timetable timetable, {
    HolidayResolver? isHoliday,
  }) async {
    holidays.add(isHoliday?.call(DateTime(2026, 7, 9)));
    alertCounts.add(alerts.length);
  }
}

void main() {
  test(
    'background refills cached alerts then applies holidays without a new PDF',
    () async {
      final scheduler = _Scheduler();
      var loads = 0;
      await runBackgroundUpdate(
        timetableService: _Service(),
        holidayService: _Holidays(),
        loadAlerts: () async {
          loads++;
          return loads == 1
              ? [
                  const Alert(
                    id: 1,
                    from: 0,
                    to: 22,
                    hour: 7,
                    minute: 0,
                    weekdays: {1},
                  ),
                ]
              : [];
        },
        initializeScheduler: () async => scheduler,
      );
      expect(scheduler.holidays, [false, true]);
      // Re-read alerts after network operations, preserving deletions made meanwhile.
      expect(scheduler.alertCounts, [1, 0]);
    },
  );
}
