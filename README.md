# Tren Belgrano Norte — Horarios

App Flutter (Android primero, iOS compatible) con los horarios oficiales del
tren Belgrano Norte (Ferrovías). Local-first: descarga el PDF oficial una vez,
lo parsea en el dispositivo y después funciona sin conexión.

## Funcionalidades

- **Búsqueda desde/hasta**: próximos trenes entre dos estaciones, con fecha y
  hora opcionales (por defecto "ahora", hora de Argentina). Maneja trenes que
  cruzan la medianoche y servicios cortos (p. ej. trenes que terminan en
  Boulogne). Interruptor "Feriado" para aplicar el cuadro de domingos.
- **Alertas**: notificaciones recurrentes por día de semana y hora que
  muestran los próximos 3 trenes del recorrido elegido. Usa alarmas exactas si
  el usuario lo permite; degrada a inexactas si no.
- **Actualización mensual automática**: al comenzar cada mes (hora argentina)
  se descarga de nuevo el PDF oficial (WorkManager en Android + chequeo al
  abrir la app). Si la descarga o el parseo fallan, se conservan los horarios
  anteriores y se reintenta.

## Arquitectura

```
lib/src/
  data/       pdf_parser.dart        parser posicional del PDF (syncfusion)
              timetable_store.dart   persistencia atómica JSON
              timetable_service.dart fetch + política de actualización mensual
  domain/     models.dart            estaciones canónicas, Trip/Stop/Timetable
              trip_finder.dart       consulta "próximos trenes"
              service_calendar.dart  tipo de día + timezone Argentina
  notifications/                     alertas + programación de notificaciones
  background/ update_worker.dart     tarea periódica WorkManager
  state/      providers.dart         Riverpod
  ui/                                pantallas (Buscar / Alertas / Ajustes)
```

### El parser de PDF

El PDF oficial es texto vectorial (no escaneado). La extracción de texto plano
pierde la alineación de columnas (los servicios cortos dejan celdas vacías),
así que el parser mapea cada hora a su estación por la **coordenada x** de la
palabra: los centros de las celdas de hora forman exactamente 23 clusters de
columna por sentido. En las páginas "hacia Retiro" el orden de columnas está
invertido. Los minutos se normalizan a "minutos desde la medianoche del día de
servicio" y pueden superar 1440 cuando el tren cruza la medianoche.

El parser valida (columnas = 23, tiempos monotónicos, paridad de número de
tren por sentido, cantidad mínima de servicios) y ante cualquier anomalía
lanza `TimetableParseException`: la app nunca reemplaza datos buenos por un
parseo dudoso.

## Desarrollo

```
flutter test      # incluye tests del parser contra test/fixtures/*.pdf
flutter analyze
flutter build apk --release
```

## Limitaciones conocidas / futuro

- Los feriados requieren el toggle manual (no hay calendario de feriados
  embebido). Las alertas en feriados muestran el cuadro del día de semana.
- Sin seguimiento en tiempo real (previsto a futuro).
- iOS: la actualización mensual corre al abrir la app (BGTaskScheduler no
  está configurado; el chequeo on-launch cubre el caso).
