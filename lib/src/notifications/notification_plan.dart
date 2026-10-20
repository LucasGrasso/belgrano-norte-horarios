import 'package:timezone/timezone.dart' as tz;

import '../domain/models.dart';
import '../domain/service_calendar.dart';
import '../domain/trip_finder.dart';
import 'alert.dart';

class PlannedNotification {
  const PlannedNotification({
    required this.id,
    required this.fireAt,
    required this.title,
    required this.body,
  });

  final int id;
  final tz.TZDateTime fireAt;
  final String title;
  final String body;
}

/// Earliest dated occurrences across ALL alerts, with one slot reserved for a
/// renewal reminder. Each occurrence uses its own service-day holiday calendar.
List<PlannedNotification> planNotifications(
  List<Alert> alerts,
  Timetable timetable, {
  required tz.TZDateTime now,
  HolidayResolver? isHoliday,
  int maxPending = 64,
}) {
  if (maxPending < 2) return [];
  final occurrences = <({Alert alert, tz.TZDateTime fireAt})>[];
  final valid = alerts.where(
    (a) =>
        a.enabled &&
        a.from >= 0 &&
        a.to >= 0 &&
        a.from < kStations.length &&
        a.to < kStations.length &&
        a.from != a.to &&
        a.hour >= 0 &&
        a.hour < 24 &&
        a.minute >= 0 &&
        a.minute < 60,
  );
  for (var day = 0; day < kScheduleHorizonDays; day++) {
    for (final alert in valid) {
      final fireAt = tz.TZDateTime(
        argentina,
        now.year,
        now.month,
        now.day + day,
        alert.hour,
        alert.minute,
      );
      if (fireAt.isAfter(now) && alert.weekdays.contains(fireAt.weekday)) {
        occurrences.add((alert: alert, fireAt: fireAt));
      }
    }
  }
  occurrences.sort((a, b) {
    final time = a.fireAt.compareTo(b.fireAt);
    return time != 0 ? time : a.alert.id.compareTo(b.alert.id);
  });
  final planned = <PlannedNotification>[];
  for (final occurrence in occurrences.take(maxPending - 1)) {
    final alert = occurrence.alert;
    final fireAt = occurrence.fireAt;
    final departures = findNextDepartures(
      timetable,
      from: alert.from,
      to: alert.to,
      when: fireAt,
      isHoliday: isHoliday,
      limit: 3,
    );
    var body = departures.isEmpty
        ? 'Sin más servicios programados a esta hora.'
        : departures
              .map((d) => '${_hhmm(d.departs)} (llega ${_hhmm(d.arrives)})')
              .join('  ·  ');
    if (isHoliday?.call(fireAt) == null) {
      body += ' Feriados sin verificar para esta fecha.';
    }
    planned.add(
      PlannedNotification(
        id: planned.length + 1,
        fireAt: fireAt,
        title:
            'Próximos trenes ${kStations[alert.from]} → ${kStations[alert.to]}',
        body: body,
      ),
    );
  }
  if (planned.isNotEmpty) {
    planned.add(
      PlannedNotification(
        id: 0,
        fireAt: planned.last.fireAt.add(const Duration(minutes: 1)),
        title: 'Renová tus alertas de trenes',
        body:
            'Abrí la app para actualizar horarios y programar las próximas alertas.',
      ),
    );
  }
  return planned;
}

String _hhmm(DateTime t) =>
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
