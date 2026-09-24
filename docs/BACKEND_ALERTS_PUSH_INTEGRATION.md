# Conectar la app a las alertas reales del backend

Hoy la app corre en **modo local**: `AlertsProvider` sólo persiste alertas
simuladas por el botón "Simular alerta" o por un push ya recibido
(`Alert.fromPushData`), y nunca llama al backend para leer/decidir sobre un
caso. `SenseCareApiService` sólo implementa `pairDevice`, `getDeviceLatest`
y `getDeviceTelemetry`. Este documento es el plan para cerrar esa brecha,
una vez que el backend despliegue la sección "Hito de notificaciones push y
confirmación de voz" de
`HackaTec2026Regional-Backend/docs/IMPLEMENTATION_ROADMAP.md`.

Ver también `docs/AWS_SNS_FCM.md` (ya existente) para la parte de
Firebase/`google-services.json` — este documento no la repite, sólo cubre
la parte de API HTTP que faltaba ahí.

## Estado de implementación (secciones 2-4)

Las secciones 2, 3 y 4 de este documento ya están implementadas en código
(`SenseCareApiService`, `AuthProvider`, `AlertsProvider`, `alerts_screen.dart`).
El plan de abajo se dejó tal cual para referencia histórica; las
desviaciones reales respecto a lo escrito aquí fueron:

- **Sección 2 -- `CaseDecisionResult`**: en vez de `{ applied: false,
  currentAlertStatus }`, se implementó como `{ caseId, alertStatus,
  conflict, error }` (`lib/models/case_decision_result.dart`). `conflict`
  reemplaza a `applied` invertido (`conflict == !applied`) y se agregó
  `error` para no perder el mensaje del backend en el 409. El razonamiento
  completo de por qué NO es una `ApiException` está documentado como
  comentario en la propia clase.
- **Sección 3 -- registro de push**: se implementó dentro de
  `AuthProvider.login()` (llamando a `_registerPushDevice()` justo tras un
  login exitoso), no vía un `ChangeNotifierProxyProvider` observando la
  transición de `isLoggedIn`. Motivo: es un efecto secundario del evento
  "login exitoso", que ya vive en `AuthProvider`; no hay estado nuevo que la
  UI deba observar, así que un provider intermedio sólo para reenviar el
  idToken habría sido una capa de más. `AuthProvider` ahora recibe
  `push`/`api` opcionales (`main.dart` los pasa). El `endpointId` se guarda
  con `StorageService` y se da de baja en `AuthProvider.logout()`.
- **Sección 4 -- `AlertsProvider`**: para que `cancel`/`escalate` puedan
  llamar al backend sin que la UI tenga que pasar el `idToken` a mano, se
  añadió un `ChangeNotifierProxyProvider<AuthProvider, AlertsProvider>` en
  `main.dart` (mismo patrón que `DevicesProvider`) que le inyecta un
  `String? Function() tokenProvider`. `syncFromBackend(idToken)` sí
  conserva la firma exacta descrita abajo (recibe el `idToken` explícito de
  quien lo invoca, hoy `AlertsScreen.initState`).
- **No implementado: polling corto en `AlertsScreen`.** Sólo se sincroniza
  una vez al abrir la pantalla (`initState`, después del primer frame,
  igual que `DeviceDetailScreen.startPolling`). Se dejó así por alcance/
  tiempo: la sincronización al abrir ya cubre la prueba de aceptación de la
  sección 5 (reflejar `CANCELLED`/`ESCALATED` resueltos por otra vía en el
  próximo `syncFromBackend`); un `Timer.periodic` como el de
  `DevicesProvider` se puede añadir después sin cambiar el resto del
  diseño.
- `AlertStatus` no ganó un valor `escalated` propio: un caso `ESCALATED`
  sigue siendo `AlertStatus.active` (nada cambia en lo que el cuidador debe
  hacer), pero el `alertStatus` real del backend se guarda en
  `Alert.data['alertStatus']` para quien lo necesite mostrar. La UI
  (`AlertDetailScreen`) sí distingue el resultado con un SnackBar
  inmediatamente después de escalar/cancelar.

## 1. Prerrequisito externo (ruta crítica, no depende de código)

Crear el proyecto Firebase y obtener `google-services.json` (pasos 1–5 de
`docs/AWS_SNS_FCM.md`). Sin esto, `FcmPushService.initialize()` sigue en
modo local aunque el resto de esta integración esté completa — no hay push
real que probar. Iniciar esto en paralelo a todo lo demás.

## 2. Extender `SenseCareApiService`

Agregar, siguiendo el mismo patrón de `_send`/`_decodeOrThrow` ya existente:

- `Future<String> registerPushDevice({required String platform, required String token, required String idToken})`
  → `POST /me/push-devices`, body `{ platform, token }`, respuesta
  `{ endpointId }`.
- `Future<void> unregisterPushDevice({required String endpointId, required String idToken})`
  → `DELETE /me/push-devices/{endpointId}`.
