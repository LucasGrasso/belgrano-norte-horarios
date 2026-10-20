# Releases de Android e iOS

Los workflows generan un APK instalable, un AAB para Google Play y un IPA
firmado. Al subir un tag `vX.Y.Z`, primero corren el analizador y los tests;
después compilan ambas plataformas en paralelo y publican los archivos y sus
SHA-256 en un GitHub Release. Si una plataforma falla, no se publica el release;
los artefactos de la otra quedan disponibles en Actions durante 14 días.

La publicación en Google Play, TestFlight o App Store se realiza por separado.
Un IPA de App Store no se puede instalar directamente desde GitHub en cualquier
iPhone: debe pasar por App Store Connect/TestFlight. Para instalación Ad Hoc,
el perfil debe incluir los dispositivos registrados.

## Configuración inicial

En GitHub → Settings → Secrets and variables → Actions, agregar los siguientes
**repository secrets** (nunca subir las claves al repositorio):

| Secret | Contenido |
| --- | --- |
| `ANDROID_KEYSTORE_BASE64` | Keystore de release existente, codificado en Base64 |
| `ANDROID_KEYSTORE_PASSWORD` | Contraseña del keystore |
| `ANDROID_KEY_ALIAS` | Alias de la clave de firma |
| `ANDROID_KEY_PASSWORD` | Contraseña de esa clave |
| `IOS_CERTIFICATE_BASE64` | Certificado **Apple Distribution**, exportado como `.p12` con su clave privada y codificado en Base64 |
| `IOS_CERTIFICATE_PASSWORD` | Contraseña no vacía del `.p12` |
| `IOS_PROVISIONING_PROFILE_BASE64` | Perfil de distribución `.mobileprovision`, codificado en Base64 |

Usar la misma clave Android de versiones previamente distribuidas si se quiere
permitir la actualización de esas instalaciones. El código anterior firmaba
con la clave de debug; una instalación previa con esa clave no podrá actualizarse
con una nueva clave de release y deberá reinstalarse (se pierden datos locales).
Guardar una copia de respaldo del keystore fuera de GitHub.

Para preparar un secreto Base64 sin saltos de línea (Linux o macOS):

```bash
base64 < release.jks | tr -d '\n'
base64 < distribution.p12 | tr -d '\n'
base64 < distribution.mobileprovision | tr -d '\n'
```

El bundle ID de iOS es `ar.com.lucasgrasso.trenBnHorarios`; el perfil debe usar
ese App ID explícito, estar vigente y corresponder al certificado. El equipo
y UUID se leen del perfil. El workflow rechaza perfiles de desarrollo,
enterprise, vencidos o de otro App ID antes de compilar.

La **repository variable** `IOS_EXPORT_METHOD` es opcional:

| Valor | Perfil requerido | Uso |
| --- | --- | --- |
| `app-store-connect` (predeterminado) | App Store | Subir el IPA a App Store Connect/TestFlight |
| `release-testing` | Ad Hoc | Instalar en dispositivos incluidos en el perfil |

No hacen falta credenciales de las tiendas para generar estos artefactos.
`GITHUB_TOKEN` lo provee Actions; sólo el job de publicación recibe
`contents: write`. Las claves temporales se eliminan aun si falla el build.

## Crear un release

1. Actualizar `version: X.Y.Z+N` en `pubspec.yaml`, por ejemplo `0.2.0+2`.
   Incrementar `N` en cada versión distribuida; no depende del número de corrida.
2. Integrar el cambio en `main` y comprobar que los tests pasan.
3. Crear y subir el tag correspondiente al mismo commit:

   ```bash
   git tag v0.2.0
   git push origin v0.2.0
   ```

Se aceptan versiones estables `X.Y.Z`; los tags y la versión deben coincidir.
Los prereleases requieren extender la validación antes de usarlos.

También se puede ejecutar **Mobile release → Run workflow**, seleccionando un
**tag existente** en el selector de referencia. Elegir `android`, `ios` o `both`.
Por defecto, una ejecución manual sólo genera artefactos; activar `publish` para
crear el GitHub Release. Esto permite preparar Android antes de contar con la
membresía/certificados de Apple. La ejecución automática por tag exige ambas
plataformas configuradas.

Una corrida interrumpida puede dejar un borrador; volver a correrla completa
reemplaza sus artefactos y lo publica al terminar. Un release ya publicado no
se sobreescribe: usar una nueva versión. Para un borrador parcial creado con una
selección de plataformas diferente, eliminarlo antes de volver a intentarlo.

## Builds locales

Flutter **3.44.6** (Dart 3.12.2), Java 17 y el lockfile son compartidos con CI.
El workflow de iOS usa macOS 15, Xcode 26.3 y CocoaPods con `--deployment`.
Al actualizar dependencias nativas, actualizar y commitear también
`ios/Podfile.lock` desde un Mac.

Android ya no usa la clave de debug para release. Crear `android/key.properties`
(ignorado por Git), usando una ruta absoluta al keystore:

```properties
storeFile=/ruta/privada/release.jks
storePassword=...
keyAlias=...
keyPassword=...
```

También se aceptan `ANDROID_KEYSTORE_PATH`, `ANDROID_KEYSTORE_PASSWORD`,
`ANDROID_KEY_ALIAS` y `ANDROID_KEY_PASSWORD` como variables de entorno.
`flutter run` y los builds debug no requieren estos secretos.

## Referencias

- [Distribuir Android con Flutter](https://docs.flutter.dev/deployment/android)
- [Distribuir iOS con Flutter](https://docs.flutter.dev/deployment/ios)
- [Instalar certificados Apple en Actions](https://docs.github.com/en/enterprise-cloud%40latest/actions/how-tos/deploy/deploy-to-third-party-platforms/sign-xcode-applications)
- [Toolchains disponibles en macOS 15](https://github.com/actions/runner-images/blob/main/images/macos/macos-15-Readme.md)
