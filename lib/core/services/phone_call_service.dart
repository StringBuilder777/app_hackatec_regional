import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Llamadas telefónicas nativas (Android, canal `sense_care/phone` en
/// MainActivity): marca sin abrir el marcador y en altavoz, para que la voz de
/// la app se oiga dentro de la llamada. En otras plataformas no hace nada.
class PhoneCallService {
  static const _channel = MethodChannel('sense_care/phone');

  /// Pide el permiso de llamadas (diálogo del sistema si aún no se concede).
  Future<bool> requestPermission() => _invoke('requestCallPermission');

  /// Marca a [number]. `false` si no hay permiso o el sistema lo rechaza.
  Future<bool> placeCall(String number) =>
      _invoke('placeCall', {'number': number});

  /// Si el teléfono sigue en una llamada (marcando o hablando).
  Future<bool> isInCall() => _invoke('isInCall');

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
