import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:shizuku_api/shizuku_api.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ShizukuService {
  final ShizukuApi _shizuku = ShizukuApi();
  bool _isAvailable = false;
  bool _hasPermission = false;
  bool _rootAvailable = false;

  /// Maximum time a binder command may run before it is treated as failed.
  /// Prevents a wedged binder call from freezing the whole task loop.
  static const _commandTimeout = Duration(seconds: 10);

  bool get isAvailable => _isAvailable;
  bool get hasPermission => _hasPermission;

  /// Whether the device is rooted (or has an app with root access, e.g.
  /// Magisk granting this app). When true, privileged commands can run via
  /// `su` even if Shizuku is unavailable.
  bool get isRootAvailable => _rootAvailable;

  /// Probe whether `su` (root shell) is usable from this app.
  Future<bool> _probeRoot() async {
    try {
      final result = await Process.run('su', ['-c', 'echo ok'])
          .timeout(const Duration(seconds: 3));
      _rootAvailable = result.exitCode == 0;
    } catch (_) {
      _rootAvailable = false;
    }
    return _rootAvailable;
  }

  /// Check if Shizuku is installed and running (also refreshes root status).
  Future<bool> checkAvailability() async {
    try {
      _isAvailable = await _shizuku.pingBinder() ?? false;
      if (_isAvailable) {
        _hasPermission = await _shizuku.checkPermission() ?? false;
      } else {
        _hasPermission = false;
      }
      await _probeRoot();
      return _isAvailable;
    } catch (e) {
      _isAvailable = false;
      _hasPermission = false;
      await _probeRoot();
      return _isAvailable;
    }
  }

  /// Request Shizuku permission
  Future<bool> requestPermission() async {
    if (!_isAvailable) {
      await checkAvailability();
    }
    if (!_isAvailable) return false;
    try {
      _hasPermission = await _shizuku.requestPermission() ?? false;
      return _hasPermission;
    } catch (e) {
      return false;
    }
  }

  /// Run a privileged command via the `su` root shell.
  Future<String> _runAsRoot(String command) async {
    try {
      final result = await Process.run('su', ['-c', command]).timeout(
        _commandTimeout,
        onTimeout: () => throw TimeoutException('Root command timed out'),
      );
      if (result.exitCode == 0) {
        final out = (result.stdout as String).trim();
        return out.isEmpty ? 'Command executed (no output)' : out;
      }
      return 'Root command failed (exit ${result.exitCode}): ${result.stderr}';
    } catch (e) {
      return 'Error running root command: $e';
    }
  }

  /// Run an ADB shell command via Shizuku (or root fallback).
  ///
  /// Automatically re-checks Shizuku connectivity before giving up, and falls
  /// back to the root shell when Shizuku is unavailable or its permission is
  /// denied, so privileged actions keep working on both rooted and
  /// non-rooted devices.
  Future<String> runCommand(String command) async {
    // Shizuku may have been started after this app launched: re-check first.
    if (!_isAvailable) {
      await checkAvailability();
    }

    if (_isAvailable) {
      if (!_hasPermission) {
        final granted = await requestPermission();
        if (!granted) {
          if (_rootAvailable) return _runAsRoot(command);
          return 'Shizuku permission denied.';
        }
      }

      try {
        final result = await _shizuku.runCommand(command).timeout(
          _commandTimeout,
          onTimeout: () => throw TimeoutException('Command timed out'),
        );
        return result ?? 'Command executed (no output)';
      } catch (e) {
        // Binder may have died mid-command: try the root shell as fallback.
        if (_rootAvailable) return _runAsRoot(command);
        return 'Error running command: $e';
      }
    }

    if (_rootAvailable) return _runAsRoot(command);
    return 'Shizuku is not running. Please start Shizuku first.';
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

  /// Connect to an already-saved network by SSID — no password needed, the
  /// device already stored it. Tries a direct connect, then resolves the saved
  /// network id and connects by id as a fallback.
  Future<String> connectToSavedNetwork(String ssid) async {
    final name = ssid.trim().replaceAll('"', '');
    if (name.isEmpty) return 'No SSID provided.';
    if (!_isAvailable && !_rootAvailable) {
      return 'Shizuku/root not available. Cannot read saved networks.';
    }
    await runCommand('svc wifi enable');
    final direct = await runCommand('cmd wifi connect-network "$name"');
    if (!_looksLikeFailure(direct)) return direct;
    final id = await _findSavedNetworkId(name);
    if (id == null) {
      return 'Network "$name" is not saved on this device, or saved networks '
          'cannot be read without root/Shizuku.';
    }
    final byId = await runCommand('cmd wifi connect-network $id');
    if (!_looksLikeFailure(byId)) return byId;
    final wpa = await runCommand(
      'wpa_cli -i wlan0 enable_network $id 2>/dev/null && '
      'wpa_cli -i wlan0 select_network $id 2>/dev/null || echo ""',
    );
    return wpa.trim().isEmpty
        ? 'Connected attempt via network id $id ($byId)'
        : wpa;
  }

  /// List all saved (known) WiFi network names.
  Future<List<String>> listSavedNetworks() async {
    final list = await runCommand('cmd wifi list-networks 2>/dev/null');
    final networks = <String>[];
    for (final line in list.split('\n')) {
      final parts = line.trim().split(RegExp(r'\s+'));
      if (parts.length < 2) continue;
      if (int.tryParse(parts[0]) != null) {
        final name = parts[1].replaceAll('"', '');
        if (name.isNotEmpty && name != 'SSID') networks.add(name);
      }
    }
    return networks;
  }

  /// Scan for in-range network names.
  Future<List<String>> scanInRangeNetworks() async {
    await runCommand('cmd wifi start-scan');
    await Future<void>.delayed(const Duration(seconds: 2));
    final out = await runCommand(
      'cmd wifi list-scan-results 2>/dev/null || '
      'dumpsys wifi | grep "SSID:" 2>/dev/null || echo "NO_SCAN"',
    );
    if (out.contains('NO_SCAN') || out.contains('Error')) return [];
    final names = <String>{};
    for (final line in out.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      final mac = RegExp(r'([0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}')
          .firstMatch(trimmed);
      if (mac != null) {
        final name = trimmed
            .substring(0, mac.start)
            .replaceAll('"', '')
            .trim();
        if (name.isNotEmpty && name.toLowerCase() != 'ssid') {
          names.add(name);
        }
      } else if (trimmed.contains('SSID:"')) {
        final quoted = RegExp(r'SSID:"([^"]+)"').firstMatch(trimmed);
        if (quoted != null) names.add(quoted.group(1)!);
      }
    }
    return names.toList();
  }

  /// Fully autonomous: connect to the best saved network currently in range.
  /// No password is required from the user — the device already knows it.
  Future<String> connectBestSavedNetwork() async {
    if (!_isAvailable && !_rootAvailable) {
      return 'Shizuku/root not available. Cannot auto-connect WiFi.';
    }
    await runCommand('svc wifi enable');
    final saved = await listSavedNetworks();
    if (saved.isEmpty) {
      return 'No saved WiFi networks found (or saved networks cannot be read '
          'without root/Shizuku).';
    }
    final inRange = await scanInRangeNetworks();
    if (inRange.isEmpty) {
      return 'WiFi is on, but no in-range scan results were returned. '
          'Saved networks: ${saved.join(', ')}';
    }
    String? target;
    for (final s in saved) {
      if (inRange.contains(s)) {
        target = s;
        break;
      }
    }
    if (target == null) {
      return 'No saved network is currently in range.\nIn range: '
          '${inRange.join(', ')}\nSaved: ${saved.join(', ')}';
    }
    final connectResult = await connectToSavedNetwork(target);
    final status = await runCommand('cmd wifi get-connection-state 2>/dev/null');
    return 'Auto-connected to saved network "$target".\n$connectResult\n'
        'Connection state: $status';
  }

  /// Scan in-range networks together with whether each is open (no password).
  Future<List<Map<String, String>>> scanNetworksWithSecurity() async {
    await runCommand('cmd wifi start-scan');
    await Future<void>.delayed(const Duration(seconds: 2));
    final out = await runCommand(
      'cmd wifi list-scan-results 2>/dev/null || echo "NO_SCAN"',
    );
    final networks = <Map<String, String>>[];
    if (out.contains('NO_SCAN') || out.contains('Error')) return networks;
    for (final line in out.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      final mac =
          RegExp(r'([0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}').firstMatch(trimmed);
      if (mac == null) continue;
      final name = trimmed.substring(0, mac.start).replaceAll('"', '').trim();
      if (name.isEmpty || name.toLowerCase() == 'ssid') continue;
      final secured = trimmed.contains(RegExp(
        r'WPA|WEP|SAE|PSK|ENTERPRISE|802.1X',
        caseSensitive: false,
      ));
      networks.add({'ssid': name, 'open': secured ? 'false' : 'true'});
    }
    return networks;
  }

  /// Connect to an open (password-less) WiFi network.
  Future<String> connectToOpenNetwork(String ssid) async {
    final name = ssid.trim().replaceAll('"', '');
    if (name.isEmpty) return 'No SSID provided.';
    await runCommand('svc wifi enable');
    final direct = await runCommand('cmd wifi connect-network "$name" open');
    if (!_looksLikeFailure(direct)) return direct;
    return 'Could not connect to open network "$name": $direct';
  }

  /// Fully autonomous "get me online": prefer a saved network in range, else
  /// connect to the best open (password-less) network. Never asks the user
  /// for a password.
  Future<String> connectBestAvailableNetwork() async {
    if (!_isAvailable && !_rootAvailable) {
      return 'Shizuku/root not available. Cannot auto-connect WiFi.';
    }
    await runCommand('svc wifi enable');
    final saved = await listSavedNetworks();
    final inRange = await scanNetworksWithSecurity();
    if (inRange.isEmpty) {
      return 'WiFi is on but no in-range networks were returned.\n'
          'Saved networks: ${saved.isEmpty ? 'none' : saved.join(', ')}';
    }
    final inRangeNames = inRange.map((n) => n['ssid']!).toSet();

    // 1) Best saved network currently in range.
    for (final s in saved) {
      if (inRangeNames.contains(s)) {
        final r = await connectToSavedNetwork(s);
        return 'Auto-connected to saved network "$s".\n$r';
      }
    }

    // 2) Otherwise the best open network (brand-new, no password needed).
    final open = inRange.where((n) => n['open'] == 'true').toList();
    if (open.isNotEmpty) {
      final target = open.first['ssid']!;
      final r = await connectToOpenNetwork(target);
      return 'No saved network in range; connected to open network "$target".\n$r';
    }

    // 3) Secured brand-new networks the AI has already recovered a password
    //    for (via the Share-QR or saved-config route).
    final recovered = await allRecoveredPasswords();
    if (recovered.isNotEmpty) {
      for (final n in inRange) {
        final pass = recovered[n['ssid']];
        if (pass != null && pass.isNotEmpty) {
          final r = await connectToWifi(n['ssid']!, pass);
          return 'Connected to secured network "${n['ssid']}" using a '
              'previously recovered password.\n$r';
        }
      }
    }

    return 'No saved network is in range and no open networks were found.\n'
        'In range (secured networks need their password): '
        '${inRangeNames.join(', ')}';
  }

  bool _looksLikeFailure(String result) {
    final lower = result.toLowerCase();
    return lower.contains('error') ||
        lower.contains('failed') ||
        lower.contains('exception') ||
        lower.contains('not supported');
  }

  /// Resolve the network id of a saved network from `cmd wifi list-networks`.
  Future<int?> _findSavedNetworkId(String ssid) async {
    final list = await runCommand('cmd wifi list-networks 2>/dev/null');
    for (final line in list.split('\n')) {
      final parts = line.trim().split(RegExp(r'\s+'));
      if (parts.length < 2) continue;
      final id = int.tryParse(parts[0]);
      final name = parts[1].replaceAll('"', '');
      if (id != null && name == ssid) return id;
    }
    return null;
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

  /// Lock the device screen
  Future<String> lockScreen() async {
    return runCommand('input keyevent KEYCODE_POWER');
  }

  /// Wake the screen (does not unlock)
  Future<String> wakeScreen() async {
    return runCommand('input keyevent KEYCODE_WAKEUP');
  }

  /// Go to the launcher home screen
  Future<String> goHome() async {
    return runCommand('input keyevent KEYCODE_HOME');
  }

  /// Open the recent-apps overview
  Future<String> openRecentApps() async {
    return runCommand('input keyevent KEYCODE_APP_SWITCH');
  }

  /// Toggle airplane mode (needs WRITE_SECURE_SETTINGS / root)
  Future<String> toggleAirplaneMode(bool enable) async {
    final onOff = enable ? '1' : '0';
    return runCommand(
      'settings put global airplane_mode_on $onOff && '
      'am broadcast -a android.intent.action.AIRPLANE_MODE --ez state $enable',
    );
  }

  /// Best-effort toggle for the portable Wi-Fi hotspot.
  Future<String> toggleHotspot(bool enable) async {
    return runCommand(
      'cmd wifi ${enable ? 'start' : 'stop'}-hotspot 2>/dev/null || '
      'echo "Hotspot toggle not supported on this Android version."',
    );
  }

  /// Toggle Do Not Disturb (zen mode). 1=off, 2=total silence.
  Future<String> toggleDnd(bool enable) async {
    return runCommand('settings put global zen_mode ${enable ? '2' : '0'}');
  }

  /// Enable/disable auto-rotate using the accelerometer.
  Future<String> setAutoRotate(bool enable) async {
    return runCommand(
      'settings put system accelerometer_rotation ${enable ? '1' : '0'}',
    );
  }

  /// Clear all active notifications.
  Future<String> clearNotifications() async {
    return runCommand('cmd notification cancel_all 2>/dev/null || '
        'service call notification 1 i32 0 2>/dev/null || '
        'echo "Could not clear notifications."');
  }

  /// Take a screenshot (saves to /sdcard/)
  Future<String> takeScreenshot() async {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    return runCommand(
      'screencap -p /sdcard/screenshot_$timestamp.png',
    );
  }

  /// Take a screenshot and return the saved file path (or null on failure).
  Future<String?> screenshotToFile() async {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final path = '/sdcard/screenshot_$timestamp.png';
    final result = await runCommand('screencap -p $path');
    if (_looksLikeFailure(result)) return null;
    return path;
  }

  /// Best-effort: dump a saved network's full config (some Android builds
  /// include the preSharedKey here even when the XML store is encrypted).
  Future<String> getSavedNetworkDetail(String ssid) async {
    final id = await _findSavedNetworkId(ssid);
    if (id == null) return 'Network "$ssid" is not saved on this device.';
    return runCommand(
      'cmd wifi get-saved-network $id 2>/dev/null || '
      'echo "Saved network details unavailable on this build."',
    );
  }

  // ─── Recovered password store ───────────────────────────────────
  // Passwords the AI recovers from the user's own saved configs or the
  // Android Share QR screen are cached locally so the agent can reuse them to
  // connect without ever asking the user.

  Future<Map<String, String>> allRecoveredPasswords() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('wifi_recovered') ?? '{}';
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      return decoded.map((k, v) => MapEntry(k, v.toString()));
    } catch (_) {
      return {};
    }
  }

  Future<String?> getRecoveredPassword(String ssid) async {
    final all = await allRecoveredPasswords();
    return all[ssid];
  }

  Future<void> storeRecoveredPassword(String ssid, String password) async {
    final prefs = await SharedPreferences.getInstance();
    final all = await allRecoveredPasswords();
    all[ssid] = password;
    await prefs.setString('wifi_recovered', jsonEncode(all));
  }

  Future<void> removeRecoveredPassword(String ssid) async {
    final prefs = await SharedPreferences.getInstance();
    final all = await allRecoveredPasswords();
    all.remove(ssid);
    await prefs.setString('wifi_recovered', jsonEncode(all));
  }

  // ─── Self setup via root ────────────────────────────────────────

  /// On a rooted device, start the Shizuku server and grant this app
  /// permission automatically so no manual Shizuku setup is required.
  Future<String> setupShizukuViaRoot() async {
    if (!_rootAvailable) {
      await checkAvailability();
    }
    if (!_rootAvailable) {
      return 'Root is not available. To use Shizuku without root, enable it '
          'once over ADB (see Settings > Shizuku), or grant root access.';
    }
    final steps = <String>[];
    // 1) Start the Shizuku server from its data dir (rooted path).
    final start = await _runAsRoot(
      'sh /sdcard/Android/data/moe.shizuku.privileged.api/start.sh 2>/dev/null || '
      'sh /data/local/tmp/shizuku/start.sh 2>/dev/null || '
      'echo "START_SCRIPT_MISSING"',
    );
    if (start.contains('START_SCRIPT_MISSING')) {
      steps.add('Shizuku app not installed - install it first, then retry.');
    } else {
      steps.add('Shizuku server started: ${start.trim().replaceAll('\n', ' ')}');
    }
    await Future<void>.delayed(const Duration(milliseconds: 800));

    // 2) Grant this app the Shizuku binder permission via appops (root).
    final grant = await _runAsRoot(
      'cmd appops set com.aaa.privateagent SHIZUKU_USER allow 2>/dev/null || '
      'appops set com.aaa.privateagent SHIZUKU_USER allow 2>/dev/null || '
      'echo "GRANT_FAILED"',
    );
    if (grant.contains('GRANT_FAILED')) {
      steps.add('Could not auto-grant permission (no root appops access).');
    } else {
      steps.add('Permission granted to com.aaa.privateagent.');
    }

    // 3) Refresh binder state.
    await checkAvailability();
    steps.add(_isAvailable
        ? 'Shizuku is now available (permission: $_hasPermission).'
        : 'Shizuku still not reachable - try launching the Shizuku app once.');
    return steps.join('\n');
  }

  /// Root fallback for the SHIZUKU_USER appops grant, used by the app itself.
  Future<bool> selfGrantShizukuPermission() async {
    final result = await _runAsRoot(
      'cmd appops set com.aaa.privateagent SHIZUKU_USER allow 2>/dev/null || '
      'appops set com.aaa.privateagent SHIZUKU_USER allow',
    );
    await checkAvailability();
    return _hasPermission || !_looksLikeFailure(result);
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
