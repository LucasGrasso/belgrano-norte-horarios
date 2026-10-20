import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:timezone/timezone.dart' as tz;

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
  final root = jsonDecode(source);
  if (root is! Map ||
      root['mainEntity'] is! Map ||
      root['mainEntity']['itemListElement'] is! List) {
    throw const FormatException('invalid holiday feed');
  }
  final items = root['mainEntity']['itemListElement'] as List;
  final dates = <String>{};
  for (final e in items) {
    if (e is! Map || e['item'] is! Map) {
      throw const FormatException('invalid holiday item');
    }
    final item = e['item'] as Map;
    final property = item['additionalProperty'];
    final date = item['startDate'];
    if (property is! Map ||
        property['value'] is! String ||
        date is! String ||
        !_validDate(date)) {
      throw const FormatException('invalid holiday date or type');
    }
    final tipo = (property['value'] as String).toLowerCase();
    if (_holidayTypes.contains(tipo)) dates.add(date);
  }
  if (dates.isEmpty) throw const FormatException('no holidays in feed');
  return dates;
}

/// Downloads holiday feeds, keeping each year's last successful fetch time.
/// Legacy year-to-list caches remain readable and are refreshed on first use.
class HolidayService {
  HolidayService(
    this._file, {
    http.Client? client,
    DateTime Function()? now,
    this.requestTimeout = const Duration(seconds: 30),
  }) : _client = client ?? http.Client(),
       _ownsClient = client == null,
       _now = now ?? nowInArgentina;

  static const refreshInterval = Duration(days: 14);
  final File _file;
  final http.Client _client;
  final bool _ownsClient;
  final DateTime Function() _now;
  final Duration requestTimeout;

  static Future<HolidayService> open({
    http.Client? client,
    Duration requestTimeout = const Duration(seconds: 30),
  }) async {
    final dir = await getApplicationSupportDirectory();
    return HolidayService(
      File('${dir.path}${Platform.pathSeparator}holidays.json'),
      client: client,
      requestTimeout: requestTimeout,
    );
  }

  void close() {
    if (_ownsClient) _client.close();
  }

  Future<Map<String, dynamic>> _readYears() async {
    try {
      final raw = jsonDecode(await _file.readAsString());
      if (raw is! Map<String, dynamic>) return {};
      final years = raw['version'] == 2 ? raw['years'] : raw;
      if (years is! Map<String, dynamic>) return {};
      return {
        for (final entry in years.entries)
          if (int.tryParse(entry.key) != null)
            entry.key: entry.value is List
                ? {'dates': entry.value, 'fetchedAt': null}
                : entry.value,
      };
    } on Exception {
      return {};
    }
  }

  HolidayCalendar _calendar(Map<String, dynamic> years) {
    final loaded = <int>{};
    final dates = <String>{};
    for (final entry in years.entries) {
      final value = entry.value;
      if (value is! Map || value['dates'] is! List) continue;
      final entries = value['dates'] as List;
      if (entries.any((d) => d is! String || !_validDate(d))) continue;
      // Yearly feeds can include the following New Year's Day. Coverage and
      // freshness still belong to the requested year, so retain only its dates.
      final yearDates = entries
          .cast<String>()
          .where((d) => d.startsWith('${entry.key}-'))
          .toSet();
      if (yearDates.isEmpty) continue;
      loaded.add(int.parse(entry.key));
      dates.addAll(yearDates);
    }
    return HolidayCalendar(loadedYears: loaded, dates: dates);
  }

  Future<HolidayCalendar> load() async => _calendar(await _readYears());

  /// Refreshes stale/missing years every 14 days, including all service days
  /// used by searches and dated alerts (yesterday through 61 days ahead).
  /// A failure keeps both the last good dates and their timestamp unchanged.
  Future<HolidayCalendar> ensureCurrentYears() async {
    final now = tz.TZDateTime.from(_now(), argentina);
    final firstYear = now.subtract(const Duration(days: 1)).year;
    final lastYear = now
        .add(const Duration(days: kScheduleHorizonDays + 1))
        .year;
    final years = await _readYears();
    final calendar = _calendar(years);
    final due = <int>[];
    for (var year = firstYear; year <= lastYear; year++) {
      final entry = years['$year'];
      final fetchedAt = entry is Map && entry['fetchedAt'] is String
          ? DateTime.tryParse(entry['fetchedAt'] as String)
          : null;
      final age = fetchedAt == null ? null : now.toUtc().difference(fetchedAt);
      if (!calendar.loadedYears.contains(year) ||
          age == null ||
          age.isNegative ||
          age >= refreshInterval) {
        due.add(year);
      }
    }
    // Fetch years in parallel to stay within iOS's background execution budget.
    final updates = await Future.wait<MapEntry<String, Map<String, dynamic>>?>(
      due.map((year) async {
        try {
          final response = await _client
              .get(Uri.parse(holidaysUrl(year)))
              .timeout(requestTimeout);
          if (response.statusCode != 200) return null;
          final dates = parseHolidaysJson(
            utf8.decode(response.bodyBytes),
          ).where((date) => date.startsWith('$year-')).toSet();
          if (dates.isEmpty) return null;
          return MapEntry('$year', {
            'dates': dates.toList()..sort(),
            'fetchedAt': now.toUtc().toIso8601String(),
          });
        } on Exception {
          return null;
        }
      }),
    );
    final valid = updates.nonNulls.toList();
    if (valid.isNotEmpty) {
      // Merge into the latest file so another refreshed year is preserved.
      final latest = await _readYears();
      latest.addEntries(valid);
      await atomicWrite(_file, jsonEncode({'version': 2, 'years': latest}));
      return _calendar(latest);
    }
    return calendar;
  }
}

bool _validDate(String value) {
  if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) return false;
  final date = DateTime.tryParse(value);
  return date != null && HolidayCalendar._key(date) == value;
}
