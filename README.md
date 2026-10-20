<div align="center">

# Tren Belgrano Norte — Horarios

</div>
<p align="center">
  <img src="logo.svg" alt="Description" />
</p>

App Flutter (Android primero, iOS compatible) con los horarios oficiales del
tren Belgrano Norte (Ferrovías). Local-first: descarga el PDF oficial una vez,
lo parsea en el dispositivo y después funciona sin conexión.

## Funcionalidades

- **Búsqueda desde/hasta**: próximos trenes entre dos estaciones, con fecha y
  hora opcionales (por defecto "ahora", hora de Argentina). Maneja trenes que
  cruzan la medianoche y servicios cortos (p. ej. trenes que terminan en
  Boulogne). Los feriados aplican el cuadro de domingos automáticamente.
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

## Cómo correr la app

Requisitos: Flutter (canal stable) y el Android SDK. En Windows, si el
proyecto está en otra unidad que la caché de pub, mover la caché a la misma
unidad (evita un bug de compilación incremental de Kotlin,
flutter/flutter#173456):

```powershell
[Environment]::SetEnvironmentVariable('PUB_CACHE','D:\pub-cache','User')
```

```powershell
flutter pub get

# En un emulador (crearlo una vez con Android Studio o avdmanager):
#   avdmanager create avd -n tren_pixel -k "system-images;android-35;google_apis;x86_64" -d pixel_7
emulator -avd tren_pixel        # o abrirlo desde Android Studio
flutter run                     # compila e instala; 'r' = hot reload, 'R' = restart

# En un teléfono físico: habilitar "Depuración USB", conectarlo y
flutter run

# APK instalable (queda en build\app\outputs\flutter-apk\app-release.apk):
flutter build apk --release
```

La primera pantalla descarga los horarios oficiales (~100 KB); después la
app funciona sin conexión.

## Desarrollo

CI y descargas de APK e IPA sin firmar para instalación con firma propia:
[guía de releases](docs/releases.md). No requiere cuentas de las tiendas.
Análisis del repositorio y próximos cambios recomendados:
[revisión técnica y de UI](docs/repository-review.md).

```
flutter test      # incluye tests del parser contra test/fixtures/*.pdf
flutter analyze
```

## Feriados

La app descarga una vez por año el calendario oficial de feriados
(`https://www.argentina.gob.ar/sites/default/files/holidays-<año>-es.json`)
y lo guarda localmente. Los feriados inamovibles, trasladables y turísticos
aplican el cuadro de domingos automáticamente en la búsqueda y en las
alertas; los días "no laborables" mantienen el horario normal. Si el
calendario del año consultado todavía no se descargó, la búsqueda usa el
cuadro que corresponde al día de la semana.

## Limitaciones conocidas / futuro

- Las alertas semanales calculan su contenido para la próxima ocurrencia
  (incluyendo feriados); las repeticiones siguientes reutilizan ese contenido
  hasta el próximo re-agendado (al abrir la app o actualizar horarios).
- Sin seguimiento en tiempo real (previsto a futuro).
- iOS: la actualización mensual corre al abrir la app (BGTaskScheduler no
  está configurado; el chequeo on-launch cubre el caso).
