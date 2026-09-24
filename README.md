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

Para probarlo: inicia sesión con tu usuario y contraseña de Cognito (el
usuario no tiene que ser un correo) y pulsa **"Simular alerta"** en la pantalla de Alertas. La activación
del backend real (AWS SNS → FCM) está documentada en
[`docs/AWS_SNS_FCM.md`](docs/AWS_SNS_FCM.md).

## Llamada automática de emergencia

Si una alerta es grave o nadie la atiende, la app **marca sola desde la SIM, en
altavoz**, y una **voz** (texto a voz, `flutter_tts`) explica lo que pasa
(`EmergencyCallProvider`, `lib/providers/emergency_call_provider.dart`).

| Alerta     | Cuándo marca                  | Se cancela con                                  |
|------------|-------------------------------|-------------------------------------------------|
| `critical` | a los 15 s (avisa en voz)     | "No llamar" o "Cancelar alerta" (falsa alarma)  |
| `warning`  | a los 60 s si sigue activa    | "No llamar", tocar su notificación o marcarla como vista |
| `info`     | nunca                         | —                                               |

- **Dónde se ve:** el aviso con la cuenta regresiva flota arriba de cualquier
  pantalla. Si el teléfono ya está en una llamada, la siguiente espera a que
  cuelguen y se puede cancelar mientras espera.
- **A quién:** cada perfil guarda dirección, responsable y contacto de
  emergencia. Con "Yo soy el responsable" se llama a tu contacto de emergencia;
  si no, al responsable. Un perfil pausado no llama.
- **Qué dice:** al responsable, *"Hola, Ana. Te llamo de Sense Care. Luis tuvo
  un accidente: se cayó. ¿Puedes llegar para ayudarle? Si no puedes, llama a
  emergencias al 911."*; al contacto de emergencia, *"Luis Emilio Pérez se
  cayó. Es una persona adulta mayor y necesita ayuda. La dirección es: …"*.
  En una advertencia pide comunicarse o ir a revisar, sin mencionar el 911.

Límites de Android (probar en los teléfonos de la demo):

- Una app no puede meter audio dentro de una llamada celular: la voz suena por
  el altavoz y la otra persona la oye por el micrófono. Sube el volumen.
- Android no avisa cuándo contestan ni deja oír la respuesta: la voz empieza a
  los 6 s y repite el mensaje (hasta 5 veces) mientras siga la llamada.
- Una app no puede marcar sola al 911 (solo abre el marcador): el contacto debe
  ser el número de una persona.
- La alerta tiene que llegar con la app al frente y desbloqueada; después la
  cuenta regresiva y la llamada siguen aunque pase a segundo plano. Un push que
  llega con la app en segundo plano, bloqueada o cerrada todavía no dispara
  nada (FCM lo manda al handler de background, que está vacío). Si Android
  cierra la app durante la cuenta regresiva, esa llamada se pierde.
- Con dos SIM, elige una SIM predeterminada para llamadas o Android preguntará.

## Verificación

```bash
flutter analyze        # análisis estático
flutter test           # pruebas
```
