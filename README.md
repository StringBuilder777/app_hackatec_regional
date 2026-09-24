# app_hackatec_regional

App móvil en **Flutter** para el Hackatec Regional. La distribución se hace
**por APK** (sideload), no por Play Store.

> El módulo de hardware conectado por cable (USB/serial) queda **fuera de alcance
> por ahora**. Esta app está centrada en **notificaciones de cuidados**: alertas
> ricas (imagen, sonido, vibración, flash, pantalla completa), login, y perfiles
> de configuración por usuario. El backend de alertas será **AWS SNS → FCM** (ver
> [`docs/AWS_SNS_FCM.md`](docs/AWS_SNS_FCM.md)); por ahora corre en modo local.

## Requisitos

- Flutter **3.44.0** (canal stable) o superior — Dart **3.12+**
- Android SDK instalado (verifica con `flutter doctor`)
- Solo se generó la plataforma **Android**. Para añadir otra:
  `flutter create --platforms ios,web .`

## Puesta en marcha

```bash
flutter pub get      # instala dependencias
flutter run          # corre en un emulador o dispositivo conectado
```

## Generar el APK (distribución)

APK universal (sirve para cualquier dispositivo, ideal para pasarlo entre gente):

```bash
flutter build apk --release
```

El archivo queda en:

```
build/app/outputs/flutter-apk/app-release.apk
```

Para instalarlo: pasa ese `.apk` al teléfono y habilita "Instalar apps de fuentes
desconocidas". El APK release se firma con la llave de debug por defecto, lo cual
es suficiente para sideload. (Para Play Store habría que configurar un keystore
propio en `android/app/build.gradle.kts`).

APKs más ligeros, uno por arquitectura (opcional):

```bash
flutter build apk --release --split-per-abi
```

La versión se controla en `pubspec.yaml` (`version: 1.0.0+1`) → `versionName+versionCode`.

## Estructura

```
lib/
  main.dart          # arranque: init de servicios + MultiProvider + AuthGate
  app/               # tema (Material 3) y shell con bottom-nav (Alertas/Perfil)
  core/services/     # storage, notificaciones (imagen/sonido/vibración/flash), push (FCM)
  models/            # Alert, CareProfile
  providers/         # auth, alerts, profiles (ChangeNotifier + shared_preferences)
  features/          # login, alerts (lista/detalle/simular), profile (CRUD de perfiles)
android/             # proyecto nativo (applicationId com.hackatec.app_hackatec_regional)
docs/AWS_SNS_FCM.md  # cómo activar notificaciones remotas AWS SNS -> FCM
test/                # pruebas unitarias de modelos
pubspec.yaml         # dependencias y metadatos
```

## Notificaciones (núcleo de la app)

Las notificaciones son la parte central. `NotificationService`
(`lib/core/services/notification_service.dart`) muestra alertas con:

- **Imagen** (BigPicture, descargando la `imageUrl` remota),
- **sonido** y **vibración** por canal,
- **flash** del dispositivo y **pantalla completa** en alertas `critical`,
- **recordatorios de medicación** agendados desde los perfiles.

Para probarlo sin backend: inicia sesión (cualquier correo + contraseña de 4+
caracteres) y pulsa **"Simular alerta"** en la pantalla de Alertas. La activación
del backend real (AWS SNS → FCM) está documentada en
[`docs/AWS_SNS_FCM.md`](docs/AWS_SNS_FCM.md).

## Verificación

```bash
flutter analyze        # análisis estático
flutter test           # pruebas
```
