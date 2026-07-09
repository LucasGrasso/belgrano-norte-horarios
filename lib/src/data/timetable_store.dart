import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../domain/models.dart';

/// Persists the parsed timetable as JSON in the app's support directory.
/// Writes are atomic (temp file + rename) so a crash mid-write can never
/// leave the app without a readable timetable.
class TimetableStore {
  TimetableStore._(this._file);

  final File _file;

  static Future<TimetableStore> open() async {
    final dir = await getApplicationSupportDirectory();
    return TimetableStore._(File('${dir.path}${Platform.pathSeparator}timetable.json'));
  }

  Future<Timetable?> load() async {
    try {
      if (!await _file.exists()) return null;
      return Timetable.decode(await _file.readAsString());
    } on Exception {
      // Corrupt/incompatible data: treat as absent, a fresh fetch replaces it.
      return null;
    }
  }

  Future<void> save(Timetable timetable) async {
    final tmp = File('${_file.path}.tmp');
    await tmp.writeAsString(timetable.encode(), flush: true);
    if (await _file.exists()) await _file.delete();
    await tmp.rename(_file.path);
  }
}
