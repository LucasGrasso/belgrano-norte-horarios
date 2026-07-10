import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tren_bn_horarios/src/data/holiday_service.dart';

void main() {
  final raw = File('test/fixtures/holidays-2026-es.json').readAsStringSync();

  test('parses official feed, keeping only Sunday-schedule types', () {
    final dates = parseHolidaysJson(raw);
    expect(dates, contains('2026-01-01')); // Año Nuevo (inamovible)
    expect(dates, contains('2026-07-09')); // Independencia (inamovible)
    expect(dates, contains('2026-08-17')); // San Martín (trasladable)
    expect(dates, contains('2026-07-10')); // puente (turistico)
    expect(dates, isNot(contains('2026-04-08'))); // no_laborable excluded
    expect(dates.length, greaterThanOrEqualTo(15));
  });

  test('calendar answers null for unknown years', () {
    final calendar = HolidayCalendar(
      loadedYears: const {2026},
      dates: parseHolidaysJson(raw),
    );
    expect(calendar.isHoliday(DateTime(2026, 7, 9)), isTrue);
    expect(calendar.isHoliday(DateTime(2026, 7, 8)), isFalse);
    expect(calendar.isHoliday(DateTime(2027, 1, 1)), isNull); // year not loaded
  });

  test('rejects malformed feed', () {
    expect(() => parseHolidaysJson('{"mainEntity":{"itemListElement":[]}}'),
        throwsFormatException);
  });
}
