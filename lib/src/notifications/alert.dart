import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// A user-configured recurring alert: at [hour]:[minute] on each weekday in
/// [weekdays] (DateTime.monday..sunday), notify the next trains from
/// [from] to [to].
class Alert {
  const Alert({
    required this.id,
    required this.from,
    required this.to,
    required this.hour,
    required this.minute,
    required this.weekdays,
    this.enabled = true,
  });

  final int id;
  final int from;
  final int to;
  final int hour;
  final int minute;
  final Set<int> weekdays;
  final bool enabled;

  Alert copyWith({
    int? from,
    int? to,
    int? hour,
    int? minute,
    Set<int>? weekdays,
    bool? enabled,
  }) =>
      Alert(
        id: id,
        from: from ?? this.from,
        to: to ?? this.to,
        hour: hour ?? this.hour,
        minute: minute ?? this.minute,
        weekdays: weekdays ?? this.weekdays,
        enabled: enabled ?? this.enabled,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'from': from,
        'to': to,
        'hour': hour,
        'minute': minute,
        'weekdays': weekdays.toList()..sort(),
        'enabled': enabled,
      };

  static Alert fromJson(Map<String, dynamic> j) => Alert(
        id: j['id'] as int,
        from: j['from'] as int,
        to: j['to'] as int,
        hour: j['hour'] as int,
        minute: j['minute'] as int,
        weekdays: {...(j['weekdays'] as List).cast<int>()},
        enabled: j['enabled'] as bool? ?? true,
      );
}

const _prefAlerts = 'alerts.v1';

class AlertStore {
  Future<List<Alert>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefAlerts);
    if (raw == null) return [];
    return [
      for (final j in jsonDecode(raw) as List)
        Alert.fromJson(j as Map<String, dynamic>),
    ];
  }

  Future<void> save(List<Alert> alerts) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _prefAlerts, jsonEncode([for (final a in alerts) a.toJson()]));
  }

  Future<int> nextId() async {
    final alerts = await load();
    return alerts.isEmpty
        ? 1
        : alerts.map((a) => a.id).reduce((a, b) => a > b ? a : b) + 1;
  }
}
