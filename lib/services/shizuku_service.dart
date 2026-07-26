import 'dart:developer';
import 'package:shizuku_api/shizuku_api.dart';

class ShizukuService {
  final ShizukuApi _shizuku = ShizukuApi();
  bool _isAvailable = false;
  bool _hasPermission = false;

  bool get isAvailable => _isAvailable;
  bool get hasPermission => _hasPermission;

  /// Check if Shizuku is installed and running
  Future<bool> checkAvailability() async {
    try {
      _isAvailable = await _shizuku.pingBinder() ?? false;
      if (_isAvailable) {
        _hasPermission = await _shizuku.checkPermission() ?? false;
      }
      return _isAvailable;
    } catch (e) {
      _isAvailable = false;
      _hasPermission = false;
      return false;
    }
  }

  /// Request Shizuku permission
  Future<bool> requestPermission() async {
    if (!_isAvailable) return false;
    try {
      _hasPermission = await _shizuku.requestPermission() ?? false;
      return _hasPermission;
    } catch (e) {
      return false;
    }
  }

  /// Run an ADB shell command via Shizuku
  Future<String> runCommand(String command) async {
    if (!_isAvailable) {
      return 'Shizuku is not running. Please start Shizuku first.';
    }
    if (!_hasPermission) {
      final granted = await requestPermission();
      if (!granted) {
        return 'Shizuku permission denied.';
      }
    }

    try {
      final result = await _shizuku.runCommand(command);
      return result ?? 'Command executed (no output)';
    } catch (e) {
      return 'Error running command: $e';
    }
  }

  // ─── Network Management ────────────────────────────────────────

  /// Toggle WiFi on/off
  Future<String> toggleWifi(bool enable) async {
    return runCommand('svc wifi ${enable ? 'enable' : 'disable'}');
  }

  /// Toggle mobile data on/off
  Future<String> toggleMobileData(bool enable) async {
    return runCommand('svc data ${enable ? 'enable' : 'disable'}');
  }

  /// Toggle Bluetooth on/off
  Future<String> toggleBluetooth(bool enable) async {
    return runCommand(
      'cmd bluetooth_manager ${enable ? 'enable' : 'disable'}',
    );
  }

  /// Get currently connected WiFi SSID
  Future<String> getCurrentWifi() async {
    final result = await runCommand(
      'cmd wifi get-connection-state 2>/dev/null || '
      'dumpsys wifi | grep "mNetworkInfo" | grep "SSID"',
    );
    return result;
  }

  /// Scan for available WiFi networks
  Future<List<Map<String, String>>> scanWifiNetworks() async {
    // Trigger a scan and get results
    await runCommand('cmd wifi start-scan 2>/dev/null');
    await Future.delayed(const Duration(seconds: 2));
    
    final result = await runCommand(
      'cmd wifi list-networks 2>/dev/null || '
      'dumpsys wifi | grep -E "SSID|BSSID|signal" 2>/dev/null || '
      'echo "NO_STANDARD_OUTPUT"',
    );
    
    if (result.contains('NO_STANDARD_OUTPUT') || result.contains('Error')) {
      // Fallback: parse dumpsys output
      final dump = await runCommand(
        'dumpsys wifi | grep -A 1 "ScanResult" | head -60',
      );
      return [{'raw': dump}];
    }
    
    // Parse the output into a list of networks
    final List<Map<String, String>> networks = [];
    final lines = result.split('\n');
    for (final line in lines) {
      if (line.trim().isNotEmpty && !line.contains('Error')) {
        networks.add({'info': line.trim()});
      }
    }
    return networks;
  }

  /// Get saved WiFi password for a known SSID (requires root or Shizuku)
  Future<String> getWifiPassword(String ssid) async {
    final result = await runCommand(
      'cat /data/misc/wifi/WifiConfigStore.xml 2>/dev/null | '
      'grep -A 10 "$ssid" | grep "PreSharedKey" || '
      'cmd wifi get-saved-network "$ssid" 2>/dev/null || '
      'echo "Password extraction requires root or Shizuku"',
    );
    return result;
  }

