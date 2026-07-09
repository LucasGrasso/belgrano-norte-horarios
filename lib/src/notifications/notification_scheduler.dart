import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../domain/models.dart';
import '../domain/service_calendar.dart';
import '../domain/trip_finder.dart';
import 'alert.dart';

/// Schedules the recurring "next trains" notifications.
///
/// Because the timetable is static between monthly updates, each alert is
/// expanded into one *weekly repeating* zoned notification per selected
/// weekday, with the next departures for that weekday's service computed at
/// scheduling time. Everything is rescheduled whenever alerts change or the
/// timetable updates, so the content can never drift more than one month.
class NotificationScheduler {
  NotificationScheduler(this._plugin);

  final FlutterLocalNotificationsPlugin _plugin;

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
        iOS: DarwinInitializationSettings(),
      ),
    );
    return NotificationScheduler(plugin);
  }

  /// Requests platform permissions in context (first alert creation).
  /// Returns true when notifications are allowed.
  Future<bool> requestPermissions() async {
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android != null) {
      final granted = await android.requestNotificationsPermission() ?? false;
      // Exact alarms make the alert fire at the configured minute. If the
      // user denies it we still schedule, inexactly (see _scheduleMode).
      if (await android.canScheduleExactNotifications() == false) {
        await android.requestExactAlarmsPermission();
      }
      return granted;
    }
    final ios = _plugin.resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin>();
    if (ios != null) {
      return await ios.requestPermissions(alert: true, badge: true, sound: true) ??
          false;
    }
    return true;
  }

  Future<AndroidScheduleMode> _scheduleMode() async {
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android != null &&
        (await android.canScheduleExactNotifications() ?? false)) {
      return AndroidScheduleMode.exactAllowWhileIdle;
    }
    return AndroidScheduleMode.inexactAllowWhileIdle;
  }

  /// Cancels everything and reschedules all enabled alerts against
  /// [timetable]. Call after any alert edit and after timetable updates.
  Future<void> rescheduleAll(List<Alert> alerts, Timetable timetable) async {
    await _plugin.cancelAll();
    final mode = await _scheduleMode();
    for (final alert in alerts.where((a) => a.enabled)) {
      for (final weekday in alert.weekdays) {
        await _scheduleWeekly(alert, weekday, timetable, mode);
      }
    }
  }

  Future<void> _scheduleWeekly(Alert alert, int weekday, Timetable timetable,
      AndroidScheduleMode mode) async {
    final fireAt = _nextInstanceOf(weekday, alert.hour, alert.minute);
    final departures = findNextDepartures(
      timetable,
      from: alert.from,
      to: alert.to,
      when: fireAt,
      limit: 3,
    );
    final route = '${kStations[alert.from]} → ${kStations[alert.to]}';
    final body = departures.isEmpty
        ? 'Sin más servicios programados a esta hora.'
        : departures
            .map((d) =>
                '${_hhmm(d.departs)} (llega ${_hhmm(d.arrives)})')
            .join('  ·  ');

    await _plugin.zonedSchedule(
      id: alert.id * 10 + weekday,
      title: 'Próximos trenes $route',
      body: body,
      scheduledDate: fireAt,
      notificationDetails: const NotificationDetails(android: _channel),
      androidScheduleMode: mode,
      matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
    );
  }

  /// Next occurrence of [weekday] at hh:mm in Argentina time.
  tz.TZDateTime _nextInstanceOf(int weekday, int hour, int minute) {
    final now = nowInArgentina();
    var t = tz.TZDateTime(
        argentina, now.year, now.month, now.day, hour, minute);
    while (t.weekday != weekday || t.isBefore(now)) {
      t = t.add(const Duration(days: 1));
      t = tz.TZDateTime(argentina, t.year, t.month, t.day, hour, minute);
    }
    return t;
  }

  static String _hhmm(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
}
