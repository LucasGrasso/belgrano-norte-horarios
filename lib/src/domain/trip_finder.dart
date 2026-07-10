import 'package:timezone/timezone.dart' as tz;

import 'models.dart';
import 'service_calendar.dart';

/// One concrete departure answering a "next trains" query.
class Departure {
  const Departure({
    required this.trainNumber,
    required this.departs,
    required this.arrives,
  });

  final int trainNumber;
  final tz.TZDateTime departs;
  final tz.TZDateTime arrives;

  Duration get duration => arrives.difference(departs);
}

/// Resolves whether a calendar day is a feriado. Returns null when unknown
/// (holiday feed not downloaded for that year).
typedef HolidayResolver = bool? Function(DateTime day);

/// Finds departures from [from] to [to] at or after [when] (Argentina time).
///
/// Timetable times belong to a *service day* and may run past midnight
/// (stored as minutes > 1440), so both the query date's table and the
/// previous day's table contribute candidates — e.g. at 00:10 on a Tuesday
/// the 23:45 Monday train that reaches Villa Rosa at 01:15 is still relevant.
///
/// Feriados run the Sunday table. [isHoliday] (the downloaded calendar) is
/// consulted per service day; where it has no data, the manual [holiday]
/// toggle applies to the queried date only.
List<Departure> findNextDepartures(
  Timetable timetable, {
  required int from,
  required int to,
  required tz.TZDateTime when,
  bool holiday = false,
  HolidayResolver? isHoliday,
  int limit = 10,
}) {
  if (from == to) return const [];
  final dir = to > from ? Direction.toVillaRosa : Direction.toRetiro;

  final results = <Departure>[];
  for (final dayOffset in [-1, 0, 1]) {
    final serviceMidnight = tz.TZDateTime(
        argentina, when.year, when.month, when.day + dayOffset);
    final isQueriedDate = dayOffset == 0;
    final auto = isHoliday?.call(serviceMidnight);
    final dayType = dayTypeFor(serviceMidnight,
        holiday: auto ?? (holiday && isQueriedDate));
    for (final trip in timetable.tripsFor(dayType, dir)) {
      final dep = trip.minutesAt(from);
      final arr = trip.minutesAt(to);
      if (dep == null || arr == null || arr <= dep) continue;
      final departs = serviceMidnight.add(Duration(minutes: dep));
      if (departs.isBefore(when)) continue;
      results.add(Departure(
        trainNumber: trip.number,
        departs: departs,
        arrives: serviceMidnight.add(Duration(minutes: arr)),
      ));
    }
  }
  results.sort((a, b) => a.departs.compareTo(b.departs));
  return results.take(limit).toList();
}