  /// Connect to a WiFi network
  Future<String> connectToWifi(String ssid, String password) async {
    // Create a WiFi network configuration via cmd wifi
    final result = await runCommand(
      'cmd wifi connect-network "$ssid" wpa2 "$password" 2>/dev/null || '
      'cmd wifi add-network "$ssid" 2>/dev/null || '
      'echo "Failed to connect. Try using Settings > WiFi manually."',
    );
    return result;
  }

  /// Enable/disable mobile data
  Future<String> setMobileData(bool enable) async {
    return runCommand('svc data ${enable ? 'enable' : 'disable'}');
  }

  // ─── Device Control ────────────────────────────────────────────

  /// Force stop an app by package name
  Future<String> forceStopApp(String packageName) async {
    return runCommand('am force-stop $packageName');
  }

  /// Clear app data
  Future<String> clearAppData(String packageName) async {
    return runCommand('pm clear $packageName');
  }

  /// Set ringer mode: 0=silent, 1=vibrate, 2=normal
  Future<String> setRingerMode(int mode) async {
    final modeStr = mode == 0 ? 'silent' : (mode == 1 ? 'vibrate' : 'normal');
    return runCommand('cmd audio set-ringer-mode $modeStr 2>/dev/null || '
        'settings put system volume_ring $mode');
  }

  /// Toggle flashlight via camera service
  Future<String> toggleFlashlight(bool enable) async {
    return runCommand(
      'cmd battery $enable 2>/dev/null; '
      'echo "Flashlight control requires system-level access"',
    );
  }

  /// Set screen brightness (0-255)
  Future<String> setScreenBrightness(int brightness) async {
    final clamped = brightness.clamp(0, 255);
    return runCommand('settings put system screen_brightness $clamped');
  }

  /// Lock the device screen
  Future<String> lockScreen() async {
    return runCommand('input keyevent KEYCODE_POWER');
  }

  /// Take a screenshot (saves to /sdcard/)
  Future<String> takeScreenshot() async {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    return runCommand(
      'screencap -p /sdcard/screenshot_$timestamp.png',
    );
  }

  /// Install an APK from a file path
  Future<String> installApk(String apkPath) async {
    return runCommand('pm install -r "$apkPath"');
  }

  /// Uninstall an app by package name
  Future<String> uninstallApp(String packageName) async {
    return runCommand('pm uninstall "$packageName"');
  }

  // ─── Screen & UI Automation ─────────────────────────────────────

  /// Tap at screen coordinates (x, y)
  Future<String> tapScreen(int x, int y) async {
    return runCommand('input tap $x $y');
  }

  /// Swipe from (x1, y1) to (x2, y2) over duration in ms
  Future<String> swipeScreen(int x1, int y1, int x2, int y2, [int durationMs = 300]) async {
    return runCommand('input swipe $x1 $y1 $x2 $y2 $durationMs');
  }

  /// Input text into the currently focused text field
  Future<String> inputText(String text) async {
    final escaped = text.replaceAll(' ', '%s').replaceAll('"', '\\"');
    return runCommand('input text "$escaped"');
  }

  /// Press Android physical key (e.g., 3=HOME, 4=BACK, 26=POWER, 187=APP_SWITCH)
  Future<String> pressKey(int keycode) async {
    return runCommand('input keyevent $keycode');
  }

  /// Get XML dump of current UI layout
  Future<String> getUiDump() async {
    return runCommand('uiautomator dump /sdcard/window_dump.xml && cat /sdcard/window_dump.xml');
  }

  /// List all third-party installed apps
  Future<String> listInstalledApps() async {
    return runCommand('pm list packages -3');
  }

  /// Grant permission to an app
  Future<String> grantPermission(String packageName, String permission) async {
    return runCommand('pm grant $packageName $permission');
  }
}
