import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Llamadas telefónicas nativas (Android, canal `sense_care/phone` en
/// MainActivity): marca sin abrir el marcador y en altavoz, para que la voz de
/// la app se oiga dentro de la llamada. En otras plataformas no hace nada.
class PhoneCallService {
  static const _channel = MethodChannel('sense_care/phone');

  /// Pide los permisos de llamadas y del registro de llamadas (para saber si
  /// contestaron). `true` si se puede marcar.
  Future<bool> requestPermission() => _invoke('requestCallPermission');

  /// Marca a [number]. `false` si no hay permiso o el sistema lo rechaza.
  Future<bool> placeCall(String number) =>
      _invoke('placeCall', {'number': number});

  /// Si el teléfono sigue en una llamada (marcando o hablando).
  Future<bool> isInCall() => _invoke('isInCall');

  /// Si contestaron la llamada saliente hecha desde [since], según el registro
  /// de llamadas (duración > 0). `null` si aún no está registrada o sin permiso.
  Future<bool?> wasAnswered(DateTime since) async {
    try {
      return await _channel.invokeMethod<bool>(
          'wasAnswered', {'since': since.millisecondsSinceEpoch});
    } on MissingPluginException {
      return null;
    } on PlatformException catch (e) {
      debugPrint('Llamada: "wasAnswered" falló: ${e.message}');
      return null;
    }
  }

  Future<bool> _invoke(String method, [Object? arguments]) async {
    try {
      return await _channel.invokeMethod<bool>(method, arguments) ?? false;
    } on MissingPluginException {
      return false; // Sin soporte nativo (iOS, web, pruebas).
    } on PlatformException catch (e) {
      debugPrint('Llamada: "$method" falló: ${e.message}');
      return false;
    }
  }
}
