import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:workmanager/workmanager.dart';

import '../data/holiday_service.dart';
import '../data/timetable_store.dart';
import '../data/timetable_service.dart';
import '../notifications/alert.dart';
import '../notifications/notification_scheduler.dart';

const _updateTask = 'ar.com.lucasgrasso.tren_bn_horarios.monthlyUpdate';

/// Background entry point. Runs in its own isolate: everything it needs is
/// re-initialized here.
@pragma('vm:entry-point')
void updateWorkerDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    WidgetsFlutterBinding.ensureInitialized();
    try {
      final store = await TimetableStore.open();
      final service = TimetableService(store);
      final holidays = await HolidayService.open();
      final calendar = await holidays.ensureCurrentYears();
      final updated = await service.updateIfNewMonth();
      if (updated != null) {
        final scheduler = await NotificationScheduler.initialize();
        await scheduler.rescheduleAll(await AlertStore().load(), updated,
            isHoliday: calendar.isHoliday);
      }
      // Success also when not due / fetch failed: the periodic task must
      // keep running and retry on its own cadence.
      return true;
    } on Exception {
      return true;
    }
  });
}

/// Registers the periodic check (Android). WorkManager respects Doze and
/// batches with other jobs; a 12h cadence guarantees the refetch lands
/// within the first day of each month without meaningful battery cost.
/// On iOS the on-launch check in the app covers updates instead.
Future<void> registerMonthlyUpdateTask() async {
  if (!Platform.isAndroid) return;
  await Workmanager().initialize(updateWorkerDispatcher);
  await Workmanager().registerPeriodicTask(
    _updateTask,
    _updateTask,
    frequency: const Duration(hours: 12),
    constraints: Constraints(networkType: NetworkType.connected),
    existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
  );
}
