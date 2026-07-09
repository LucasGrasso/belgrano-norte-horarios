import 'dart:convert';

/// Canonical station order, Retiro -> Villa Rosa. Indices are stable IDs used
/// across the timetable JSON, saved alerts and the UI.
const List<String> kStations = [
  'Retiro',
  'Saldías',
  'Ciudad Universitaria',
  'A. del Valle',
  'M. Padilla',
  'Florida',
  'Munro',
  'Carapachay',
  'V. Adelina',
  'Boulogne',
  'A. Montes',
  'Don Torcuato',
  'A. Sourdeaux',
  'Villa de Mayo',
  'Los Polvorines',
  'Ing. P. Nogués',
  'Grand Bourg',
  'Tierras Altas',
  'Tortuguitas',
  'M. Alberti',
  'Del Viso',
  'C. Grierson',
  'Villa Rosa',
];

enum Direction { toVillaRosa, toRetiro }

enum DayType { weekday, saturday, sundayHoliday }

extension DayTypeJson on DayType {
  String get json => switch (this) {
        DayType.weekday => 'weekday',
        DayType.saturday => 'saturday',
        DayType.sundayHoliday => 'sunday_holiday',
      };

  static DayType parse(String s) => switch (s) {
        'weekday' => DayType.weekday,
        'saturday' => DayType.saturday,
        'sunday_holiday' => DayType.sundayHoliday,
        _ => throw FormatException('unknown day type: $s'),
      };
}

/// One scheduled stop: station index (canonical) and minutes since the
/// service day's midnight. May exceed 1440 when the trip crosses midnight.
class Stop {
  const Stop(this.station, this.minutes);

  final int station;
  final int minutes;

  List<int> toJson() => [station, minutes];

  static Stop fromJson(List<dynamic> j) => Stop(j[0] as int, j[1] as int);
}

class Trip {
  const Trip({required this.number, required this.stops});

  /// Train number as printed in the timetable (odd = to Villa Rosa).
  final int number;

  /// Stops in travel order.
  final List<Stop> stops;

  int? minutesAt(int station) {
    for (final s in stops) {
      if (s.station == station) return s.minutes;
    }
    return null;
  }

  Map<String, dynamic> toJson() =>
      {'number': number, 'stops': [for (final s in stops) s.toJson()]};

  static Trip fromJson(Map<String, dynamic> j) => Trip(
        number: j['number'] as int,
        stops: [for (final s in j['stops'] as List) Stop.fromJson(s as List)],
      );
}

class Timetable {
  const Timetable({
    required this.scheduleNumber,
    required this.validFrom,
    required this.fetchedAt,
    required this.services,
  });

  final int scheduleNumber;

  /// ISO date the operator declared the schedule valid from (yyyy-MM-dd).
  final String validFrom;

  /// When this data was downloaded (ISO-8601, UTC).
  final String fetchedAt;

  final Map<DayType, Map<Direction, List<Trip>>> services;

  List<Trip> tripsFor(DayType day, Direction dir) =>
      services[day]?[dir] ?? const [];

  String encode() => jsonEncode({
        'scheduleNumber': scheduleNumber,
        'validFrom': validFrom,
        'fetchedAt': fetchedAt,
        'stations': kStations,
        'services': {
          for (final e in services.entries)
            e.key.json: {
              for (final d in e.value.entries)
                (d.key == Direction.toVillaRosa ? 'toVillaRosa' : 'toRetiro'):
                    [for (final t in d.value) t.toJson()],
            },
        },
      });

  static Timetable decode(String source) {
    final j = jsonDecode(source) as Map<String, dynamic>;
    final services = <DayType, Map<Direction, List<Trip>>>{};
    (j['services'] as Map<String, dynamic>).forEach((day, dirs) {
      final byDir = <Direction, List<Trip>>{};
      (dirs as Map<String, dynamic>).forEach((dir, trips) {
        byDir[dir == 'toVillaRosa' ? Direction.toVillaRosa : Direction.toRetiro] = [
          for (final t in trips as List) Trip.fromJson(t as Map<String, dynamic>),
        ];
      });
      services[DayTypeJson.parse(day)] = byDir;
    });
    return Timetable(
      scheduleNumber: j['scheduleNumber'] as int,
      validFrom: j['validFrom'] as String,
      fetchedAt: j['fetchedAt'] as String? ?? '',
      services: services,
    );
  }
}
