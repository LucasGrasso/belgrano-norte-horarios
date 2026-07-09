import 'package:syncfusion_flutter_pdf/pdf.dart';

import '../domain/models.dart';

/// Thrown when the PDF does not match the expected layout. Callers must keep
/// the previously stored timetable when this happens.
class TimetableParseException implements Exception {
  TimetableParseException(this.message, [this.problems = const []]);

  final String message;
  final List<String> problems;

  @override
  String toString() =>
      'TimetableParseException: $message\n${problems.take(20).join('\n')}';
}

const _monthNames = {
  'ENERO': 1, 'FEBRERO': 2, 'MARZO': 3, 'ABRIL': 4, 'MAYO': 5, 'JUNIO': 6,
  'JULIO': 7, 'AGOSTO': 8, 'SEPTIEMBRE': 9, 'OCTUBRE': 10, 'NOVIEMBRE': 11,
  'DICIEMBRE': 12,
};

final _timeRe = RegExp(r'^\d{2}:\d{2}$');
final _trainRe = RegExp(r'^\d{4}$');

class _Word {
  _Word(this.text, this.x0, this.x1, this.y0, this.y1);

  final String text;
  final double x0, x1, y0, y1;

  double get xc => (x0 + x1) / 2;
  double get yc => (y0 + y1) / 2;
}

