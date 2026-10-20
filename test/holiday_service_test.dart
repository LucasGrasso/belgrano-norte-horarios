import 'dart:io';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;

import 'package:flutter_test/flutter_test.dart';
import 'package:tren_bn_horarios/src/data/holiday_service.dart';

http.Response _response(String body, int status) => http.Response.bytes(
  utf8.encode(body),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

void main() {
  setUpAll(tzdata.initializeTimeZones);
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
    expect(
      () => parseHolidaysJson('{"mainEntity":{"itemListElement":[]}}'),
      throwsFormatException,
    );
  });

  group('holiday cache refresh', () {
    late Directory dir;
    late File file;
    late DateTime now;
    setUp(() async {
      dir = await Directory.systemTemp.createTemp('bn-holidays-');
      file = File('${dir.path}/holidays.json');
      now = DateTime.utc(2026, 7, 1, 12);
    });
    tearDown(() async => dir.delete(recursive: true));

    test(
      'refreshes exactly every 14 days and replaces removed holidays',
      () async {
        var calls = 0;
        final client = MockClient((_) async {
          calls++;
          return _response(
            calls == 1 ? raw : raw.replaceAll('2026-07-10', '2026-07-11'),
            200,
          );
        });
        final service = HolidayService(file, client: client, now: () => now);
        expect(
          (await service.ensureCurrentYears()).dates,
          contains('2026-07-10'),
        );
        now = now
            .add(const Duration(days: 14))
            .subtract(const Duration(seconds: 1));
        await service.ensureCurrentYears();
        expect(calls, 1);
        now = now.add(const Duration(seconds: 1));
        final changed = await service.ensureCurrentYears();
        expect(calls, 2);
        expect(changed.dates, isNot(contains('2026-07-10')));
        expect(changed.dates, contains('2026-07-11'));
        // The successful-fetch timestamp survives a new service instance.
        await HolidayService(
          file,
          client: client,
          now: () => now,
        ).ensureCurrentYears();
        expect(calls, 2);
      },
    );

    test('migrates legacy caches and preserves other years', () async {
      await file.writeAsString(
        jsonEncode({
          '2025': ['2025-01-01'],
          '2026': ['2026-01-01'],
        }),
      );
      final service = HolidayService(
        file,
        client: MockClient((_) async => _response(raw, 200)),
        now: () => now,
      );
      expect((await service.load()).loadedYears, {2025, 2026});
      final calendar = await service.ensureCurrentYears();
      expect(calendar.loadedYears, {2025, 2026});
      final stored = jsonDecode(await file.readAsString()) as Map;
      expect(stored['version'], 2);
      expect(stored['years']['2025']['dates'], ['2025-01-01']);
      expect(stored['years']['2026']['fetchedAt'], isNotNull);
    });

    test(
      'failed and malformed refreshes preserve dates and retry while stale',
      () async {
        var calls = 0;
        final responses = [raw, 'offline', '{}', '[]', raw];
        final client = MockClient((_) async {
          final index = calls++;
          return _response(responses[index], index == 1 ? 503 : 200);
        });
        final service = HolidayService(file, client: client, now: () => now);
        await service.ensureCurrentYears();
        final before = await file.readAsString();
        now = now.add(const Duration(days: 14));
        for (var i = 0; i < 3; i++) {
          expect(
            (await service.ensureCurrentYears()).isHoliday(
              DateTime(2026, 7, 9),
            ),
            isTrue,
          );
          expect(await file.readAsString(), before);
        }
        await service.ensureCurrentYears();
        expect(calls, 5);
        expect(await file.readAsString(), isNot(before));
      },
    );

    test('November prefetch covers January searches and alerts', () async {
      now = DateTime.utc(2026, 11, 15, 12);
      final requested = <int>[];
      final service = HolidayService(
        file,
        now: () => now,
        client: MockClient((request) async {
          final year = request.url.path.contains('2027') ? 2027 : 2026;
          requested.add(year);
          return _response(raw.replaceAll('2026-', '$year-'), 200);
        }),
      );
      final calendar = await service.ensureCurrentYears();
      expect(requested, unorderedEquals([2026, 2027]));
      expect(calendar.isHoliday(DateTime(2027, 1, 1)), isTrue);
    });

    test(
      'missing future year retries without re-fetching fresh current year',
      () async {
        now = DateTime.utc(2026, 11, 15, 12);
        final calls = <String>[];
        var futureAvailable = false;
        final service = HolidayService(
          file,
          now: () => now,
          client: MockClient((request) async {
            calls.add(request.url.path);
            if (request.url.path.contains('2027')) {
              return _response(
                raw.replaceAll('2026-', '2027-'),
                futureAvailable ? 200 : 404,
              );
            }
            return _response(raw, 200);
          }),
        );
        expect((await service.ensureCurrentYears()).loadedYears, {2026});
        futureAvailable = true;
        expect((await service.ensureCurrentYears()).loadedYears, {2026, 2027});
        expect(calls.where((p) => p.contains('2026')), hasLength(1));
        expect(calls.where((p) => p.contains('2027')), hasLength(2));
      },
    );

    test('bad dates, wrong feed year and corrupt cache can recover', () async {
      for (final invalid in ['2026-02-30', 'bad-date']) {
        expect(
          () => parseHolidaysJson(raw.replaceAll('2026-07-09', invalid)),
          throwsFormatException,
        );
      }
      await file.writeAsString('[]');
      var good = false;
      final service = HolidayService(
        file,
        now: () => now,
        client: MockClient(
          (_) async =>
              _response(good ? raw : raw.replaceAll('2026-', '2027-'), 200),
        ),
      );
      expect((await service.ensureCurrentYears()).loadedYears, isEmpty);
      good = true;
      expect((await service.ensureCurrentYears()).loadedYears, {2026});
    });

    test('clock moving backwards makes the cached year due again', () async {
      var calls = 0;
      final service = HolidayService(
        file,
        now: () => now,
        client: MockClient((_) async {
          calls++;
          return _response(raw, 200);
        }),
      );
      await service.ensureCurrentYears();
      now = now.subtract(const Duration(days: 1));
      await service.ensureCurrentYears();
      expect(calls, 2);
    });
  });
}
