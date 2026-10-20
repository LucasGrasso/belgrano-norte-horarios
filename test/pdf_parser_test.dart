import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tren_bn_horarios/src/data/pdf_parser.dart';
import 'package:tren_bn_horarios/src/domain/models.dart';

// Reference values verified independently with a Python/pdfplumber prototype
// and by eye against the rendered PDF (Horario N° 21, May 2026).
void main() {
  late Timetable t;

  setUpAll(() {
    final bytes = File(
      'test/fixtures/horarios-tren-belgrano-norte.pdf',
    ).readAsBytesSync();
    t = parseTimetablePdf(bytes, fetchedAt: DateTime.utc(2026, 7, 9));
  });

  Trip find(DayType day, Direction dir, int number) =>
      t.tripsFor(day, dir).singleWhere((x) => x.number == number);

  test('metadata', () {
    expect(t.scheduleNumber, 21);
    expect(t.validFrom, '2026-05-19');
  });

  test('matches every train and station time from the previous PDF engine', () {
    // Captured before replacing Syncfusion. Checking the complete output also
    // catches shifted/missing cells that aggregate counts cannot detect.
    final expected = jsonDecode(
      File('test/fixtures/horario-21.expected.json').readAsStringSync(),
    );
    expect(jsonDecode(t.encode()), expected);
  });

  test('trip counts per section', () {
    expect(t.tripsFor(DayType.weekday, Direction.toVillaRosa).length, 74);
    expect(t.tripsFor(DayType.weekday, Direction.toRetiro).length, 71);
    expect(t.tripsFor(DayType.saturday, Direction.toVillaRosa).length, 58);
    expect(t.tripsFor(DayType.saturday, Direction.toRetiro).length, 59);
    expect(t.tripsFor(DayType.sundayHoliday, Direction.toVillaRosa).length, 38);
    expect(t.tripsFor(DayType.sundayHoliday, Direction.toRetiro).length, 37);
  });

  test(
    'full-run weekday train 3013: Retiro 04:37 -> Villa Rosa 06:07, 23 stops',
    () {
      final trip = find(DayType.weekday, Direction.toVillaRosa, 3013);
      expect(trip.stops.length, 23);
      expect(trip.stops.first.station, 0);
      expect(trip.stops.first.minutes, 4 * 60 + 37);
      expect(trip.stops.last.station, 22);
      expect(trip.stops.last.minutes, 6 * 60 + 7);
    },
  );

  test('short-turn train 3003 starts at Boulogne (blank leading cells)', () {
    final trip = find(DayType.weekday, Direction.toVillaRosa, 3003);
    expect(trip.stops.first.station, 9); // Boulogne
    expect(trip.stops.first.minutes, 2 * 60 + 45);
    expect(trip.stops.length, 14);
  });

  test('midnight crossing keeps monotonic minutes (train 3143)', () {
    final trip = find(DayType.weekday, Direction.toVillaRosa, 3143);
    expect(trip.minutesAt(16), 24 * 60); // Grand Bourg at 00:00 -> 1440
    expect(trip.stops.last.minutes, 24 * 60 + 25); // Villa Rosa 00:25
  });

  test('retiro-bound short-turn 3002 terminates at Boulogne 01:22', () {
    final trip = find(DayType.weekday, Direction.toRetiro, 3002);
    expect(trip.stops.first.station, 22); // Villa Rosa 00:30
    expect(trip.stops.first.minutes, 30);
    expect(trip.stops.last.station, 9); // Boulogne
    expect(trip.stops.last.minutes, 60 + 22);
  });

  test('sunday retiro-bound 3006 starts at Boulogne 04:00', () {
    final trip = find(DayType.sundayHoliday, Direction.toRetiro, 3006);
    expect(trip.stops.first.station, 9);
    expect(trip.stops.first.minutes, 4 * 60);
  });

  test('saturday 3115 departs 23:45, arrives Villa Rosa 01:15 (+24h)', () {
    final trip = find(DayType.saturday, Direction.toVillaRosa, 3115);
    expect(trip.stops.first.minutes, 23 * 60 + 45);
    expect(trip.stops.last.minutes, 25 * 60 + 15);
  });

  test('all trips: stops strictly increasing, plausible dwell', () {
    for (final day in DayType.values) {
      for (final dir in Direction.values) {
        for (final trip in t.tripsFor(day, dir)) {
          for (var i = 1; i < trip.stops.length; i++) {
            final delta = trip.stops[i].minutes - trip.stops[i - 1].minutes;
            expect(
              delta,
              greaterThan(0),
              reason: 'train ${trip.number} $day $dir stop $i',
            );
            expect(
              delta,
              lessThanOrEqualTo(30),
              reason: 'train ${trip.number} $day $dir stop $i',
            );
          }
        }
      }
    }
  });

  test('round-trips through JSON encode/decode', () {
    final decoded = Timetable.decode(t.encode());
    expect(decoded.scheduleNumber, t.scheduleNumber);
    final a = decoded.tripsFor(DayType.weekday, Direction.toRetiro);
    final b = t.tripsFor(DayType.weekday, Direction.toRetiro);
    expect(a.length, b.length);
    expect(a.first.stops.first.minutes, b.first.stops.first.minutes);
  });

  test('corrupt pdf throws TimetableParseException', () {
    expect(
      () => parseTimetablePdf(
        List<int>.filled(100, 0),
        fetchedAt: DateTime.now(),
      ),
      throwsA(isA<TimetableParseException>()),
    );
  });

  test('empty input throws TimetableParseException', () {
    expect(
      () => parseTimetablePdf([], fetchedAt: DateTime.utc(2026)),
      throwsA(isA<TimetableParseException>()),
    );
  });
}
