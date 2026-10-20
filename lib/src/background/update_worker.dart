import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:workmanager/workmanager.dart';

import '../data/holiday_service.dart';
import '../data/timetable_store.dart';
import '../data/timetable_service.dart';
import '../domain/models.dart';
import '../notifications/alert.dart';
import '../notifications/notification_scheduler.dart';

// Keep identical to Info.plist / AppDelegate and the existing Android task.
const updateTask = 'ar.com.lucasgrasso.tren_bn_horarios.monthlyUpdate';

/// Renew cached notifications before networking, so an offline/expired iOS
/// execution still extends the queue. Then apply holiday and timetable changes
/// independently of whether a new monthly PDF was available.
Future<void> runBackgroundUpdate({
  required TimetableService timetableService,
  required HolidayService holidayService,
  required Future<List<Alert>> Function() loadAlerts,
  required Future<NotificationScheduler> Function() initializeScheduler,
}) async {
  final cached = await timetableService.loadStored();
  final scheduler = await initializeScheduler();
  if (cached != null) {
    final calendar = await holidayService.load();
    await scheduler.rescheduleAll(
      await loadAlerts(),
      cached,
      isHoliday: calendar.isHoliday,
    );
  }
  final results = await Future.wait<Object?>([
    holidayService.ensureCurrentYears(),
    timetableService.updateIfNewMonth(),
  ]);
  final timetable = results[1] ?? cached;
  if (timetable != null) {
    final calendar = results[0] as HolidayCalendar;
    await scheduler.rescheduleAll(
      await loadAlerts(),
      timetable as Timetable,
      isHoliday: calendar.isHoliday,
    );
  }
}

/// Runs in its own isolate, including when iOS launches a headless engine.
@pragma('vm:entry-point')
void updateWorkerDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    WidgetsFlutterBinding.ensureInitialized();
    ui.DartPluginRegistrant.ensureInitialized();
    TimetableService? service;
    HolidayService? holidays;
    try {
      service = TimetableService(
        await TimetableStore.open(),
        requestTimeout: const Duration(seconds: 10),
      );
      holidays = await HolidayService.open(
        requestTimeout: const Duration(seconds: 10),
      );
      await runBackgroundUpdate(
        timetableService: service,
        holidayService: holidays,
        loadAlerts: AlertStore().load,
        initializeScheduler: NotificationScheduler.initialize,
      );
      return true;
    } on Exception catch (error) {
      debugPrint('Background schedule update failed: $error');
      return false;
    } finally {
      service?.close();
      holidays?.close();
    }
  });
}

/// Both systems choose actual execution times. This requests a 12-hour check;
/// the services decide when the monthly PDF and fortnightly feeds are due.
/// No network constraint: offline runs can still renew cached alert content.
Future<void> registerMonthlyUpdateTask() async {
  if (!Platform.isAndroid && !Platform.isIOS) return;
  await Workmanager().initialize(updateWorkerDispatcher);
  await Workmanager().registerPeriodicTask(
    updateTask,
    updateTask,
    frequency: const Duration(hours: 12),
    initialDelay: const Duration(hours: 12),
    existingWorkPolicy: ExistingPeriodicWorkPolicy.update,
  );
}
