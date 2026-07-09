import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/models.dart';
import '../notifications/alert.dart';
import '../state/providers.dart';

class AlertsScreen extends ConsumerWidget {
  const AlertsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final alerts = ref.watch(alertsProvider).value ?? const <Alert>[];

    return Scaffold(
      body: alerts.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                  'Sin alertas.\n\nCreá una alerta para recibir una notificación '
                  'con los próximos trenes de tu recorrido a la hora que elijas.',
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: alerts.length,
              itemBuilder: (context, i) => _AlertTile(alert: alerts[i]),
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _edit(context, ref, null),
        icon: const Icon(Icons.add_alert),
        label: const Text('Nueva alerta'),
      ),
    );
  }

  static Future<void> _edit(
      BuildContext context, WidgetRef ref, Alert? existing) async {
    // Ask for permission in context, the first time an alert is created.
    final scheduler = await ref.read(notificationSchedulerProvider.future);
    final granted = await scheduler.requestPermissions();
    if (!context.mounted) return;
    if (!granted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text(
              'Sin permiso de notificaciones la alerta no puede avisarte. '
              'Podés habilitarlo en Ajustes del sistema.')));
    }
    final result = await showModalBottomSheet<Alert>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _AlertEditor(existing: existing),
    );
    if (result != null) {
      await ref.read(alertsProvider.notifier).upsert(result);
    }
  }
}

class _AlertTile extends ConsumerWidget {
  const _AlertTile({required this.alert});

  final Alert alert;

  static const _dayLetters = ['L', 'M', 'X', 'J', 'V', 'S', 'D'];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final days = (alert.weekdays.toList()..sort())
        .map((d) => _dayLetters[d - 1])
        .join(' ');
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        onTap: () => AlertsScreen._edit(context, ref, alert),
        title: Text(
            '${kStations[alert.from]} → ${kStations[alert.to]}',
            style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(
            '${alert.hour.toString().padLeft(2, '0')}:${alert.minute.toString().padLeft(2, '0')} · $days'),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Switch(
              value: alert.enabled,
              onChanged: (v) => ref
                  .read(alertsProvider.notifier)
                  .upsert(alert.copyWith(enabled: v)),
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Eliminar',
              onPressed: () =>
                  ref.read(alertsProvider.notifier).remove(alert.id),
            ),
          ],
        ),
      ),
    );
  }
}

class _AlertEditor extends ConsumerStatefulWidget {
  const _AlertEditor({this.existing});

  final Alert? existing;

  @override
  ConsumerState<_AlertEditor> createState() => _AlertEditorState();
}

class _AlertEditorState extends ConsumerState<_AlertEditor> {
  late int _from = widget.existing?.from ?? 0;
  late int _to = widget.existing?.to ?? kStations.length - 1;
  late TimeOfDay _time = widget.existing == null
      ? const TimeOfDay(hour: 8, minute: 0)
      : TimeOfDay(hour: widget.existing!.hour, minute: widget.existing!.minute);
  late Set<int> _days = widget.existing?.weekdays ??
      {DateTime.monday, DateTime.tuesday, DateTime.wednesday, DateTime.thursday, DateTime.friday};

  static const _dayNames = ['Lun', 'Mar', 'Mié', 'Jue', 'Vie', 'Sáb', 'Dom'];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(widget.existing == null ? 'Nueva alerta' : 'Editar alerta',
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 16),
          DropdownButtonFormField<int>(
            initialValue: _from,
            isExpanded: true,
            decoration: const InputDecoration(
                labelText: 'Desde', border: OutlineInputBorder()),
            items: [
              for (var i = 0; i < kStations.length; i++)
                DropdownMenuItem(value: i, child: Text(kStations[i])),
            ],
            onChanged: (v) => setState(() {
              if (v == null) return;
              if (v == _to) _to = _from;
              _from = v;
            }),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<int>(
            initialValue: _to,
            isExpanded: true,
            decoration: const InputDecoration(
                labelText: 'Hasta', border: OutlineInputBorder()),
            items: [
              for (var i = 0; i < kStations.length; i++)
                DropdownMenuItem(value: i, child: Text(kStations[i])),
            ],
            onChanged: (v) => setState(() {
              if (v == null) return;
              if (v == _from) _from = _to;
              _to = v;
            }),
          ),
          const SizedBox(height: 12),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.schedule),
            title: Text('Avisarme a las ${_time.format(context)}'),
            onTap: () async {
              final t = await showTimePicker(context: context, initialTime: _time);
              if (t != null) setState(() => _time = t);
            },
          ),
          Wrap(
            spacing: 6,
            children: [
              for (var d = 1; d <= 7; d++)
                FilterChip(
                  label: Text(_dayNames[d - 1]),
                  selected: _days.contains(d),
                  onSelected: (sel) => setState(() {
                    _days = {..._days};
                    sel ? _days.add(d) : _days.remove(d);
                  }),
                ),
            ],
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _days.isEmpty
                ? null
                : () async {
                    final id = widget.existing?.id ??
                        await ref.read(alertsProvider.notifier).nextId();
                    if (!context.mounted) return;
                    Navigator.pop(
                      context,
                      Alert(
                        id: id,
                        from: _from,
                        to: _to,
                        hour: _time.hour,
                        minute: _time.minute,
                        weekdays: _days,
                        enabled: widget.existing?.enabled ?? true,
                      ),
                    );
                  },
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
  }
}
