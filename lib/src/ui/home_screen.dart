import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/timezone.dart' as tz;

import '../data/holiday_service.dart';
import '../domain/models.dart';
import '../domain/service_calendar.dart';
import '../domain/trip_finder.dart';
import '../state/providers.dart';
import 'brand.dart';

/// Search: desde/hasta + optional date-time (defaults to "now"), results list.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key, this.now = nowInArgentina});

  final tz.TZDateTime Function() now;

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen>
    with WidgetsBindingObserver {
  Timer? _refreshTimer;
  int _from = 0;
  int _to = kStations.length - 1;

  /// Null = "now"; refreshed periodically and immediately on app resume.
  tz.TZDateTime? _customWhen;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startRefreshTimer();
    _restoreLastRoute();
  }

  void _refreshNow() {
    if (mounted && _customWhen == null) setState(() {});
  }

  void _startRefreshTimer() {
    _refreshTimer?.cancel();
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      _refreshNow();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshNow();
      _startRefreshTimer();
    } else {
      _refreshTimer?.cancel();
    }
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
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

  tz.TZDateTime get _when => _customWhen ?? widget.now();

  Future<void> _pickWhen() async {
    final now = widget.now();
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
    // Feriados come from the downloaded official calendar; they apply the
    // Sunday timetable automatically, with no manual control.
    final holidays =
        ref.watch(holidaysProvider).value ?? const HolidayCalendar.empty();

    return SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: _SearchCard(
              from: _from,
              to: _to,
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
                    isHoliday: holidays.isHoliday,
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
    required this.whenLabel,
    required this.onFrom,
    required this.onTo,
    required this.onSwap,
    required this.onWhenTap,
    required this.onWhenClear,
  });

  final int from;
  final int to;
  final String whenLabel;
  final ValueChanged<int> onFrom;
  final ValueChanged<int> onTo;
  final VoidCallback onSwap;
  final VoidCallback onWhenTap;
  final VoidCallback? onWhenClear;

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
    required this.isHoliday,
  });

  final Timetable timetable;
  final int from;
  final int to;
  final tz.TZDateTime when;
  final HolidayResolver isHoliday;

  @override
  Widget build(BuildContext context) {
    final departures = findNextDepartures(
      timetable,
      from: from,
      to: to,
      when: when,
      isHoliday: isHoliday,
      limit: 12,
    );
    if (departures.isEmpty) {
      return const Center(child: Text('Sin servicios para esta búsqueda.'));
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: departures.length,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (context, i) => _DepartureCard(
        departure: departures[i],
        from: from,
        to: to,
        wait: departures[i].departs.difference(when),
      ),
    );
  }
}

/// Card styled after the hand-drawn mockup (ui-idea.png): tinted header
/// strip with the train number, big Sale/Llega times, station names below,
/// and a dotted arrow labelled with the trip duration in between.
class _DepartureCard extends StatelessWidget {
  const _DepartureCard({
    required this.departure,
    required this.from,
    required this.to,
    required this.wait,
  });

  final Departure departure;
  final int from;
  final int to;
  final Duration wait;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final timeStyle = theme.textTheme.displaySmall!.copyWith(
      fontWeight: FontWeight.w700,
      fontFeatures: const [FontFeature.tabularFigures()],
      color: theme.colorScheme.onSurface,
    );
    final labelStyle = theme.textTheme.titleMedium!;
    final stationStyle = theme.textTheme.bodySmall!;

    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            color: kBrandColor,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Text(
                  'Tren ${departure.trainNumber}',
                  style: theme.textTheme.titleSmall!.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                Text(
                  _waitLabel(wait),
                  style: theme.textTheme.labelMedium!
                      .copyWith(color: Colors.white),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Sale', style: labelStyle),
                    Text('Llega', style: labelStyle),
                  ],
                ),
                // Big times with the dashed connector vertically centered on
                // the same row, as in the reference design.
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text(_hhmm(departure.departs), style: timeStyle),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        child: SizedBox(
                          height: 20,
                          child: CustomPaint(
                            size: const Size(double.infinity, 20),
                            painter: _DashedConnectorPainter(
                                color: theme.colorScheme.outline),
                          ),
                        ),
                      ),
                    ),
                    Text(_hhmm(departure.arrives), style: timeStyle),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text('Estación ${kStations[from]}',
                          style: stationStyle),
                    ),
                    Text('${departure.duration.inMinutes} min',
                        style: theme.textTheme.labelSmall),
                    Expanded(
                      child: Text('Estación ${kStations[to]}',
                          style: stationStyle, textAlign: TextAlign.right),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
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

/// Dashed line with a small circled chevron in the middle, imitating the
/// trip connector of the reference design.
class _DashedConnectorPainter extends CustomPainter {
  const _DashedConnectorPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round;
    final y = size.height / 2;
    final cx = size.width / 2;
    const r = 7.0; // circled-chevron radius
    const dash = 4.0;
    const gap = 4.0;

    void dashes(double from, double to) {
      for (var x = from; x < to; x += dash + gap) {
        canvas.drawLine(
            Offset(x, y), Offset((x + dash).clamp(from, to), y), stroke);
      }
    }

    dashes(0, cx - r - 3);
    dashes(cx + r + 3, size.width);

    canvas.drawCircle(Offset(cx, y), r, stroke);
    final chevron = Path()
      ..moveTo(cx - 1.5, y - 3)
      ..lineTo(cx + 2.0, y)
      ..lineTo(cx - 1.5, y + 3);
    canvas.drawPath(chevron, stroke..strokeJoin = StrokeJoin.round);
  }

  @override
  bool shouldRepaint(_DashedConnectorPainter oldDelegate) =>
      color != oldDelegate.color;
}
