import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../domain/service_calendar.dart';
import 'atomic_file.dart';

/// Official national-holiday feed, one file per year (argentina.gob.ar).
String holidaysUrl(int year) =>
    'https://www.argentina.gob.ar/sites/default/files/holidays-$year-es.json';

/// Which entry types run the Sunday train schedule. "no_laborable" days are
/// optional non-working days: trains keep their normal timetable.
const _holidayTypes = {'inamovible', 'trasladable', 'turistico'};

/// Immutable set of known feriados plus which source years were fetched.
class HolidayCalendar {
  const HolidayCalendar({required this.loadedYears, required this.dates});

  const HolidayCalendar.empty() : this(loadedYears: const {}, dates: const {});

  final Set<int> loadedYears;

  /// Feriado dates as 'yyyy-MM-dd'.
  final Set<String> dates;

  /// True/false when [day]'s year was fetched; null when unknown (feed for
  /// that year never downloaded), letting the UI fall back to a manual toggle.
  bool? isHoliday(DateTime day) {
    if (!loadedYears.contains(day.year)) return null;
    return dates.contains(_key(day));
  }

  static String _key(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

/// Parses the schema.org ItemList payload of the official feed into feriado
/// date keys. Throws [FormatException] on unexpected shape.
Set<String> parseHolidaysJson(String source) {
  final root = jsonDecode(source) as Map<String, dynamic>;
  final items =
      (root['mainEntity'] as Map<String, dynamic>)['itemListElement'] as List;
  final dates = <String>{};
  for (final e in items) {
    final item = (e as Map<String, dynamic>)['item'] as Map<String, dynamic>;
    final tipo = ((item['additionalProperty']
            as Map<String, dynamic>)['value'] as String)
        .toLowerCase();
    final date = item['startDate'] as String;
    if (_holidayTypes.contains(tipo)) dates.add(date);
  }
  if (dates.isEmpty) throw const FormatException('no holidays in feed');
  return dates;
}

/// Downloads and persists the yearly feriado feeds. Stored shape:
/// `{"2026": ["2026-01-01", ...]}` in the app support directory.
class HolidayService {
  HolidayService(this._file, {http.Client? client})
      : _client = client ?? http.Client();

  final File _file;
  final http.Client _client;

  static Future<HolidayService> open({http.Client? client}) async {
    final dir = await getApplicationSupportDirectory();
    return HolidayService(
        File('${dir.path}${Platform.pathSeparator}holidays.json'),
        client: client);
  }

  Future<HolidayCalendar> load() async {
    try {
      if (!await _file.exists()) return const HolidayCalendar.empty();
      final raw = jsonDecode(await _file.readAsString()) as Map<String, dynamic>;
      return HolidayCalendar(
        loadedYears: raw.keys.map(int.parse).toSet(),
        dates: {
          for (final v in raw.values) ...(v as List).cast<String>(),
        },
      );
    } on Exception {
      return const HolidayCalendar.empty();
    }
  }

  /// Fetches the current Argentina year (and the next one from December,
  /// so New Year queries keep working) unless already stored. Network or
  /// format failures leave the stored data untouched; the year stays
  /// missing and is retried on the next call.
  Future<HolidayCalendar> ensureCurrentYears() async {
    final now = nowInArgentina();
    final wanted = {now.year, if (now.month == 12) now.year + 1};
    var calendar = await load();
    for (final year in wanted.difference(calendar.loadedYears)) {
      try {
        final response = await _client
            .get(Uri.parse(holidaysUrl(year)))
            .timeout(const Duration(seconds: 30));
        if (response.statusCode != 200) continue;
        final dates = parseHolidaysJson(utf8.decode(response.bodyBytes));
        await _save(year, dates);
        calendar = await load();
      } on Exception {
        // keep going; retried on next launch/periodic check
      }
    }
    return calendar;
  }

  Future<void> _save(int year, Set<String> dates) async {
    Map<String, dynamic> raw = {};
    if (await _file.exists()) {
      try {
        raw = jsonDecode(await _file.readAsString()) as Map<String, dynamic>;
      } on Exception {
        raw = {};
      }
    }
    raw['$year'] = dates.toList()..sort();
    await atomicWrite(_file, jsonEncode(raw));
  }
}

