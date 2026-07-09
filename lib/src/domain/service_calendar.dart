import 'package:timezone/timezone.dart' as tz;

import 'models.dart';

/// All schedule reasoning happens in Argentina's timezone regardless of the
/// device's setting: the printed timetable is in local Buenos Aires time
/// (UTC-3, no DST).
tz.Location get argentina => tz.getLocation('America/Argentina/Buenos_Aires');

tz.TZDateTime nowInArgentina() => tz.TZDateTime.now(argentina);

/// Day type by weekday. [holiday] forces the Sunday-and-holidays table
/// (feriados run the Sunday service); the app has no holiday calendar, so
/// this comes from a user toggle.
DayType dayTypeFor(DateTime date, {bool holiday = false}) {
  if (holiday) return DayType.sundayHoliday;
  return switch (date.weekday) {
    DateTime.saturday => DayType.saturday,
    DateTime.sunday => DayType.sundayHoliday,
    _ => DayType.weekday,
  };
}
