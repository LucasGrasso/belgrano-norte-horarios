import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tren_bn_horarios/src/data/holiday_service.dart';
import 'package:tren_bn_horarios/src/data/timetable_service.dart';
import 'package:tren_bn_horarios/src/domain/models.dart';
import 'package:tren_bn_horarios/src/domain/trip_finder.dart';
import 'package:tren_bn_horarios/src/notifications/alert.dart';
import 'package:tren_bn_horarios/src/notifications/notification_scheduler.dart';
import 'package:tren_bn_horarios/src/state/providers.dart';

const oldTimetable = Timetable(
  scheduleNumber: 1,
  validFrom: '2026-01-01',
  fetchedAt: '',
  services: {},
);
const freshTimetable = Timetable(
  scheduleNumber: 2,
  validFrom: '2026-02-01',
  fetchedAt: '',
  services: {},
);

class _Service extends Fake implements TimetableService {
  final download = Completer<Timetable>();
  @override
  Future<Timetable?> loadStored() async => oldTimetable;
  @override
  Future<Timetable> fetchAndStore() => download.future;
  @override
  Future<Timetable?> updateIfNewMonth() async => null;
}

class _Scheduler extends Fake implements NotificationScheduler {
  int schedules = 0;
  @override
  Future<void> rescheduleAll(
    List<Alert> alerts,
    Timetable timetable, {
    HolidayResolver? isHoliday,
  }) async {
    schedules++;
  }
}

class _Holidays extends HolidaysController {
  @override
  Future<HolidayCalendar> build() async => const HolidayCalendar.empty();
}

class _Alerts extends AlertsController {
  @override
  Future<List<Alert>> build() async => [];
}

void main() {
  late _Service service;
  late _Scheduler scheduler;
  late ProviderContainer container;
  setUp(() {
    service = _Service();
    scheduler = _Scheduler();
    container = ProviderContainer(
      overrides: [
        timetableServiceProvider.overrideWith((ref) async => service),
        notificationSchedulerProvider.overrideWith((ref) async => scheduler),
        holidaysProvider.overrideWith(_Holidays.new),
        alertsProvider.overrideWith(_Alerts.new),
      ],
    );
  });
  tearDown(() => container.dispose());

  test(
    'refresh keeps stored data visible until the new timetable is ready',
    () async {
      await container.read(timetableProvider.future);
      final download = container.read(timetableProvider.notifier).download();
      await Future<void>.delayed(Duration.zero);
      expect(container.read(timetableProvider).value, same(oldTimetable));
      expect(container.read(timetableProvider).isLoading, isFalse);
      service.download.complete(freshTimetable);
      await download;
      expect(container.read(timetableProvider).value, same(freshTimetable));
      expect(scheduler.schedules, 1);
    },
  );

  test(
    'failed refresh preserves cached data and reports the failure',
    () async {
      await container.read(timetableProvider.future);
      final download = container.read(timetableProvider.notifier).download();
      final failure = expectLater(download, throwsException);
      service.download.completeError(Exception('offline'));
      await failure;
      expect(container.read(timetableProvider).value, same(oldTimetable));
    },
  );

  test(
    'launch reschedules alerts even when a monthly fetch is not due',
    () async {
      await container.read(timetableProvider.future);
      await container.read(timetableProvider.notifier).monthlyCheck();
      expect(scheduler.schedules, 1);
    },
  );
}
