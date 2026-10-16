import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Ponte com o código nativo Android (MainActivity.kt).
/// Todas as chamadas são seguras: se o canal não existir (ex.: testes,
/// outra plataforma) retornam valores padrão em vez de lançar exceção.
class NativeBridge {
  NativeBridge._();

  static const MethodChannel _channel = MethodChannel('unex.vision/native');
  static bool _initialized = false;

  /// Notifica quando o Android entra/sai do modo Picture-in-Picture.
  static final ValueNotifier<bool> isInPip = ValueNotifier<bool>(false);

  static void init() {
    if (_initialized) return;
    _initialized = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'pipChanged') {
        isInPip.value = call.arguments == true;
      }
      return null;
    });
  }

  static Future<T?> _invoke<T>(String method, [dynamic args]) async {
    try {
      return await _channel.invokeMethod<T>(method, args);
    } catch (_) {
      return null;
    }
  }

  // ---- Detecção de dispositivo ----
  static Future<bool?> isTelevision() => _invoke<bool>('isTelevision');

  // ---- Memória ----
  static Future<int> totalRamMb() async =>
      (await _invoke<int>('getTotalRamMb')) ?? 2048;

  // ---- PiP ----
  static Future<bool> isPipSupported() async =>
      (await _invoke<bool>('isPipSupported')) ?? false;

  static Future<void> setPipAllowed(bool allowed) =>
      _invoke<void>('setPipAllowed', {'allowed': allowed});

  static Future<bool> enterPip() async =>
      (await _invoke<bool>('enterPip')) ?? false;

  // ---- Brilho / volume (0.0 a 1.0) ----
  static Future<double> getBrightness() async =>
      (await _invoke<double>('getBrightness')) ?? 0.5;

  static Future<void> setBrightness(double v) =>
      _invoke<void>('setBrightness', {'value': v.clamp(0.0, 1.0)});

  /// Devolve o controle de brilho ao sistema (chamar ao sair do player).
  static Future<void> resetBrightness() => _invoke<void>('resetBrightness');

  static Future<double> getVolume() async =>
      (await _invoke<double>('getVolume')) ?? 0.5;

  static Future<void> setVolume(double v) =>
      _invoke<void>('setVolume', {'value': v.clamp(0.0, 1.0)});

  // ---- Codecs ----
  static Future<bool> hasHardwareDecoder(String mime) async =>
      (await _invoke<bool>('hasDecoder', {'mime': mime})) ?? true;
}
