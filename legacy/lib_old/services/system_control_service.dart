import 'package:volume_controller/volume_controller.dart';
import 'package:screen_brightness/screen_brightness.dart';
import 'package:android_intent_plus/android_intent.dart';

class SystemControlService {
  SystemControlService() {
    // Don't show system volume UI when we control it
    VolumeController().showSystemUI = false;
  }

  /// Set media volume (0-100)
  Future<String> setVolume(int level) async {
    try {
      final volume = (level / 100).clamp(0.0, 1.0);
      VolumeController().setVolume(volume);
      return 'Volume set to $level%';
    } catch (e) {
      return 'Error setting volume: $e';
    }
  }

  /// Set screen brightness (0-100)
  Future<String> setBrightness(int level) async {
    try {
      final brightness = (level / 100).clamp(0.0, 1.0);
      await ScreenBrightness().setScreenBrightness(brightness);
      return 'Brightness set to $level%';
    } catch (e) {
      return 'Error setting brightness: $e';
    }
  }

  /// Non-Root System Setting Launcher (via Android Intent)
  Future<String> openSystemSetting(String setting) async {
    try {
      String action;
      switch (setting.toLowerCase()) {
        case 'wifi':
        case 'wireless':
          action = 'android.settings.WIFI_SETTINGS';
          break;
        case 'bluetooth':
          action = 'android.settings.BLUETOOTH_SETTINGS';
          break;
        case 'display':
        case 'screen':
          action = 'android.settings.DISPLAY_SETTINGS';
          break;
        case 'accessibility':
          action = 'android.settings.ACCESSIBILITY_SETTINGS';
          break;
        case 'notification':
        case 'notifications':
          action = 'android.settings.ACTION_NOTIFICATION_LISTENER_SETTINGS';
          break;
        case 'location':
        case 'gps':
          action = 'android.settings.LOCATION_SOURCE_SETTINGS';
          break;
        case 'apps':
        case 'applications':
          action = 'android.settings.APPLICATION_SETTINGS';
          break;
        case 'battery':
        case 'power':
          action = 'android.settings.BATTERY_SAVER_SETTINGS';
          break;
        case 'sound':
        case 'volume':
          action = 'android.settings.SOUND_SETTINGS';
          break;
        default:
          action = 'android.settings.SETTINGS';
      }

      final intent = AndroidIntent(action: action);
      await intent.launch();
      return 'Opened $setting settings';
    } catch (e) {
      return 'Failed to open $setting settings: $e';
    }
  }

  /// Non-Root Media Control (Play/Pause/Next/Previous via Intent)
  Future<String> controlMedia(String command) async {
    try {
      int keycode;
      switch (command.toLowerCase()) {
        case 'play':
        case 'pause':
        case 'toggle':
          keycode = 85; // KEYCODE_MEDIA_PLAY_PAUSE
          break;
        case 'next':
        case 'skip':
          keycode = 87; // KEYCODE_MEDIA_NEXT
          break;
        case 'previous':
        case 'prev':
          keycode = 88; // KEYCODE_MEDIA_PREVIOUS
          break;
        case 'stop':
          keycode = 86; // KEYCODE_MEDIA_STOP
          break;
        default:
          keycode = 85;
      }

      final intent = AndroidIntent(
        action: 'android.intent.action.MEDIA_BUTTON',
        arguments: {'key_code': keycode},
      );
      await intent.launch();
      return 'Media command "$command" sent successfully';
    } catch (e) {
      return 'Media control error: $e';
    }
  }
}
