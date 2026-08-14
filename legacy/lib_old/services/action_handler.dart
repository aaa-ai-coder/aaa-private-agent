import 'dart:convert' show utf8;
import '../models/agent_action.dart';
import '../models/chat_message.dart';
import 'app_launcher_service.dart';
import 'contacts_service.dart';
import 'communication_service.dart';
import 'alarm_service.dart';
import 'system_control_service.dart';
import 'shizuku_service.dart';
import 'screen_automation_service.dart';
import 'task_executor.dart';
import 'ai_service.dart';
import 'clipboard_service.dart';
import 'device_info_service.dart';
import 'firebase_service.dart';
import 'storage_service.dart';
import 'qr_decoder.dart';

class ActionHandler {
  final AppLauncherService _appLauncher = AppLauncherService();
  final ContactsService _contacts = ContactsService();
  final CommunicationService _communication = CommunicationService();
  final AlarmService _alarm = AlarmService();
  final SystemControlService _systemControl = SystemControlService();
  final ShizukuService _shizuku = ShizukuService();
  final ScreenAutomationService _screenAutomation = ScreenAutomationService();
  final ClipboardService _clipboard = ClipboardService();
  final DeviceInfoService _deviceInfo = DeviceInfoService();

  ShizukuService get shizuku => _shizuku;
  ScreenAutomationService get screenAutomation => _screenAutomation;

  /// The currently running task executor, if any
  TaskExecutor? _currentExecutor;

  int _parseInt(dynamic val, int defaultValue) {
    if (val == null) return defaultValue;
    if (val is num) return val.toInt();
    if (val is String) return int.tryParse(val) ?? defaultValue;
    return defaultValue;
  }

