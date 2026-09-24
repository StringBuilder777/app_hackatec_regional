import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

/// Voz de la app (texto a voz en español): anuncia la alerta en el teléfono y
/// explica la situación durante la llamada automática.
class VoiceService {
  /// Topes: si el motor de voz falla o se reconecta, flutter_tts deja en
  /// espera cualquier método (hasta `stop`) y nunca responde.
  static const _maxSpeech = Duration(seconds: 60);
  static const _maxStop = Duration(seconds: 2);

  final FlutterTts _tts = FlutterTts();
  late final Future<void> _setup;

  VoiceService() {
    // Prepara el motor desde el arranque: la primera frase suele ser urgente.
    _setup = _configure()..ignore();
  }

  Future<void> _configure() async {
    await _tts.awaitSpeakCompletion(true);
    for (final lang in const ['es-MX', 'es-US', 'es-ES']) {
      if (await _tts.isLanguageAvailable(lang) == true) {
        await _tts.setLanguage(lang);
        break;
      }
    }
    // Un poco más lenta que la normal: se entiende mejor por teléfono.
    await _tts.setSpeechRate(0.45);
    await _tts.setVolume(1.0);
  }

  /// Dice [text] y espera a que termine; corta lo que se estuviera diciendo
  /// (flutter_tts descarta una frase nueva si otra sigue sonando). Nunca
  /// lanza: sin voz, la llamada sigue igual.
  Future<void> speak(String text) async {
    try {
      await _setup.timeout(const Duration(seconds: 10));
      await _tts.stop().timeout(_maxStop);
      await _tts.speak(text).timeout(_maxSpeech);
    } catch (e) {
      debugPrint('Voz no disponible: $e');
    }
  }

  Future<void> stop() async {
    try {
      await _tts.stop().timeout(_maxStop);
    } catch (e) {
      debugPrint('Voz no disponible: $e');
    }
  }
}
