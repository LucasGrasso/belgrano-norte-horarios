import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/timetable_service.dart';
import '../state/providers.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  bool _updating = false;

  Future<void> _updateNow() async {
    setState(() => _updating = true);
    try {
      await ref.read(timetableProvider.notifier).download();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Horarios actualizados.')));
      }
    } on Exception {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text(
                'No se pudo actualizar. Se conservan los horarios anteriores.')));
      }
    } finally {
      if (mounted) setState(() => _updating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final timetable = ref.watch(timetableProvider).value;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.description_outlined),
                title: Text(timetable == null
                    ? 'Sin horarios descargados'
                    : 'Horario N° ${timetable.scheduleNumber}'),
                subtitle: timetable == null
                    ? null
                    : Text('Vigente desde ${timetable.validFrom}\n'
                        'Descargado: ${_localDate(timetable.fetchedAt)}'),
                isThreeLine: timetable != null,
              ),
              const Divider(height: 1),
              ListTile(
                leading: _updating
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.refresh),
                title: const Text('Actualizar ahora'),
                subtitle: const Text(
                    'Los horarios se actualizan solos al comenzar cada mes'),
                onTap: _updating ? null : _updateNow,
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        const Card(
          child: Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'Acerca de\n\n'
              'Horarios oficiales del tren Belgrano Norte (Ferrovías), '
              'descargados de trenbelgranonorte.com.ar y guardados en el '
              'teléfono: la app funciona sin conexión.\n\n'
              'Los feriados se rigen por el cuadro de domingos: usá el '
              'interruptor "Feriado" en la búsqueda. Las alertas de días '
              'feriados mostrarán el horario del día de semana '
              'correspondiente.',
            ),
          ),
        ),
      ],
    );
  }

  static String _localDate(String iso) {
    final t = DateTime.tryParse(iso)?.toLocal();
    if (t == null) return iso;
    return '${t.day}/${t.month}/${t.year} '
        '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  }
}

/// Shown when no timetable has ever been downloaded (first run).
class FirstRunScreen extends ConsumerWidget {
  const FirstRunScreen({super.key, this.error});

  final Object? error;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.train, size: 72),
            const SizedBox(height: 16),
            Text(
              error == null
                  ? 'Para empezar hay que descargar los horarios oficiales '
                      '(una sola vez, ~100 KB). Después la app funciona sin conexión.'
                  : 'No se pudieron descargar los horarios.\n'
                      'Revisá tu conexión e intentá de nuevo.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () =>
                  ref.read(timetableProvider.notifier).download(),
              icon: const Icon(Icons.download),
              label: Text(error == null ? 'Descargar horarios' : 'Reintentar'),
            ),
            Text('\nFuente: $kTimetablePdfUrl',
                style: Theme.of(context).textTheme.bodySmall,
                textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}