  /// Execute an action and return the result
  Future<AgentActionResult> execute(
    AgentAction action, {
    AiService? aiService,
    void Function(String)? onProgress,
  }) async {
    try {
      String result;

      switch (action.action) {
        case 'open_app':
          result = await _appLauncher.openApp(
            action.params['app_name'] as String? ?? '',
          );
          break;

        case 'launch_package':
          final packageName = action.params['package_name'] as String? ?? '';
          result = await _appLauncher.openPackage(packageName);
          break;

        case 'make_call':
          result = await _communication.makeCall(
            contactName: action.params['contact_name'] as String?,
            phoneNumber: action.params['phone_number'] as String?,
          );
          break;

        case 'send_sms':
          result = await _communication.sendSms(
            contactName: action.params['contact_name'] as String?,
            phoneNumber: action.params['phone_number'] as String?,
            message: action.params['message'] as String? ?? '',
          );
          break;

        case 'search_contact':
          result = await _contacts.searchAndFormat(
            action.params['query'] as String? ?? '',
          );
          break;

        case 'set_alarm':
          result = await _alarm.setAlarm(
            hour: _parseInt(action.params['hour'], 0),
            minute: _parseInt(action.params['minute'], 0),
            label: action.params['label'] as String?,
          );
          break;

        case 'set_timer':
          result = await _alarm.setTimer(
            seconds: _parseInt(action.params['seconds'], 60),
            label: action.params['label'] as String?,
          );
          break;

        case 'set_volume':
          result = await _systemControl.setVolume(
            _parseInt(action.params['level'], 50),
          );
          break;

        case 'set_brightness':
          result = await _systemControl.setBrightness(
            _parseInt(action.params['level'], 50),
          );
          break;

        case 'open_system_setting':
          result = await _systemControl.openSystemSetting(
            action.params['setting'] as String? ?? 'settings',
          );
          break;

        case 'control_media':
          result = await _systemControl.controlMedia(
            action.params['command'] as String? ?? 'play',
          );
          break;

        case 'run_adb_command':
          result = await _shizuku.runCommand(
            action.params['command'] as String? ?? '',
          );
          break;

        // ─── WiFi & Network Actions ──────────────────────────

        case 'scan_wifi':
          final networks = await _shizuku.scanWifiNetworks();
          result = networks.isNotEmpty
              ? 'Found ${networks.length} networks: ${networks.map((n) => n['info'] ?? n['raw'] ?? '?').join(', ')}'
              : 'No networks found or scan failed.';
          break;

        case 'connect_wifi':
          result = await _shizuku.connectToWifi(
            action.params['ssid'] as String? ?? '',
            action.params['password'] as String? ?? '',
          );
          break;

        case 'connect_saved_wifi':
          result = await _shizuku.connectToSavedNetwork(
            action.params['ssid'] as String? ?? '',
          );
          break;

        case 'connect_best_wifi':
          result = await _shizuku.connectBestSavedNetwork();
          break;

        case 'connect_available_wifi':
          result = await _shizuku.connectBestAvailableNetwork();
          break;

        case 'connect_open_wifi':
          result = await _shizuku.connectToOpenNetwork(
            action.params['ssid'] as String? ?? '',
          );
          break;

        // Recover the password of a network saved on this device, via the
        // saved config, `cmd wifi` detail, or Android's own Share-QR screen.
        case 'reveal_wifi_password':
          result = await _revealWifiPassword(
            action.params['ssid'] as String? ?? '',
          );
          break;

        // On a rooted device: start Shizuku and grant permission automatically.
        case 'setup_shizuku':
          result = await _shizuku.setupShizukuViaRoot();
          break;

        case 'toggle_wifi':
          result = await _shizuku.toggleWifi(
            action.params['enable'] as bool? ?? true,
          );
          break;

        case 'get_current_wifi':
          result = await _shizuku.getCurrentWifi();
          break;

        case 'toggle_mobile_data':
          result = await _shizuku.toggleMobileData(
            action.params['enable'] as bool? ?? true,
          );
          break;

        case 'toggle_bluetooth':
          result = await _shizuku.toggleBluetooth(
            action.params['enable'] as bool? ?? true,
          );
          break;

        // ─── Device Control Actions ──────────────────────────

        case 'set_ringer_mode':
          result = await _shizuku.setRingerMode(
            _parseInt(action.params['mode'], 2),
          );
          break;

        case 'lock_screen':
          result = await _shizuku.lockScreen();
          break;

        case 'wake_screen':
          result = await _shizuku.wakeScreen();
          break;

        case 'go_home':
          result = await _shizuku.goHome();
          break;

        case 'open_recent_apps':
          result = await _shizuku.openRecentApps();
          break;

        case 'toggle_airplane_mode':
          result = await _shizuku.toggleAirplaneMode(
            action.params['enable'] as bool? ?? true,
          );
          break;

        case 'toggle_hotspot':
          result = await _shizuku.toggleHotspot(
            action.params['enable'] as bool? ?? true,
          );
          break;

        case 'toggle_dnd':
          result = await _shizuku.toggleDnd(
            action.params['enable'] as bool? ?? true,
          );
          break;

        case 'set_auto_rotate':
          result = await _shizuku.setAutoRotate(
            action.params['enable'] as bool? ?? true,
          );
          break;

        case 'clear_notifications':
          result = await _shizuku.clearNotifications();
          break;

        case 'get_wifi_password':
          result = await _shizuku.getWifiPassword(
            action.params['ssid'] as String? ?? '',
          );
          break;

        case 'take_screenshot':
          result = await _shizuku.takeScreenshot();
          break;

        case 'force_stop_app':
          result = await _shizuku.forceStopApp(
            action.params['package_name'] as String? ?? '',
          );
          break;

        case 'install_apk':
          result = await _shizuku.installApk(
            action.params['apk_path'] as String? ?? '',
          );
          break;

        case 'uninstall_app':
          result = await _shizuku.uninstallApp(
            action.params['package_name'] as String? ?? '',
          );
          break;

        case 'tap_screen':
          result = await _shizuku.tapScreen(
            _parseInt(action.params['x'], 0),
            _parseInt(action.params['y'], 0),
          );
          break;

        case 'swipe_screen':
          result = await _shizuku.swipeScreen(
            _parseInt(action.params['x1'], 0),
            _parseInt(action.params['y1'], 0),
            _parseInt(action.params['x2'], 0),
            _parseInt(action.params['y2'], 0),
            _parseInt(action.params['duration'], 300),
          );
          break;

        case 'input_text':
          result = await _shizuku.inputText(
            action.params['text'] as String? ?? '',
          );
          break;

        case 'press_key':
          result = await _shizuku.pressKey(
            _parseInt(action.params['keycode'], 4), // Default 4 = BACK
          );
          break;

        case 'get_ui_dump':
          result = await _shizuku.getUiDump();
          break;

        case 'list_installed_apps':
          result = await _shizuku.listInstalledApps();
          break;

        case 'grant_permission':
          result = await _shizuku.grantPermission(
            action.params['package_name'] as String? ?? '',
            action.params['permission'] as String? ?? '',
          );
          break;

        case 'clear_app_data':
          result = await _shizuku.clearAppData(
            action.params['package_name'] as String? ?? '',
          );
          break;

        case 'send_email':
          result = await _communication.sendEmail(
            to: action.params['to'] as String? ?? '',
            subject: action.params['subject'] as String?,
            body: action.params['body'] as String?,
          );
          break;

        case 'open_url':
          result = await _appLauncher.openUrl(
            action.params['url'] as String? ?? '',
          );
          break;

        // ─── Screen Automation Actions ────────────────────────

        case 'read_screen':
          result = await _screenAutomation.getScreenDescription();
          break;

        case 'click_element':
          final text = action.params['text'] as String? ?? '';
          final success = await _screenAutomation.clickByText(text);
          result = success ? 'Clicked "$text"' : 'Could not find "$text" to click';
          break;

        case 'type_on_screen':
          final text = action.params['text'] as String? ?? '';
          final hint = action.params['field_hint'] as String?;
          final success = await _screenAutomation.typeText(text, fieldHint: hint);
          result = success ? 'Typed "$text"' : 'Could not type into field';
          break;

        case 'scroll_screen':
          final direction = action.params['direction'] as String? ?? 'down';
          final success = await _screenAutomation.scroll(direction);
          result = success ? 'Scrolled $direction' : 'Could not scroll';
          break;

        case 'press_back':
          final success = await _screenAutomation.pressBack();
          result = success ? 'Pressed back' : 'Could not press back';
          break;

        // ─── Multi-Step Task Execution ────────────────────────

        case 'execute_task':
          final goal = action.params['goal'] as String? ?? action.response;
          if (aiService == null) {
            result = 'AI service not available for task execution.';
            break;
          }
          if (_currentExecutor != null) {
            result = 'Another task is already running. Wait for it to finish or stop it first.';
            break;
          }
          _currentExecutor = TaskExecutor(
            aiService: aiService,
            screenService: _screenAutomation,
            appLauncher: _appLauncher,
            shizukuService: _shizuku,
            onProgress: onProgress,
          );
          try {
            result = await _currentExecutor!.executeTask(goal);
          } finally {
            _currentExecutor = null;
          }
          break;

        // ─── Non-Root Device Actions ──────────────────────────

        case 'get_device_info':
          final deviceInfo = await _deviceInfo.getDeviceInfo();
          final batteryInfo = await _deviceInfo.getBatteryLevel();
          final storageInfo = await _deviceInfo.getStorageInfo();
          final memInfo = await _deviceInfo.getMemoryInfo();
          result = 'Device: $deviceInfo\nBattery: $batteryInfo\nStorage: $storageInfo\nRAM: $memInfo';
          break;

        case 'copy_clipboard':
          result = await _clipboard.copyToClipboard(
            action.params['text'] as String? ?? '',
          );
          break;

        case 'paste_clipboard':
          result = await _clipboard.pasteFromClipboard();
          break;

        case 'get_battery':
          result = await _deviceInfo.getBatteryLevel();
          break;

        case 'get_memory':
          result = await _deviceInfo.getMemoryInfo();
          break;

        case 'get_storage':
          result = await _deviceInfo.getStorageInfo();
          break;

        // ─── Firebase / Cloud Actions ─────────────────────────

        case 'fcm_subscribe':
          final topic = action.params['topic'] as String? ?? '';
          final success = await FirebaseService.subscribeToTopic(topic);
          result = success
              ? 'Subscribed to topic: $topic'
              : 'Failed to subscribe to topic: $topic';
          break;

        case 'fcm_unsubscribe':
          final topic = action.params['topic'] as String? ?? '';
          final success = await FirebaseService.unsubscribeFromTopic(topic);
          result = success
              ? 'Unsubscribed from topic: $topic'
              : 'Failed to unsubscribe from topic: $topic';
          break;

        case 'list_storage_files':
          final prefix = action.params['prefix'] as String? ?? '';
          final files = await FirebaseService.listStorageFiles(prefix);
          result = files.isNotEmpty
              ? 'Files in "$prefix":\n${files.join('\n')}'
              : 'No files found in "$prefix"';
          break;

        case 'get_storage_url':
          final path = action.params['path'] as String? ?? '';
          final url = await FirebaseService.getStorageUrl(path);
          result = url ?? 'Could not get URL for: $path';
          break;

        case 'save_message_to_cloud':
          final text = action.params['text'] as String? ?? '';
          final label = action.params['label'] as String? ?? 'note';
          final success = await FirebaseService.saveMessageFragment(
            'shared',
            {'text': text, 'label': label},
          );
          result = success
              ? 'Saved message to cloud: "$text"'
              : 'Failed to save message to cloud';
          break;

        // ─── Cloudflare R2 Actions ────────────────────────────

        case 'r2_upload':
          final text = action.params['content'] as String? ?? '';
          final fileName = action.params['file_name'] as String? ?? 'note.txt';
          final folder = action.params['folder'] as String? ?? 'notes';
          final bytes = utf8.encode(text);
          final url = await StorageService.uploadBytes(
            bytes: bytes,
            fileName: fileName,
            folder: folder,
            contentType: 'text/plain',
          );
          result = url != null
              ? 'Uploaded to R2: $url'
              : 'Failed to upload. Is R2 configured?';
          break;

        case 'r2_list':
          final prefix = action.params['prefix'] as String? ?? '';
          final files = await StorageService.listFiles(prefix);
          result = files.isNotEmpty
              ? 'Files in "$prefix":\n${files.join('\n')}'
              : 'No files found in "$prefix"';
          break;

        case 'r2_delete':
          final path = action.params['path'] as String? ?? '';
          final deleted = await StorageService.deleteFile(path);
          result = deleted
              ? 'Deleted: $path'
              : 'Failed to delete: $path';
          break;

        default:
          result = action.response;
      }

      return AgentActionResult(
        actionType: action.action,
        success: true,
        details: result,
      );
    } catch (e) {
      return AgentActionResult(
        actionType: action.action,
        success: false,
        details: 'Error: $e',
      );
    }
  }