/// Parses the official "horarios-tren-belgrano-norte.pdf" into a [Timetable].
///
/// The tables are laid out on a fixed 23-station column grid; plain text
/// extraction loses which column a time belongs to (short-turn trains leave
/// blank cells), so times are mapped to stations by word x-coordinates:
/// the x-centers of all time cells of a direction cluster into exactly 23
/// columns. On "hacia Retiro" pages the column order is reversed.
Timetable parseTimetablePdf(List<int> bytes, {required DateTime fetchedAt}) {
  final doc = PdfDocument(inputBytes: bytes);
  try {
    final extractor = PdfTextExtractor(doc);
    final problems = <String>[];

    int? scheduleNumber;
    String? validFrom;

    // Per page: classification + words.
    final pages = <({DayType day, Direction dir, List<_Word> words})>[];
    final colXs = <Direction, List<double>>{
      Direction.toVillaRosa: [],
      Direction.toRetiro: [],
    };

    for (var p = 0; p < doc.pages.count; p++) {
      final lines = extractor.extractTextLines(startPageIndex: p, endPageIndex: p);
      final words = <_Word>[];
      for (final line in lines) {
        for (final w in line.wordCollection) {
          final t = w.text.trim();
          if (t.isEmpty) continue;
          words.add(_Word(t, w.bounds.left, w.bounds.right, w.bounds.top,
              w.bounds.bottom));
        }
      }
      final pageText = words.map((w) => w.text).join(' ').toUpperCase();

      scheduleNumber ??= _parseScheduleNumber(pageText);
      validFrom ??= _parseValidFrom(pageText);

      final day = pageText.contains('LUNES A VIERNES')
          ? DayType.weekday
          : pageText.contains('BADOS') // SÁBADOS with any accent handling
              ? DayType.saturday
              : pageText.contains('DOMINGOS')
                  ? DayType.sundayHoliday
                  : null;
      final dir = pageText.contains('HACIA VILLA ROSA')
          ? Direction.toVillaRosa
          : pageText.contains('HACIA RETIRO')
              ? Direction.toRetiro
              : null;
      if (day == null || dir == null) {
        problems.add('page ${p + 1}: unclassifiable (day=$day dir=$dir)');
        continue;
      }
      pages.add((day: day, dir: dir, words: words));
      for (final w in words) {
        if (_timeRe.hasMatch(w.text)) colXs[dir]!.add(w.xc);
      }
    }

    if (scheduleNumber == null || validFrom == null) {
      throw TimetableParseException(
          'header not found (scheduleNumber=$scheduleNumber validFrom=$validFrom)');
    }

    // Column grid per direction, from all pages of that direction.
    final centers = <Direction, List<double>>{};
    for (final e in colXs.entries) {
      final c = _clusterCenters(e.value);
      if (c.length != kStations.length) {
        throw TimetableParseException(
            '${e.key}: found ${c.length} columns, expected ${kStations.length}');
      }
      centers[e.key] = c;
    }

    final services = {
      for (final d in DayType.values)
        d: {for (final dir in Direction.values) dir: <Trip>[]},
    };

    for (final page in pages) {
      final cols = centers[page.dir]!;
      final timeWords =
          page.words.where((w) => _timeRe.hasMatch(w.text)).toList();
      final trainWords = page.words
          .where((w) => _trainRe.hasMatch(w.text) && w.x1 < cols.first - 10)
          .toList();

      for (final tw in trainWords) {
        final rowHalfHeight = (tw.y1 - tw.y0) * 0.6;
        final cells = <(int col, String time)>[];
        for (final w in timeWords) {
          if ((w.yc - tw.yc).abs() >= rowHalfHeight) continue;
          var best = 0;
          for (var i = 1; i < cols.length; i++) {
            if ((cols[i] - w.xc).abs() < (cols[best] - w.xc).abs()) best = i;
          }
          if ((cols[best] - w.xc).abs() > 12) {
            problems.add('train ${tw.text}: time ${w.text} off-grid');
          }
          cells.add((best, w.text));
        }
        if (cells.isEmpty) continue;
        cells.sort((a, b) => a.$1.compareTo(b.$1));
        if (cells.map((c) => c.$1).toSet().length != cells.length) {
          problems.add('train ${tw.text}: two times in one column');
          continue;
        }

        final stops = <Stop>[];
        int? prev;
        for (final (col, time) in cells) {
          final station = page.dir == Direction.toVillaRosa
              ? col
              : kStations.length - 1 - col;
          var mins = int.parse(time.substring(0, 2)) * 60 +
              int.parse(time.substring(3));
          if (prev != null && mins < prev) mins += 24 * 60; // crossed midnight
          if (prev != null && (mins - prev <= 0 || mins - prev > 30)) {
            problems.add(
                'train ${tw.text}: implausible step ${prev}m -> ${mins}m at ${kStations[station]}');
          }
          prev = mins;
          stops.add(Stop(station, mins));
        }

        final number = int.parse(tw.text);
        final expectedOdd = page.dir == Direction.toVillaRosa;
        if (number.isOdd != expectedOdd) {
          problems.add('train $number: parity does not match ${page.dir}');
        }
        services[page.day]![page.dir]!.add(Trip(number: number, stops: stops));
      }
    }

    if (problems.isNotEmpty) {
      throw TimetableParseException(
          '${problems.length} problems while parsing', problems);
    }

    for (final byDir in services.values) {
      for (final trips in byDir.values) {
        trips.sort((a, b) => a.stops.first.minutes - b.stops.first.minutes);
      }
      if (byDir.values.any((t) => t.length < 10)) {
        throw TimetableParseException('suspiciously few trips parsed');
      }
    }

    return Timetable(
      scheduleNumber: scheduleNumber,
      validFrom: validFrom,
      fetchedAt: fetchedAt.toUtc().toIso8601String(),
      services: services,
    );
  } finally {
    doc.dispose();
  }
}

int? _parseScheduleNumber(String text) {
  final m = RegExp(r'HORARIO N.?\s*(\d+)').firstMatch(text);
  return m == null ? null : int.parse(m.group(1)!);
}

String? _parseValidFrom(String text) {
  final m = RegExp(r'VIGENTE DESDE EL (\d{1,2}) DE (\w+) DE (\d{4})')
      .firstMatch(text);
  if (m == null) return null;
  final month = _monthNames[m.group(2)!];
  if (month == null) return null;
  final d = int.parse(m.group(1)!).toString().padLeft(2, '0');
  return '${m.group(3)}-${month.toString().padLeft(2, '0')}-$d';
}

/// Groups sorted x-centers into clusters, splitting where neighbours are more
/// than [gap] points apart; returns each cluster's mean.
List<double> _clusterCenters(List<double> xs, {double gap = 15}) {
  if (xs.isEmpty) return const [];
  final sorted = [...xs]..sort();
  final centers = <double>[];
  var sum = sorted.first;
  var count = 1;
  var last = sorted.first;
  for (final x in sorted.skip(1)) {
    if (x - last > gap) {
      centers.add(sum / count);
      sum = 0;
      count = 0;
    }
    sum += x;
    count++;
    last = x;
  }
  centers.add(sum / count);
  return centers;
}
