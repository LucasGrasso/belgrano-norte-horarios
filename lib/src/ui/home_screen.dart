import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/timezone.dart' as tz;

import '../domain/models.dart';
import '../domain/service_calendar.dart';
import '../domain/trip_finder.dart';
import '../state/providers.dart';

/// Search: desde/hasta + optional date-time (defaults to "now"), results list.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  int _from = 0;
  int _to = kStations.length - 1;
  bool _holiday = false;

  /// Null = "now" (recomputed on every build so results stay fresh).
  tz.TZDateTime? _customWhen;

  @override
  void initState() {
    super.initState();
    _restoreLastRoute();
  }

  Future<void> _restoreLastRoute() async {
    final prefs = await SharedPreferences.getInstance();
    final from = prefs.getInt('route.from');
    final to = prefs.getInt('route.to');
    if (from != null && to != null && from != to && mounted) {
      setState(() {
        _from = from;
        _to = to;
      });
    }
  }

  Future<void> _saveLastRoute() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('route.from', _from);
    await prefs.setInt('route.to', _to);
  }

  tz.TZDateTime get _when => _customWhen ?? nowInArgentina();

  Future<void> _pickWhen() async {
    final now = nowInArgentina();
    final date = await showDatePicker(
      context: context,
      initialDate: _when,
      firstDate: now.subtract(const Duration(days: 1)),
      lastDate: now.add(const Duration(days: 60)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: _when.hour, minute: _when.minute),
    );
    if (time == null) return;
    setState(() {
      _customWhen = tz.TZDateTime(
          argentina, date.year, date.month, date.day, time.hour, time.minute);
    });
  }

  @override
  Widget build(BuildContext context) {
    final timetable = ref.watch(timetableProvider).value;

    return SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: _SearchCard(
              from: _from,
              to: _to,
              holiday: _holiday,
              whenLabel: _customWhen == null
                  ? 'Ahora'
                  : _formatWhen(_customWhen!),
              onFrom: (v) => setState(() {
                if (v == _to) _to = _from; // swap instead of invalid state
                _from = v;
                _saveLastRoute();
              }),
              onTo: (v) => setState(() {
                if (v == _from) _from = _to;
                _to = v;
                _saveLastRoute();
              }),
              onSwap: () => setState(() {
                final t = _from;
                _from = _to;
                _to = t;
                _saveLastRoute();
              }),
              onWhenTap: _pickWhen,
              onWhenClear:
                  _customWhen == null ? null : () => setState(() => _customWhen = null),
              onHoliday: (v) => setState(() => _holiday = v),
            ),
          ),
          Expanded(
            child: timetable == null
                ? const SizedBox.shrink()
                : _ResultsList(
                    timetable: timetable,
                    from: _from,
                    to: _to,
                    when: _when,
                    holiday: _holiday,
                  ),
          ),
        ],
      ),
    );
  }

  static String _formatWhen(tz.TZDateTime t) {
    const days = ['lun', 'mar', 'mié', 'jue', 'vie', 'sáb', 'dom'];
    return '${days[t.weekday - 1]} ${t.day}/${t.month} '
        '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  }
}

class _SearchCard extends StatelessWidget {
  const _SearchCard({
    required this.from,
    required this.to,
    required this.holiday,
    required this.whenLabel,
    required this.onFrom,
    required this.onTo,
    required this.onSwap,
    required this.onWhenTap,
    required this.onWhenClear,
    required this.onHoliday,
  });

  final int from;
  final int to;
  final bool holiday;
  final String whenLabel;
  final ValueChanged<int> onFrom;
  final ValueChanged<int> onTo;
  final VoidCallback onSwap;
  final VoidCallback onWhenTap;
  final VoidCallback? onWhenClear;
  final ValueChanged<bool> onHoliday;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    children: [
                      _StationDropdown(
                          label: 'Desde', value: from, onChanged: onFrom),
                      const SizedBox(height: 8),
                      _StationDropdown(
                          label: 'Hasta', value: to, onChanged: onTo),
                    ],
                  ),
                ),
                IconButton.filledTonal(
                  onPressed: onSwap,
                  icon: const Icon(Icons.swap_vert),
                  tooltip: 'Invertir sentido',
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                ActionChip(
                  avatar: const Icon(Icons.schedule, size: 18),
                  label: Text(whenLabel),
                  onPressed: onWhenTap,
                ),
                if (onWhenClear != null)
                  IconButton(
                    onPressed: onWhenClear,
                    icon: const Icon(Icons.close, size: 18),
                    tooltip: 'Volver a "ahora"',
                    visualDensity: VisualDensity.compact,
                  ),
                const Spacer(),
                FilterChip(
                  label: const Text('Feriado'),
                  tooltip: 'Los feriados rigen los horarios de domingo',
                  selected: holiday,
                  onSelected: onHoliday,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _StationDropdown extends StatelessWidget {
  const _StationDropdown(
      {required this.label, required this.value, required this.onChanged});

  final String label;
  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<int>(
      initialValue: value,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
      items: [
        for (var i = 0; i < kStations.length; i++)
          DropdownMenuItem(value: i, child: Text(kStations[i])),
      ],
      onChanged: (v) {
        if (v != null) onChanged(v);
      },
    );
  }
}

class _ResultsList extends StatelessWidget {
  const _ResultsList({
    required this.timetable,
    required this.from,
    required this.to,
    required this.when,
    required this.holiday,
  });

  final Timetable timetable;
  final int from;
  final int to;
  final tz.TZDateTime when;
  final bool holiday;

  @override
  Widget build(BuildContext context) {
    final departures = findNextDepartures(
      timetable,
      from: from,
      to: to,
      when: when,
      holiday: holiday,
      limit: 12,
    );
    if (departures.isEmpty) {
      return const Center(child: Text('Sin servicios para esta búsqueda.'));
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: departures.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, i) {
        final d = departures[i];
        final wait = d.departs.difference(when);
        return Card(
          margin: EdgeInsets.zero,
          child: ListTile(
            leading: CircleAvatar(
              child: Text(_hhmm(d.departs).substring(0, 2),
                  style: const TextStyle(fontSize: 14)),
            ),
            title: Text(
              'Sale ${_hhmm(d.departs)} — llega ${_hhmm(d.arrives)}',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            subtitle: Text(
                'Tren ${d.trainNumber} · ${d.duration.inMinutes} min de viaje'),
            trailing: Text(
              _waitLabel(wait),
              style: Theme.of(context).textTheme.labelLarge,
            ),
          ),
        );
      },
    );
  }

  static String _hhmm(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  static String _waitLabel(Duration wait) {
    if (wait.inMinutes < 60) return 'en ${wait.inMinutes} min';
    final h = wait.inHours;
    final m = wait.inMinutes % 60;
    return m == 0 ? 'en ${h}h' : 'en ${h}h ${m}m';
  }
}