  /// Cancel the currently running task
  void cancelTask() {
    _currentExecutor?.cancel();
  }

  /// Recover a saved WiFi network's password from the user's own device.
  /// Tries (1) the WifiConfigStore XML, (2) `cmd wifi get-saved-network`,
  /// then (3) Android's own Share-QR screen via UI automation. Recovered
  /// passwords are cached so the agent can reuse them to connect.
  Future<String> _revealWifiPassword(String ssid) async {
    final name = ssid.trim().replaceAll('"', '');
    if (name.isEmpty) return 'No SSID provided.';
    if (!_shizuku.isAvailable && !_shizuku.isRootAvailable) {
      return 'Root/Shizuku required to read saved WiFi configs.';
    }

    // 1) Config-file route.
    final config = await _shizuku.getWifiPassword(name);
    final configMatch =
        RegExp(r'PreSharedKey[^>]*>\s*([^<\s]+)').firstMatch(config);
    final configPass = configMatch?.group(1);
    if (configPass != null &&
        configPass.isNotEmpty &&
        configPass != '...' &&
        !configPass.contains('Cannot') &&
        !configPass.contains('requires')) {
      await _shizuku.storeRecoveredPassword(name, configPass);
      return 'Recovered from device config. Password for "$name": $configPass';
    }

    // 2) cmd wifi saved-network detail.
    final detail = await _shizuku.getSavedNetworkDetail(name);
    final detailMatch =
        RegExp(r'(?:preSharedKey|PreSharedKey)[^"]*"?\s*([^"<]+)')
            .firstMatch(detail);
    final detailPass = detailMatch?.group(1)?.trim();
    if (detailPass != null &&
        detailPass.isNotEmpty &&
        !detailPass.contains(' ') &&
        !detailPass.contains('unavailable')) {
      await _shizuku.storeRecoveredPassword(name, detailPass);
      return 'Recovered from saved network config. Password for "$name": $detailPass';
    }

    // 3) Android Share-QR route (best effort, device-specific).
    await _systemControl.openSystemSetting('wifi');
    await Future<void>.delayed(const Duration(milliseconds: 1200));
    var opened = await _screenAutomation.clickByText(name);
    if (opened) {
      await Future<void>.delayed(const Duration(milliseconds: 800));
      var tapped = await _screenAutomation.clickByText('Share');
      if (!tapped) {
        tapped = await _screenAutomation.clickByText('QR');
      }
      if (tapped) {
        await Future<void>.delayed(const Duration(milliseconds: 800));
        final path = await _shizuku.screenshotToFile();
        if (path != null) {
          final payload = QrDecoder.decodePngFile(path);
          if (payload != null) {
            final info = QrDecoder.parseWifiQr(payload);
            if (info != null && info.password != null && info.password!.isNotEmpty) {
              await _shizuku.storeRecoveredPassword(info.ssid, info.password!);
              return 'Recovered from Share QR. Password for "${info.ssid}": '
                  '${info.password}';
            }
            return 'QR decoded but it has no recoverable password: $payload';
          }
          return 'Reached the Share-QR screen but decoding failed. '
              'Screenshot saved at: $path';
        }
      }
    }
    return 'Could not recover the password automatically. Open '
        'Settings > WiFi > "$name" > Share and decode the QR with Google Lens.';
  }
}
