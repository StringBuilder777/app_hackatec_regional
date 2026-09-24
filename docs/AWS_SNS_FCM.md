# Activar notificaciones remotas: AWS SNS → FCM

Hoy la app corre en **modo local**: las alertas se muestran con
`flutter_local_notifications` (imagen, sonido, vibración, flash, pantalla
completa) y se pueden disparar con el botón **"Simular alerta"**. No hace falta
backend para probar todo el flujo visual.

Cuando el backend en **AWS SNS** esté listo, en Android la entrega se hace a
través de **Firebase Cloud Messaging (FCM)**. La app ya tiene la costura lista
(`lib/core/services/push_service.dart`, clase `FcmPushService`), que se
autodegrada si aún no hay credenciales.

## Arquitectura

```
Backend  ──►  AWS SNS (Platform Application: FCM)
                   │  registra el token del dispositivo como Endpoint
                   ▼
              FCM (Google)
                   │  push data-only  { id, title, body, imageUrl, severity }
                   ▼
        App Flutter  ──►  FcmPushService.onData
                   │
                   ▼
   AlertsProvider.receiveIncoming(Alert) ──► NotificationService.showAlert()
```

Recomendación: enviar **mensajes data-only** (sólo `data`, sin bloque
`notification`). Así la app siempre construye la notificación con
`NotificationService` y controla imagen, canal, vibración y flash. Un mensaje
`notification` lo dibuja el sistema y perderías ese control.

## Formato del payload (data)

Todos los valores como string:

| clave      | ejemplo                            | notas                                   |
|------------|------------------------------------|-----------------------------------------|
| `id`       | `alert-123`                        | opcional; se genera si falta            |
| `title`    | `Caída detectada`                  |                                         |
| `body`     | `Posible caída en la habitación`   |                                         |
| `imageUrl` | `https://.../foto.jpg`             | opcional; se muestra como BigPicture    |
| `severity` | `info` / `warning` / `critical`    | `critical` = flash + pantalla completa  |
| `profileId`| `profile-1727000000000`            | opcional; persona de la alerta para la llamada automática (si falta, el primer perfil activo) |

(Se mapea en `Alert.fromPushData`.)

## Pasos para activarlo

1. **Crear proyecto Firebase** y registrar la app Android con el applicationId
   `com.hackatec.app_hackatec_regional`.
2. Descargar **`google-services.json`** y colocarlo en `android/app/`.
3. En `android/settings.gradle.kts`, dentro de `plugins { ... }`, agregar:
   ```kotlin
   id("com.google.gms.google-services") version "4.4.2" apply false
   ```
4. En `android/app/build.gradle.kts`, descomentar la línea:
   ```kotlin
   id("com.google.gms.google-services")
   ```
5. `flutter pub get` y recompilar. Al abrir la app, `FcmPushService.initialize()`
   ya no caerá en modo local; en el log verás **"FCM listo. Token de
   dispositivo: ..."**.
6. **AWS SNS**: crear una *Platform Application* tipo **FCM** con la credencial
   del proyecto Firebase. Registrar el token del dispositivo como *Platform
   Endpoint* (envía `FcmPushService.deviceToken()` a tu backend para que lo
   registre).
7. Publicar con el JSON de FCM, por ejemplo:
   ```json
   { "GCM": "{ \"data\": { \"title\": \"Caída detectada\", \"severity\": \"critical\", \"imageUrl\": \"https://...\" } }" }
   ```

## Permisos ya configurados (AndroidManifest)

`POST_NOTIFICATIONS`, `VIBRATE`, `USE_FULL_SCREEN_INTENT`,
`SCHEDULE_EXACT_ALARM` / `USE_EXACT_ALARM`, `RECEIVE_BOOT_COMPLETED`,
`WAKE_LOCK`, `INTERNET` y `camera.flash`. El canal por defecto de FCM
(`alertas_criticas`) ya está declarado en el manifest.

## Notas

- `minSdk` debe ser **>= 23** (lo exigen `torch_light` y `firebase_messaging`).
  El template usa `flutter.minSdkVersion`; verifica que resuelva a 23+ o fíjalo
  explícitamente si el build se queja.
- Sonido / flash / vibración se controlan por canal y en `NotificationService`.
  Para un sonido propio, agrega un `.mp3`/`.wav` en
  `android/app/src/main/res/raw/` y referencia
  `RawResourceAndroidNotificationSound` en el canal correspondiente.
- **Flash / vibración de refuerzo**: hoy se disparan cuando la app procesa la
  alerta en primer plano (`showAlert`). Con la app en segundo plano, el sistema
  muestra la notificación (sonido y vibración del canal) pero el flash extra no
  se ejecuta; para flash garantizado en background hay que procesarlo en
  `firebaseBackgroundHandler`.
- **Ícono de la barra de estado**: usa `@mipmap/ic_launcher` (a color). Para que
  no se vea como cuadro blanco en algunos equipos, agrega un `drawable`
  monocromo y referencia ese ícono en `AndroidInitializationSettings` y en la
  meta-data `default_notification_icon`.
