import 'package:timezone/timezone.dart' as tz;

import 'models.dart';

/// Shared horizon for dated alerts and holiday coverage.
const kScheduleHorizonDays = 60;

/// All schedule reasoning happens in Argentina's timezone regardless of the
/// device's setting: the printed timetable is in local Buenos Aires time
/// (UTC-3, no DST).
tz.Location get argentina => tz.getLocation('America/Argentina/Buenos_Aires');

tz.TZDateTime nowInArgentina() => tz.TZDateTime.now(argentina);

/// Day type by weekday. [holiday] forces the Sunday-and-holidays table
/// (feriados run the Sunday service). The downloaded calendar or the manual
/// fallback toggle supplies this value.
DayType dayTypeFor(DateTime date, {bool holiday = false}) {
  if (holiday) return DayType.sundayHoliday;
  return switch (date.weekday) {
    DateTime.saturday => DayType.saturday,
    DateTime.sunday => DayType.sundayHoliday,
    _ => DayType.weekday,
  };
}
