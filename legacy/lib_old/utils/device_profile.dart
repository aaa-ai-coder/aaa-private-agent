import 'package:device_info_plus/device_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Device capability detection used to keep the app smooth on low-end phones
/// (e.g. Samsung Galaxy A30: Exynos 7885, 4 GB RAM, 720p display).
class DeviceProfile {
  DeviceProfile._();

  /// Preferred visual effects mode, stored in SharedPreferences:
  /// 'auto' (default — effects on, off automatically on weak phones), 'on' or 'off'.
  static const String prefVisualEffects = 'visual_effects_mode';

  static bool? _lowEndCached;

  /// True when the device reports at most 4 GB of RAM.
  static Future<bool> isLowEndDevice() async {
    if (_lowEndCached != null) return _lowEndCached!;
    var lowEnd = false;
    try {
      final info = await DeviceInfoPlugin().androidInfo;
      lowEnd = info.physicalRamSize <= 4096;
    } catch (_) {
      lowEnd = false;
    }
    _lowEndCached = lowEnd;
    return lowEnd;
  }

  /// Effective visual-effects mode after applying the user override and the
  /// automatic low-end fallback. Returns 'on' or 'off'.
  static Future<String> effectiveVisualMode() async {
    final prefs = await SharedPreferences.getInstance();
    final mode = prefs.getString(prefVisualEffects) ?? 'auto';
    if (mode != 'auto') return mode;
    return (await isLowEndDevice()) ? 'off' : 'on';
  }

  /// Whether expensive background effects (mesh glows, full-screen blur) should
  /// be painted on this device right now.
  static Future<bool> visualsEnabled() async =>
      (await effectiveVisualMode()) == 'on';
}
