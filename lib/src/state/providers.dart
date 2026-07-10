import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/holiday_service.dart';
import '../data/timetable_service.dart';
import '../data/timetable_store.dart';
import '../domain/models.dart';
import '../notifications/alert.dart';
import '../notifications/notification_scheduler.dart';

final timetableServiceProvider = FutureProvider<TimetableService>((ref) async {
  final store = await TimetableStore.open();
  return TimetableService(store);
});

final notificationSchedulerProvider =
    FutureProvider<NotificationScheduler>((ref) => NotificationScheduler.initialize());

/// National-holiday calendar (feriados run the Sunday timetable).
class HolidaysController extends AsyncNotifier<HolidayCalendar> {
  @override
  Future<HolidayCalendar> build() async {
    final service = await HolidayService.open();
    return service.load();
  }

  /// Fetches missing years (once per year in practice). Silent on failure.
  Future<void> refresh() async {
    final service = await HolidayService.open();
    final updated = await service.ensureCurrentYears();
    state = AsyncData(updated);
  }
}

final holidaysProvider =
    AsyncNotifierProvider<HolidaysController, HolidayCalendar>(HolidaysController.new);

/// The timetable. `null` means "never fetched yet" (first-run screen).
class TimetableController extends AsyncNotifier<Timetable?> {
  @override
  Future<Timetable?> build() async {
    final service = await ref.watch(timetableServiceProvider.future);
    return service.loadStored();
  }

  /// Explicit fetch (first run, or "Actualizar ahora"). Errors surface in
  /// [state] but never clobber previously loaded data on refresh failure.
  Future<void> download() async {
    final service = await ref.read(timetableServiceProvider.future);
    final previous = state.value;
    state = const AsyncLoading();
    try {
      final fresh = await service.fetchAndStore();
      state = AsyncData(fresh);
      await _rescheduleAlerts(fresh);
    } on Exception catch (e, st) {
      state = previous == null ? AsyncError(e, st) : AsyncData(previous);
      if (previous != null) rethrow; // caller shows a snackbar
    }
  }

  /// Silent check on app launch: refetch if the Argentina month changed.
  Future<void> monthlyCheck() async {
    final service = await ref.read(timetableServiceProvider.future);
    final updated = await service.updateIfNewMonth();
    if (updated != null) {
      state = AsyncData(updated);
      await _rescheduleAlerts(updated);
    }
  }

  Future<void> _rescheduleAlerts(Timetable timetable) async {
    final scheduler = await ref.read(notificationSchedulerProvider.future);
    final alerts = await ref.read(alertsProvider.future);
    final holidays = ref.read(holidaysProvider).value;
    await scheduler.rescheduleAll(alerts, timetable,
        isHoliday: holidays?.isHoliday);
  }
}

final timetableProvider =
    AsyncNotifierProvider<TimetableController, Timetable?>(TimetableController.new);

class AlertsController extends AsyncNotifier<List<Alert>> {
  final _store = AlertStore();

  @override
  Future<List<Alert>> build() => _store.load();

  Future<void> upsert(Alert alert) async {
    final current = [...await future];
    final i = current.indexWhere((a) => a.id == alert.id);
    if (i >= 0) {
      current[i] = alert;
    } else {
      current.add(alert);
    }
    await _persistAndReschedule(current);
  }

  Future<void> remove(int id) async {
    final current = [...await future]..removeWhere((a) => a.id == id);
    await _persistAndReschedule(current);
  }

  Future<int> nextId() => _store.nextId();

  Future<void> _persistAndReschedule(List<Alert> alerts) async {
    await _store.save(alerts);
    state = AsyncData(alerts);
    final timetable = ref.read(timetableProvider).value;
    if (timetable != null) {
      final scheduler = await ref.read(notificationSchedulerProvider.future);
      final holidays = ref.read(holidaysProvider).value;
      await scheduler.rescheduleAll(alerts, timetable,
          isHoliday: holidays?.isHoliday);
    }
  }
}

final alertsProvider =
    AsyncNotifierProvider<AlertsController, List<Alert>>(AlertsController.new);
