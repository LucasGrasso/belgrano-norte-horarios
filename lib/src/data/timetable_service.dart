import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/models.dart';
import '../domain/service_calendar.dart';
import 'pdf_parser.dart';
import 'timetable_store.dart';

const kTimetablePdfUrl =
    'https://www.trenbelgranonorte.com.ar/img/horarios-tren-belgrano-norte.pdf';

const _prefLastFetchMonth = 'timetable.lastFetchMonth';

/// Fetch + parse + persist. Any failure leaves the stored timetable intact.
class TimetableService {
  TimetableService(
    this._store, {
    http.Client? client,
    this.requestTimeout = const Duration(seconds: 60),
  }) : _client = client ?? http.Client(),
       _ownsClient = client == null;

  final TimetableStore _store;
  final http.Client _client;
  final bool _ownsClient;
  final Duration requestTimeout;

  void close() {
    if (_ownsClient) _client.close();
  }

  Future<Timetable?> loadStored() => _store.load();

  /// Downloads the PDF, parses it and stores the result. Throws on network
  /// or parse failure; the caller decides how to surface it.
  Future<Timetable> fetchAndStore() async {
    final response = await _client
        .get(Uri.parse(kTimetablePdfUrl))
        .timeout(requestTimeout);
    if (response.statusCode != 200) {
      throw Exception('HTTP ${response.statusCode} downloading timetable');
    }
    final timetable = parseTimetablePdf(
      response.bodyBytes,
      fetchedAt: DateTime.now(),
    );
    await _store.save(timetable);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefLastFetchMonth, currentArgentinaMonth());
    return timetable;
  }

  /// "yyyy-MM" of the current month in Argentina.
  static String currentArgentinaMonth() {
    final now = nowInArgentina();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}';
  }

  /// True when we have never fetched in the current Argentina month.
  static Future<bool> isMonthlyUpdateDue() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    return prefs.getString(_prefLastFetchMonth) != currentArgentinaMonth();
  }

  /// Refetches if a new Argentina month has started. Returns the fresh
  /// timetable, or null when not due or when the update failed (stored data
  /// stays in place; the check stays "due" and is retried on the next call).
  Future<Timetable?> updateIfNewMonth() async {
    if (!await isMonthlyUpdateDue()) return null;
    try {
      return await fetchAndStore();
    } on Exception {
      return null;
    }
  }
}
