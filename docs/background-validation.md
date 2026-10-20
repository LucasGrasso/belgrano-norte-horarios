# Validación de actualizaciones y alertas

## Pruebas automatizadas

`flutter test` cubre el vencimiento exacto de 14 días, migración del caché,
fallos HTTP y de formato, recuperación y cobertura de noviembre a enero.
También comprueba jueves feriado → jueves normal y viceversa, cambio de año,
horarios de Argentina, límites globales de notificaciones, renovación sin PDF
nuevo y eliminación de alertas durante una actualización.

El test del scheduler comprueba que las notificaciones no repiten su contenido,
que se cancelan las pendientes antiguas y que los re-agendados no se intercalan.
Las notificaciones ya entregadas no se borran al renovar la agenda.

Los pull requests también compilan un IPA sin firmar con versión de prueba
`0.0.0+1` para validar el código nativo de iOS. Ese artefacto de CI no se publica
como release.

## iPhone real / Xcode

La compilación no prueba que iOS vaya a conceder tiempo de ejecución. Verificar
en un dispositivo con Actualización en segundo plano y notificaciones activas:

1. Crear una alerta y dejar la app en segundo plano.
2. En una sesión de depuración de Xcode, simular el lanzamiento de la tarea:

   ```text
   e -l objc -- (void)[[BGTaskScheduler sharedScheduler] _simulateLaunchForTaskWithIdentifier:@"ar.com.lucasgrasso.tren_bn_horarios.monthlyUpdate"]
   ```

   Esta API es sólo para la consola de depuración, no forma parte de la app.
3. Confirmar que se ejecuta `updateWorkerDispatcher`, que los plugins de
   almacenamiento/notificaciones están disponibles y que se renuevan los avisos
   incluso cuando el PDF mensual no está vencido.
4. Repetir sin conexión: se debe renovar primero con los datos guardados y
   conservar el caché si las descargas fallan.
5. Confirmar que los avisos en feriado y en la semana siguiente tienen horarios
   distintos cuando corresponde. Crear muchas alertas: no se deben superar
   64 notificaciones pendientes y la última debe pedir renovar la agenda.
6. Desactivar Actualización en segundo plano y forzar el cierre para verificar
   que los avisos pendientes siguen disponibles y abrir la app repone la agenda.

Las ejecuciones reales son discrecionales y pueden diferirse por batería,
patrones de uso o configuración del sistema. El vencimiento de 14 días es la
política de descarga, no una promesa de ejecución a una hora exacta.

## Android real

Verificar permiso de notificaciones, alarmas exactas denegadas/permitidas,
reinicio del teléfono y ahorro de batería. Las alarmas inexactas deben seguir
programándose si no se permite usar alarmas exactas. La renovación periódica
no exige conexión: debe poder usar los datos guardados.
