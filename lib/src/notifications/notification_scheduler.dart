import 'dart:io';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../domain/models.dart';
import '../domain/service_calendar.dart';
import '../domain/trip_finder.dart';
import 'alert.dart';
import 'notification_plan.dart';

/// Maintains a bounded queue of dated notifications, replenished on app
/// launch/resume, alert edits, and background checks on Android and iOS.
class NotificationScheduler {
  NotificationScheduler(
    this._plugin, {
    tz.TZDateTime Function()? now,
    int? maxPending,
  }) : _now = now ?? nowInArgentina,
       _maxPending = maxPending ?? (Platform.isIOS ? 64 : 500);

  final FlutterLocalNotificationsPlugin _plugin;
  final tz.TZDateTime Function() _now;
  final int _maxPending;
  Future<void> _pending = Future.value();

  static const _channel = AndroidNotificationDetails(
    'train_alerts',
    'Alertas de horarios',
    channelDescription: 'Próximos trenes para tus alertas configuradas',
    importance: Importance.high,
    priority: Priority.high,
  );

  static Future<NotificationScheduler> initialize() async {
    tzdata.initializeTimeZones();
    final plugin = FlutterLocalNotificationsPlugin();
    await plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
    );
    return NotificationScheduler(plugin);
  }

  /// Requests platform permissions in context (first alert creation).
  /// Returns true when notifications are allowed.
  Future<bool> requestPermissions() async {
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (android != null) {
      final granted = await android.requestNotificationsPermission() ?? false;
      // Exact alarms make the alert fire at the configured minute. If the
      // user denies it we still schedule, inexactly (see _scheduleMode).
      if (await android.canScheduleExactNotifications() == false) {
        await android.requestExactAlarmsPermission();
      }
      return granted;
    }
    final ios = _plugin
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >();
    if (ios != null) {
      return await ios.requestPermissions(
            alert: true,
            badge: true,
            sound: true,
          ) ??
          false;
    }
    return true;
  }

  Future<AndroidScheduleMode> _scheduleMode() async {
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (android != null &&
        (await android.canScheduleExactNotifications() ?? false)) {
      return AndroidScheduleMode.exactAllowWhileIdle;
    }
    return AndroidScheduleMode.inexactAllowWhileIdle;
  }

  /// Replaces the pending queue, including legacy weekly notifications,
  /// without dismissing notifications that have already been delivered.
  /// Serialize calls so rapid alert edits cannot interleave cancellations.
  Future<void> rescheduleAll(
    List<Alert> alerts,
    Timetable timetable, {
    HolidayResolver? isHoliday,
  }) {
    final snapshot = List<Alert>.of(alerts);
    final result = _pending.then((_) async {
      final planned = planNotifications(
        snapshot,
        timetable,
        now: _now(),
        isHoliday: isHoliday,
        maxPending: _maxPending,
      );
      final mode = await _scheduleMode();
      await _plugin.cancelAllPendingNotifications();
      for (final notification in planned) {
        await _plugin.zonedSchedule(
          id: notification.id,
          title: notification.title,
          body: notification.body,
          scheduledDate: notification.fireAt,
          notificationDetails: const NotificationDetails(
            android: _channel,
            iOS: DarwinNotificationDetails(),
          ),
          androidScheduleMode: mode,
          // Deliberately one-off: repeating a holiday's body next week is wrong.
        );
      }
    });
    _pending = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }
}
