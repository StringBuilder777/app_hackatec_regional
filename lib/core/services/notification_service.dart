import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;
import 'package:torch_light/torch_light.dart';
import 'package:vibration/vibration.dart';

import '../../models/alert.dart';
import '../../models/care_profile.dart';

/// Núcleo de la app: muestra alertas ricas (imagen, sonido, vibración, flash,
/// pantalla completa) y agenda recordatorios de medicación.
///
/// Es agnóstico del origen de la alerta: la misma ruta sirve para una alerta
/// simulada o para una que llegue mañana desde AWS SNS -> FCM.
class NotificationService {
  static const criticalChannelId = 'alertas_criticas';
  static const alertChannelId = 'alertas';
  static const reminderChannelId = 'recordatorios';

  /// Patrón de vibración de emergencia (ms: espera, vibra, espera, vibra...).
  /// Se aplica en el canal crítico (que es quien manda en Android 8+) y en el
  /// refuerzo háptico manual, para que ambos vibren igual.
  static const _criticalPattern = <int>[0, 500, 250, 500, 250, 800];

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _ready = false;

  /// Se invoca cuando el usuario toca una notificación (payload = id de alerta).
  void Function(String? payload)? onTap;

  Future<void> init() async {
    if (_ready) return;

    // Zona horaria: necesaria para agendar recordatorios con hora local.
    tzdata.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation(await _resolveTimeZone()));

    const androidInit =
        AndroidInitializationSettings('@drawable/ic_stat_sense_care');
    const initSettings = InitializationSettings(android: androidInit);
    await _plugin.initialize(
      settings: initSettings,
      onDidReceiveNotificationResponse: (resp) => onTap?.call(resp.payload),
    );

