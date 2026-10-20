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
  muestran los próximos 3 trenes del recorrido elegido, calculados para cada
  fecha con su calendario de feriados. Usa alarmas exactas si
  el usuario lo permite; degrada a inexactas si no.
- **Actualización mensual automática**: al comenzar cada mes (hora argentina)
  se descarga de nuevo el PDF oficial (WorkManager en Android y BGTaskScheduler
  en iOS, más chequeo al abrir o retomar la app). Si la descarga o el parseo
  fallan, se conservan los horarios anteriores y se reintenta.

## Arquitectura

```
lib/src/
  data/       pdf_parser.dart        parser posicional del PDF (pdf_graphics)
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

La lectura del PDF usa `pdf_document` y `pdf_graphics`, bibliotecas de Dart
con licencia Apache-2.0. No requiere cuenta ni licencia de Syncfusion, ni
agrega librerías nativas a Android/iOS. Los tests comparan el cuadro completo
contra la referencia anterior: todos los trenes, estaciones y minutos.

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

La app descarga el calendario oficial de feriados y lo vuelve a consultar
cada **14 días desde la última descarga exitosa**
(`https://www.argentina.gob.ar/sites/default/files/holidays-<año>-es.json`)
y lo guarda localmente. También obtiene los años que cubren las búsquedas y
alertas de los próximos 60 días, incluso antes de diciembre. Si la consulta
falla, conserva el calendario anterior y reintenta en el siguiente chequeo.
Los feriados inamovibles, trasladables y turísticos
aplican el cuadro de domingos automáticamente en la búsqueda y en las
alertas; los días "no laborables" mantienen el horario normal. Si el
calendario del año consultado todavía no se descargó, la búsqueda usa el
cuadro que corresponde al día de la semana.

## Actualizaciones y alertas en segundo plano

Android y iOS solicitan un chequeo periódico cada 12 horas. El PDF se vuelve a
descargar cuando cambia el mes; los feriados se refrescan cuando cumplen 14
días. Al abrir o retomar la app también se comprueban ambas actualizaciones.

Las alertas se programan para **fechas concretas**, hasta 60 días hacia adelante,
con el contenido de cada fecha: un jueves feriado no reutiliza sus horarios el
jueves siguiente. La agenda se renueva al editar alertas, al abrir o retomar la
app y durante los chequeos en segundo plano, aunque no haya un PDF nuevo.

Se respetan los límites de notificaciones pendientes: hasta 63 avisos de trenes
más un recordatorio de renovación en iOS; hasta 499 más un recordatorio en
Android. Se priorizan los avisos más próximos entre todas las alertas. Si el
sistema no pudo renovar la agenda, el último aviso pide abrir la app para
continuar recibiendo alertas. Las fechas cuyo calendario no está disponible
se identifican como «Feriados sin verificar» en la notificación.

En iOS está configurado `BGTaskScheduler` con `BGAppRefreshTask`. **iOS decide
cuándo ejecutarlo** según el uso de la app, la batería y los permisos de
actualización en segundo plano. Forzar el cierre o desactivar esa función
puede impedir las renovaciones; abrir la app permite realizarlas. Android
también puede diferir trabajo por ahorro de batería. Ninguna plataforma
garantiza el chequeo exactamente cada 12 horas ni en el instante en que vence
el calendario. Los avisos ya programados funcionan sin conexión.

## Limitaciones conocidas / futuro

- Sin seguimiento en tiempo real (previsto a futuro).

## Licencia

Copyright (C) 2026 Lucas Grasso.

El código original de este proyecto se distribuye bajo la **GNU General Public
License, versión 3 únicamente** (`GPL-3.0-only`). Podés redistribuirlo y/o
modificarlo bajo los términos de esa licencia. Se proporciona sin garantía;
consultá el texto completo en [LICENSE](LICENSE).

Las dependencias y los recursos de terceros conservan sus respectivas licencias.
Esta licencia no concede derechos sobre los horarios, los PDF ni los datos de
feriados obtenidos de fuentes externas. Los archivos de fuentes Segoe UI
incluidos en `assets/fonts/` tampoco quedan cubiertos por la GPL del proyecto;
sus derechos de redistribución deben resolverse o deben reemplazarse antes de
una publicación pública.
