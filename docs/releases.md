# Descargas sin Play Store ni App Store

El workflow **Mobile release** genera dos archivos, sin credenciales de tiendas:

| Archivo | Cómo se instala |
| --- | --- |
| `belgrano-norte.apk` | Descargar e instalar en Android; autorizar al navegador o a la app de archivos si Android lo solicita |
| `belgrano-norte-unsigned.ipa` | **Sin firmar**. Cada usuario debe firmarlo e instalarlo con su propia cuenta y una herramienta de sideloading como AltStore Classic |

El IPA no se instala con sólo tocar un enlace. Con una cuenta gratuita, las
apps instaladas mediante AltStore Classic vencen a los 7 días y deben renovarse;
la instalación inicial requiere configurar la herramienta y normalmente una
computadora. No se necesita una membresía paga del autor para generar el IPA,
pero no es una instalación tan sencilla como un APK. La compatibilidad real
del IPA debe verificarse en un iPhone con esa herramienta.

Ver las instrucciones oficiales de [AltStore Classic](https://faq.altstore.io/altstore-classic/your-altstore)
y [AltServer](https://faq.altstore.io/altstore-classic/altserver).
Para distribución iOS sin esa configuración por usuario, haría falta otra vía
de distribución de Apple o una versión web de la app. Este proyecto todavía
no incluye una versión web.

## Enlaces a la última versión

Una vez que exista un release, los nombres estables permiten compartir siempre
estos enlaces:

- [Último APK para Android](https://github.com/LucasGrasso/belgrano-norte-horarios/releases/latest/download/belgrano-norte.apk)
- [Último IPA sin firmar](https://github.com/LucasGrasso/belgrano-norte-horarios/releases/latest/download/belgrano-norte-unsigned.ipa)
- [Todas las versiones](https://github.com/LucasGrasso/belgrano-norte-horarios/releases)

Mientras el repositorio sea privado, sólo funcionan para personas con acceso.
Al hacerlo público, los releases también serán públicos. No se modifica la
visibilidad desde estos workflows. El enlace al IPA requiere que ese release
haya completado su build de iOS; puede añadirse después con una corrida manual.

Cada archivo incluye un `.sha256` para verificar la descarga. Android mantiene
el mismo identificador de aplicación y clave de firma entre versiones, para
que instalar un APK nuevo actualice la app y conserve sus datos.

## Configuración inicial: clave Android gratuita

Android exige firmar los APK aunque no se use Play Store. La clave se puede
generar localmente con el JDK; no requiere una cuenta de Google ni un pago.
Si ya se distribuyó una versión con una clave de release, reutilizar esa clave.

Para una app nueva, ejecutar fuera del repositorio, en una carpeta privada:

```bash
keytool -genkeypair -v -storetype PKCS12 \
  -keystore belgrano-norte-release.p12 -alias belgrano-norte \
  -keyalg RSA -keysize 2048 -validity 10000
```

Guardar una copia de respaldo de ese archivo y su contraseña. Para PKCS12,
usar la misma contraseña para la clave y el almacén. Obtener su Base64:

```bash
base64 < belgrano-norte-release.p12 | tr -d '\n'
```

En GitHub → Settings → Secrets and variables → Actions, agregar estos cuatro
**repository secrets**. No subir la clave al repositorio:

| Secret | Contenido |
| --- | --- |
| `ANDROID_KEYSTORE_BASE64` | Archivo `.p12`/`.jks` codificado en Base64 |
| `ANDROID_KEYSTORE_PASSWORD` | Contraseña del almacén |
| `ANDROID_KEY_ALIAS` | `belgrano-norte`, o el alias de la clave existente |
| `ANDROID_KEY_PASSWORD` | Contraseña de esa clave |

No se necesitan secretos de Apple. La compilación de iOS usa
`--no-codesign` y empaqueta `Payload/Runner.app` como IPA para firma por el usuario.
El archivo se identifica como **unsigned** en el nombre y en las notas del release.

Las versiones anteriores del proyecto usaban la clave de debug. Si alguien ya
instaló una de esas versiones, cambiar a una clave de release impide actualizarla
directamente: deberá desinstalarla primero y perderá los datos locales. En las
siguientes versiones, conservar siempre la nueva clave de release.

## Publicar una versión

1. Actualizar `version: X.Y.Z+N` en `pubspec.yaml`, por ejemplo `0.2.0+2`.
   Incrementar `N` en cada versión distribuida.
2. Integrar el cambio en `main` y comprobar que CI pasa.
3. Crear y subir el tag del mismo commit:

   ```bash
   git tag v0.2.0
   git push origin v0.2.0
   ```

Los tags deben coincidir con la versión del archivo. Sólo se aceptan versiones
estables `X.Y.Z`. El workflow corre el analizador y los tests, compila ambas
plataformas en paralelo y publica los archivos en GitHub Releases.
Si iOS falla pero Android termina bien, se publica el APK sin bloquear a los
usuarios de Android. Si falla Android, no se crea un nuevo release que deje
sin APK al enlace de la última versión. Los artefactos de builds exitosos
también quedan en Actions durante 14 días.

Desde **Mobile release → Run workflow** se puede seleccionar un **tag existente**
y elegir `android`, `ios` o `both`. Una corrida manual sólo genera artefactos
por defecto; activar `publish` para publicarlos. Después de un release sólo
Android, una corrida `ios` con el mismo tag y `publish` puede añadir el IPA.
Los archivos de un release ya publicado no se sobreescriben; para reemplazar
una descarga, crear una nueva versión. Los borradores incompletos sí admiten
reemplazo al reintentar la corrida.

## Builds locales

Usar Flutter **3.44.6** (Dart 3.12.2), Java 17 y el lockfile. Android no usa
la clave de debug para release. Crear `android/key.properties` (ignorado por Git):

```properties
storeFile=/ruta/privada/belgrano-norte-release.p12
storePassword=...
keyAlias=belgrano-norte
keyPassword=...
```

También se aceptan `ANDROID_KEYSTORE_PATH`, `ANDROID_KEYSTORE_PASSWORD`,
`ANDROID_KEY_ALIAS` y `ANDROID_KEY_PASSWORD` como variables de entorno.
`flutter run` y los builds debug no requieren estos secretos.
El build iOS corre en macOS 15/Xcode 26.3 con CocoaPods `--deployment`;
si cambian dependencias nativas, actualizar `ios/Podfile.lock` desde un Mac.

## Referencias

- [Firma y distribución Android](https://developer.android.com/studio/publish/app-signing)
- [Builds iOS con Flutter](https://docs.flutter.dev/deployment/ios)
- [AltStore Classic: renovación de apps y cuenta gratuita](https://faq.altstore.io/altstore-classic/your-altstore)
- [AltServer: instalación y renovación](https://faq.altstore.io/altstore-classic/altserver)
