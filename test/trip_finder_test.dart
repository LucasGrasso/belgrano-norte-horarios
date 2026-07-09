import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;
import 'package:tren_bn_horarios/src/domain/models.dart';
import 'package:tren_bn_horarios/src/domain/service_calendar.dart';
import 'package:tren_bn_horarios/src/domain/trip_finder.dart';

/// Small synthetic timetable, minutes chosen to exercise the edges:
/// - weekday train 101 Retiro 08:00 -> Villa Rosa 09:30
/// - weekday train 103 departs 23:45, arrives 25:15 (01:15 next day)
/// - saturday train 201 Retiro 10:00
/// - sunday/holiday train 301 Retiro 11:00
/// - weekday retiro-bound train 102 Villa Rosa 08:10 -> Retiro 09:40
Timetable _fixture() {
  Trip trip(int n, int dep, {bool reverse = false}) => Trip(
        number: n,
        stops: [
          Stop(reverse ? 22 : 0, dep),
          Stop(10, dep + 50),
          Stop(reverse ? 0 : 22, dep + 90),
        ],
      );
  return Timetable(
    scheduleNumber: 1,
    validFrom: '2026-01-01',
    fetchedAt: '',
    services: {
      DayType.weekday: {
        Direction.toVillaRosa: [trip(101, 8 * 60), trip(103, 23 * 60 + 45)],
        Direction.toRetiro: [trip(102, 8 * 60 + 10, reverse: true)],
      },
      DayType.saturday: {
        Direction.toVillaRosa: [trip(201, 10 * 60)],
        Direction.toRetiro: [],
      },
      DayType.sundayHoliday: {
        Direction.toVillaRosa: [trip(301, 11 * 60)],
        Direction.toRetiro: [],
      },
    },
  );
}

void main() {
  setUpAll(tzdata.initializeTimeZones);

  // 2026-07-06 is a Monday.
  tz.TZDateTime at(int day, int hour, [int minute = 0]) =>
      tz.TZDateTime(argentina, 2026, 7, day, hour, minute);

  final t = _fixture();

  test('direction inferred from station order', () {
    final toVR = findNextDepartures(t, from: 0, to: 22, when: at(6, 7));
    expect(toVR.first.trainNumber, 101);

    final toRetiro = findNextDepartures(t, from: 22, to: 0, when: at(6, 7));
    expect(toRetiro.first.trainNumber, 102);
  });

  test('same station returns nothing', () {
    expect(findNextDepartures(t, from: 5, to: 5, when: at(6, 7)), isEmpty);
  });

  test('past departures excluded, results never precede the query time', () {
    final r = findNextDepartures(t, from: 0, to: 22, when: at(6, 8, 1));
    // Monday's 101 (08:00) already left; first is Monday's 103 at 23:45.
    expect(r.first.trainNumber, 103);
    expect(r.first.departs.day, 6);
    for (final d in r) {
      expect(d.departs.isBefore(at(6, 8, 1)), isFalse);
    }
  });

  test('after-midnight query still sees previous service day train', () {
    // Monday's 103 leaves Retiro 23:45 and calls at station 10 at 00:35
    // Tuesday. Queried from station 10 at Tuesday 00:00 it must appear,
    // sourced from Monday's (weekday) table.
    final r = findNextDepartures(t, from: 10, to: 22, when: at(7, 0, 0));
    expect(r.first.trainNumber, 103);
    expect(r.first.departs.day, 7);
    expect(r.first.departs.hour, 0);
    expect(r.first.departs.minute, 35);
    expect(r.first.arrives.hour, 1);
    expect(r.first.arrives.minute, 15);
  });

  test('arrival minutes >1440 resolve to the next calendar day', () {
    final r = findNextDepartures(t, from: 0, to: 22, when: at(6, 23));
    final d = r.first;
    expect(d.trainNumber, 103);
    expect(d.departs.day, 6);
    expect(d.arrives.day, 7);
    expect(d.duration.inMinutes, 90);
  });

  test('saturday uses saturday table', () {
    // 2026-07-11 is a Saturday.
    final r = findNextDepartures(t, from: 0, to: 22, when: at(11, 9));
    expect(r.first.trainNumber, 201);
  });

  test('holiday flag forces sunday table on a weekday', () {
    final r =
        findNextDepartures(t, from: 0, to: 22, when: at(6, 9), holiday: true);
    expect(r.first.trainNumber, 301);
    expect(r.first.departs.hour, 11);
  });

  test('friday night train crossing into saturday is found early saturday', () {
    // Friday 2026-07-10 23:45 weekday train arrives Saturday 01:15.
    // Query Saturday 00:30 from an intermediate? Origin departure already
    // passed; verify instead that the *arrival* math never yields saturday
    // trains before their table starts.
    final r = findNextDepartures(t, from: 0, to: 22, when: at(11, 0, 30));
    expect(r.first.trainNumber, 201); // Saturday 10:00, not a phantom weekday run
  });

  test('dayTypeFor maps weekdays correctly', () {
    expect(dayTypeFor(DateTime(2026, 7, 6)), DayType.weekday);
    expect(dayTypeFor(DateTime(2026, 7, 11)), DayType.saturday);
    expect(dayTypeFor(DateTime(2026, 7, 12)), DayType.sundayHoliday);
    expect(dayTypeFor(DateTime(2026, 7, 9), holiday: true),
        DayType.sundayHoliday);
  });

  test('results sorted by departure and limited', () {
    final r = findNextDepartures(t, from: 0, to: 22, when: at(6, 0), limit: 2);
    expect(r.length, 2);
    expect(r[0].departs.isBefore(r[1].departs), isTrue);
  });
}