- `Future<List<CaseSummary>> listCases({required String idToken})`
  → `GET /cases`. Nuevo modelo `CaseSummary` (`caseId`, `deviceId`,
  `eventType`, `anomalyType`, `severity`, `alertStatus`, `evidenceStatus`,
  `analysisStatus`, `createdAt`, `updatedAt`) en `lib/models/`.
- `Future<List<CaseEvent>> getCaseEvents({required String caseId, required String idToken})`
  → `GET /cases/{caseId}/events`.
- `Future<CaseDecisionResult> cancelCase({required String caseId, required String idToken})`
  y el mismo para `escalateCase` → `POST /cases/{caseId}/cancel` /
  `/escalate`. Un `409` no es una `ApiException` más: modelarlo como
  resultado tipado (`{ applied: false, currentAlertStatus }`) para que la
  UI pueda mostrar "ya fue decidido por otra vía" sin un catch genérico.

## 3. Registrar el token de push tras iniciar sesión

En el flujo que ya conecta `AuthProvider` con `DevicesProvider` (ver
`main.dart`, `ChangeNotifierProxyProvider<AuthProvider, DevicesProvider>`):
cuando `AuthProvider.isLoggedIn` pasa a `true` y `push.isAvailable` es
`true`, llamar `push.deviceToken()` y luego
`SenseCareApiService.registerPushDevice(...)` una sola vez por sesión
(guardar el `endpointId` devuelto en `StorageService` para poder llamar
`unregisterPushDevice` al cerrar sesión). Si `push.isAvailable` es `false`
(sin `google-services.json` todavía), simplemente no registrar nada — la
app sigue funcionando en modo local, igual que hoy.

## 4. `AlertsProvider`: pasar de sólo-local a sincronizado

- Nuevo método `Future<void> syncFromBackend(String idToken)`: llama
  `listCases`, mapea cada `CaseSummary` a un `Alert` (id = `caseId`,
  severity desde `severity`/`eventType`, status desde `alertStatus`
  — `PENDING`/`SENT` → `active`, `CANCELLED` → `canceled`, `ESCALATED` →
  mantenerlo `active` pero marcado, según se decida en UI), y hace merge
  con `_alerts` por `id` (nunca duplica ni pisa una alerta ya marcada
  `viewed` localmente sólo porque el backend todavía diga `SENT`).
- `cancel(id)` y una nueva acción `escalate(id)`: si el `Alert.data`
  contiene un `caseId` real (viene de `syncFromBackend` o de un push del
  backend, a diferencia de las alertas `seed-*`/`sim-*` puramente locales),
  llamar `SenseCareApiService.cancelCase`/`escalateCase` ANTES de actualizar
  el estado local; si el backend responde conflicto (409), reflejar el
  `currentAlertStatus` real en vez del que el usuario pidió.
- Mantener el botón "Simular alerta" tal cual: sigue siendo útil sin
  conexión/como respaldo de demo, y no debe intentar llamar al backend con
  un `caseId` que no existe ahí.
- Llamar `syncFromBackend` al entrar a `AlertsScreen` y opcionalmente con
  un polling corto (mismo intervalo que el simulador web,
  `frontend-equipo404`, para consistencia visual en la demo).

## 5. Prueba de aceptación

- Con `google-services.json` real: la app registra su token al iniciar
  sesión, y `GET /me/push-devices` (o el runbook del backend) confirma el
  endpoint activo.
- Una anomalía crítica real (o vía simulador) dispara un push data-only;
  la app lo muestra con `NotificationService.showAlert` y también aparece
  en `AlertsScreen` con el mismo `caseId`.
- Tocar "Cancelar alerta" en la app resuelve el caso en el backend
  (verificable con `GET /cases/{caseId}/events` desde el simulador o CLI);
  un segundo intento de "Escalar" desde la app da conflicto y la UI muestra
  el estado real (`CANCELLED`), no un error genérico.
- Si el `VOICE_CHECKIN` de la Pi resuelve el caso primero, la próxima vez
  que la app sincroniza (`syncFromBackend`) refleja `ESCALATED`/`CANCELLED`
  aunque el usuario nunca haya tocado nada — la sincronización es la
  fuente de verdad, no el estado local optimista.

## 6. Qué se puede paralelizar

Las secciones 2 (cliente HTTP) y 3 (registro de push) no dependen de la 4
(wiring de `AlertsProvider`) para *compilar* — pueden escribirse en
paralelo y converger sólo al conectar `syncFromBackend`/`cancel`/`escalate`
a la UI existente (`alerts_screen.dart`, `AlertDetailScreen`). Ambas
requieren, sin embargo, el contrato ya fijado en
`BACKEND/docs/IMPLEMENTATION_ROADMAP.md` (sección "Hito de notificaciones
push y confirmación de voz") — no requieren esperar a que el backend
despliegue para escribir el código, sólo para probarlo de punta a punta.
