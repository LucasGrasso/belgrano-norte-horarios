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

/// Finds departures from [from] to [to] at or after [when] (Argentina time).
///
/// Timetable times belong to a *service day* and may run past midnight
/// (stored as minutes > 1440), so both the query date's table and the
/// previous day's table contribute candidates — e.g. at 00:10 on a Tuesday
/// the 23:45 Monday train that reaches Villa Rosa at 01:15 is still relevant.
List<Departure> findNextDepartures(
  Timetable timetable, {
  required int from,
  required int to,
  required tz.TZDateTime when,
  bool holiday = false,
  int limit = 10,
}) {
  if (from == to) return const [];
  final dir = to > from ? Direction.toVillaRosa : Direction.toRetiro;

  final results = <Departure>[];
  for (final dayOffset in [-1, 0, 1]) {
    final serviceMidnight = tz.TZDateTime(
        argentina, when.year, when.month, when.day + dayOffset);
    // The holiday toggle describes the queried date, not its neighbours.
    final isQueriedDate = dayOffset == 0;
    final dayType =
        dayTypeFor(serviceMidnight, holiday: holiday && isQueriedDate);
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