    await _createChannels();
    await _requestPermissions();
    _ready = true;
  }

  Future<String> _resolveTimeZone() async {
    try {
      final dynamic info = await FlutterTimezone.getLocalTimezone();
      if (info is String && info.isNotEmpty) return info;
      final id = (info as dynamic).identifier; // flutter_timezone >= 4
      if (id is String && id.isNotEmpty) return id;
    } catch (_) {
      // Sin permiso/plugin: usamos una zona por defecto (México).
    }
    return 'America/Mexico_City';
  }

  Future<void> _requestPermissions() async {
    final android = _androidPlugin;
    await android?.requestNotificationsPermission();
    await android?.requestExactAlarmsPermission();
    // Android 14+: el intent a pantalla completa exige permiso propio; sin él
    // las alertas críticas caen a heads-up en vez de abrir a pantalla completa.
    await android?.requestFullScreenIntentPermission();
  }

  AndroidFlutterLocalNotificationsPlugin? get _androidPlugin =>
      _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();

  Future<void> _createChannels() async {
    final android = _androidPlugin;
    if (android == null) return;
    await android.createNotificationChannel(AndroidNotificationChannel(
      criticalChannelId,
      'Alertas críticas',
      description: 'Emergencias que requieren atención inmediata',
      importance: Importance.max,
      enableLights: true,
      ledColor: const Color(0xFFD32F2F),
      enableVibration: true,
      // En Android 8+ el patrón lo define el canal, no la notificación.
      vibrationPattern: Int64List.fromList(_criticalPattern),
    ));
    await android.createNotificationChannel(const AndroidNotificationChannel(
      alertChannelId,
      'Alertas',
      description: 'Alertas generales de cuidado',
      importance: Importance.high,
      enableVibration: true,
    ));
    await android.createNotificationChannel(const AndroidNotificationChannel(
      reminderChannelId,
      'Recordatorios',
      description: 'Recordatorios de medicación y rutinas',
      importance: Importance.high,
      enableVibration: true,
    ));
  }

  // --- Mostrar una alerta -------------------------------------------------

  Future<void> showAlert(Alert alert) async {
    if (!_ready) await init();
    final isCritical = alert.severity == AlertSeverity.critical;
    final channelId = isCritical ? criticalChannelId : alertChannelId;

    final imagePath =
        alert.hasImage ? await _downloadImage(alert.imageUrl!) : null;

    final StyleInformation style = imagePath != null
        ? BigPictureStyleInformation(
            FilePathAndroidBitmap(imagePath),
            largeIcon: FilePathAndroidBitmap(imagePath),
            contentTitle: alert.title,
            summaryText: alert.body,
            hideExpandedLargeIcon: true,
          )
        : BigTextStyleInformation(alert.body, contentTitle: alert.title);

    final details = AndroidNotificationDetails(
      channelId,
      isCritical ? 'Alertas críticas' : 'Alertas',
      channelDescription: 'Alertas de cuidado',
      importance: Importance.max,
      priority: Priority.high,
      category: AndroidNotificationCategory.alarm,
      visibility: NotificationVisibility.public,
      fullScreenIntent: isCritical,
      color: alert.severity.color,
      styleInformation: style,
      largeIcon:
          imagePath != null ? FilePathAndroidBitmap(imagePath) : null,
      enableLights: true,
      ledColor: alert.severity.color,
      ledOnMs: 1000,
      ledOffMs: 500,
      enableVibration: true,
      // Solo aplica en Android < 8 (en 8+ manda el canal). Se alinea con el
      // patrón del canal para las críticas y usa uno breve para el resto.
      vibrationPattern:
          Int64List.fromList(isCritical ? _criticalPattern : const [0, 400]),
      ticker: alert.title,
    );

    await _plugin.show(
      id: _idFrom(alert.id),
      title: alert.title,
      body: alert.body,
      notificationDetails: NotificationDetails(android: details),
      payload: alert.id,
    );

    // Refuerzo háptico y visual (con la app en primer plano). El flash no se
    // espera para no retrasar ~2 s el resto del flujo de la alerta.
    await _vibrate(isCritical);
    if (isCritical) unawaited(_flash());
  }

  Future<String?> _downloadImage(String url) async {
    try {
      final resp =
          await http.get(Uri.parse(url)).timeout(const Duration(seconds: 10));
      if (resp.statusCode != 200) return null;
      final dir = await getTemporaryDirectory();
      final file = File(
          '${dir.path}/alert_${DateTime.now().millisecondsSinceEpoch}.png');
      await file.writeAsBytes(resp.bodyBytes);
      return file.path;
    } catch (e) {
      debugPrint('No se pudo descargar la imagen de la alerta: $e');
      return null;
    }
  }

  Future<void> _vibrate(bool critical) async {
    try {
      if (await Vibration.hasVibrator() != true) return;
      if (critical) {
        await Vibration.vibrate(pattern: _criticalPattern);
      } else {
        await Vibration.vibrate(duration: 400);
      }
    } catch (_) {
      // Dispositivo sin vibrador: ignorar.
    }
  }

  bool _flashing = false;

  Future<void> _flash({int times = 5}) async {
    // Evita que dos alertas solapen los destellos y dejen la linterna encendida.
    if (_flashing) return;
    _flashing = true;
    try {
      for (var i = 0; i < times; i++) {
        await TorchLight.enableTorch();
        await Future.delayed(const Duration(milliseconds: 180));
        await TorchLight.disableTorch();
        await Future.delayed(const Duration(milliseconds: 180));
      }
    } catch (e) {
      debugPrint('Flash no disponible en este equipo: $e');
    } finally {
      // Pase lo que pase, la linterna debe quedar apagada.
      try {
        await TorchLight.disableTorch();
      } catch (_) {}
      _flashing = false;
    }
  }

  /// Dispara sólo el flash (útil para probarlo desde la UI).
  Future<void> flashOnly() => _flash();

  // --- Recordatorios de medicación ---------------------------------------

  Future<void> scheduleMedication(
    MedicationReminder med, {
    required String profileName,
  }) async {
    if (!_ready) await init();
    try {
      await _zonedSchedule(
          med, profileName, AndroidScheduleMode.exactAllowWhileIdle);
    } catch (e) {
      // Sin permiso de alarmas exactas: caemos a inexacto.
      debugPrint('Recordatorio exacto no permitido, usando inexacto: $e');
      await _zonedSchedule(
          med, profileName, AndroidScheduleMode.inexactAllowWhileIdle);
    }
  }

  Future<void> _zonedSchedule(
    MedicationReminder med,
    String profileName,
    AndroidScheduleMode mode,
  ) async {
    await _plugin.zonedSchedule(
      id: _idFrom(med.id),
      title: 'Hora de medicación: ${med.name}',
      body: 'Perfil: $profileName',
      scheduledDate: _nextInstanceOfTime(med.hour, med.minute),
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          reminderChannelId,
          'Recordatorios',
          channelDescription: 'Recordatorios de medicación y rutinas',
          importance: Importance.high,
          priority: Priority.high,
          category: AndroidNotificationCategory.reminder,
        ),
      ),
      androidScheduleMode: mode,
      matchDateTimeComponents: DateTimeComponents.time, // repetir cada día
    );
  }

  Future<void> cancelMedication(String medId) =>
      _plugin.cancel(id: _idFrom(medId));

  Future<void> cancelAll() => _plugin.cancelAll();

  tz.TZDateTime _nextInstanceOfTime(int hour, int minute) {
    final now = tz.TZDateTime.now(tz.local);
    var scheduled =
        tz.TZDateTime(tz.local, now.year, now.month, now.day, hour, minute);
    if (!scheduled.isAfter(now)) {
      scheduled = scheduled.add(const Duration(days: 1));
    }
    return scheduled;
  }

  /// Id de notificación estable (32 bits) derivado de un id de texto.
  int _idFrom(String id) => id.hashCode & 0x7fffffff;
}
