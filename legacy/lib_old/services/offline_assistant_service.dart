import '../models/agent_action.dart';

/// Result of the offline assistant: either an [action] the app executes, or a
/// plain [reply] text the assistant speaks/shows.
class OfflineResult {
  final AgentAction? action;
  final String reply;

  const OfflineResult({this.action, required this.reply});
}

/// A small, fully on-device assistant that runs without any API key or
/// network. It understands common device-control commands and simple chat,
/// and emits the same [AgentAction] objects the cloud agent uses — so it
/// "merges" with the app's normal AI flow.
class OfflineAssistantService {
  OfflineAssistantService._();

  static const String intro =
      'Offline Assistant ready. I can control this phone (WiFi, Bluetooth, '
      'brightness, volume, alarm, timer, screenshots and more) and answer '
      'simple questions — all without an internet connection or API key. '
      'Try "turn on wifi" or "what time is it?".';

  static OfflineResult handle(String input) {
    final text = input.trim();
    final lower = text.toLowerCase();

    // ── Small talk / simple chat ────────────────────────────────────────
    if (lower.isEmpty) return const OfflineResult(reply: 'I didn\u2019t catch that. Try again?');

    final hi = RegExp(r'^(hi+|hello+|hey+|yo|good (morning|afternoon|evening))\b').hasMatch(lower);
    if (hi) {
      final h = DateTime.now().hour;
      final greeting = h < 12 ? 'Good morning' : (h < 18 ? 'Good afternoon' : 'Good evening');
      return OfflineResult(
        reply: '$greeting! I\u2019m your offline assistant. I can control your phone '
            'and chat with you — no internet or API key needed. Say "help" to see what I can do.',
      );
    }

    if (lower.contains('who are you') || lower.contains('what are you') || lower.contains('your name')) {
      return const OfflineResult(
        reply: 'I\u2019m the built-in Offline Assistant inside AAA Private Agent. '
            'I run entirely on your device, so I keep working even with no signal.',
      );
    }

    if (lower.contains('help') || lower.contains('what can you do') || lower.contains('capabilities')) {
      return const OfflineResult(reply: _help);
    }

    if (lower.contains('thank') || lower.contains('thanks')) {
      return const OfflineResult(reply: 'You\u2019re welcome! Anything else I can do?');
    }

    if (lower.contains('how are you') || lower.contains('how do you feel')) {
      return const OfflineResult(reply: 'Running smoothly on your device. How can I help?');
    }

    // ── Time & date (pure info, no action needed) ───────────────────────
    final timeMatch = RegExp(r'what.*(time)|current time|what time').hasMatch(lower);
    if (timeMatch) {
      final now = DateTime.now();
      final h = now.hour.toString().padLeft(2, '0');
      final m = now.minute.toString().padLeft(2, '0');
      return OfflineResult(reply: 'It\u2019s $h:$m.');
    }

    final dateMatch = RegExp(r'what.*(date|day)').hasMatch(lower);
    if (dateMatch) {
      const weekdays = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
      const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
      final now = DateTime.now();
      return OfflineResult(
        reply: 'Today is ${weekdays[now.weekday - 1]}, ${now.day} ${months[now.month - 1]} ${now.year}.',
      );
    }

    // ── Device control ──────────────────────────────────────────────────
    // Brightness
    final brightMatch = RegExp(r'brightness.*?(\d{1,3})|(\d{1,3}).*?brightness').firstMatch(lower);
    if (brightMatch != null) {
      final level = int.tryParse(brightMatch.group(1) ?? brightMatch.group(2) ?? '')?.clamp(0, 100) ?? 50;
      return OfflineResult(
        action: AgentAction(
          action: 'set_brightness',
          params: {'level': level},
          response: 'Setting screen brightness to $level%.',
        ),
        reply: 'Setting brightness to $level%.',
      );
    }

    // Volume
    final volMatch = RegExp(r'volume.*?(\d{1,3})|(\d{1,3}).*?volume').firstMatch(lower);
    if (volMatch != null) {
      final level = int.tryParse(volMatch.group(1) ?? volMatch.group(2) ?? '')?.clamp(0, 100) ?? 50;
      return OfflineResult(
        action: AgentAction(
          action: 'set_volume',
          params: {'level': level},
          response: 'Setting media volume to $level%.',
        ),
        reply: 'Setting volume to $level%.',
      );
    }

    // WiFi
    if (lower.contains('wifi') || lower.contains('wi-fi') || lower.contains('wireless')) {
      final enable = _booleanFor(lower);
      if (enable != null) {
        return OfflineResult(
          action: AgentAction(
            action: 'toggle_wifi',
            params: {'enable': enable},
            response: enable ? 'Turning WiFi on.' : 'Turning WiFi off.',
          ),
          reply: enable ? 'Turning WiFi on.' : 'Turning WiFi off.',
        );
      }
    }

    // Bluetooth
    if (lower.contains('bluetooth')) {
      final enable = _booleanFor(lower);
      if (enable != null) {
        return OfflineResult(
          action: AgentAction(
            action: 'toggle_bluetooth',
            params: {'enable': enable},
            response: enable ? 'Turning Bluetooth on.' : 'Turning Bluetooth off.',
          ),
          reply: enable ? 'Turning Bluetooth on.' : 'Turning Bluetooth off.',
        );
      }
    }

    // Airplane mode
    if (lower.contains('airplane') || lower.contains('flight mode')) {
      final enable = _booleanFor(lower);
      if (enable != null) {
        return OfflineResult(
          action: AgentAction(
            action: 'toggle_airplane_mode',
            params: {'enable': enable},
            response: enable ? 'Enabling airplane mode.' : 'Disabling airplane mode.',
          ),
          reply: enable ? 'Enabling airplane mode.' : 'Disabling airplane mode.',
        );
      }
    }

    // Hotspot
    if (lower.contains('hotspot') || lower.contains('tethering')) {
      final enable = _booleanFor(lower);
      if (enable != null) {
        return OfflineResult(
          action: AgentAction(
            action: 'toggle_hotspot',
            params: {'enable': enable},
            response: enable ? 'Turning hotspot on.' : 'Turning hotspot off.',
          ),
          reply: enable ? 'Turning hotspot on.' : 'Turning hotspot off.',
        );
      }
    }

    // Mobile data
    if (lower.contains('mobile data') || lower.contains('cellular data')) {
      final enable = _booleanFor(lower);
      if (enable != null) {
        return OfflineResult(
          action: AgentAction(
            action: 'toggle_mobile_data',
            params: {'enable': enable},
            response: enable ? 'Turning mobile data on.' : 'Turning mobile data off.',
          ),
          reply: enable ? 'Turning mobile data on.' : 'Turning mobile data off.',
        );
      }
    }

    // Do Not Disturb
    if (lower.contains('do not disturb') || lower.contains('dnd')) {
      final enable = _booleanFor(lower);
      if (enable != null) {
        return OfflineResult(
          action: AgentAction(
            action: 'toggle_dnd',
            params: {'enable': enable},
            response: enable ? 'Enabling Do Not Disturb.' : 'Disabling Do Not Disturb.',
          ),
          reply: enable ? 'Enabling Do Not Disturb.' : 'Disabling Do Not Disturb.',
        );
      }
    }

    // Auto rotate
    if (lower.contains('auto rotate') || lower.contains('rotate')) {
      final enable = _booleanFor(lower);
      if (enable != null) {
        return OfflineResult(
          action: AgentAction(
            action: 'set_auto_rotate',
            params: {'enable': enable},
            response: enable ? 'Enabling auto-rotate.' : 'Disabling auto-rotate.',
          ),
          reply: enable ? 'Enabling auto-rotate.' : 'Disabling auto-rotate.',
        );
      }
    }

    // Ringer mode
    if (lower.contains('silent') || lower.contains('mute') || lower.contains('vibrate') || lower.contains('ringer')) {
      if (lower.contains('silent') || lower.contains('mute')) {
        return OfflineResult(
          action: AgentAction(
            action: 'set_ringer_mode',
            params: {'mode': 2},
            response: 'Setting phone to silent.',
          ),
          reply: 'Setting phone to silent.',
        );
      }
      if (lower.contains('vibrate')) {
        return OfflineResult(
          action: AgentAction(
            action: 'set_ringer_mode',
            params: {'mode': 1},
            response: 'Setting phone to vibrate.',
          ),
          reply: 'Setting phone to vibrate.',
        );
      }
    }

    // Media control
    if (lower.contains('pause')) {
      return _media('pause');
    }
    if (lower.contains('play') || lower.contains('resume')) {
      return _media('play');
    }
    if (lower.contains('next track') || lower.contains('skip')) {
      return _media('next');
    }
    if (lower.contains('previous') || lower.contains('previous track')) {
      return _media('previous');
    }

    // Alarm
    final alarmMatch = RegExp(r'(?:set|make).{0,12}?alarm.{0,20}?(\d{1,2})[:.](\d{2})')
        .firstMatch(lower);
    if (alarmMatch != null) {
      final hour = int.parse(alarmMatch.group(1)!) % 24;
      final minute = int.parse(alarmMatch.group(2)!) % 60;
      return OfflineResult(
        action: AgentAction(
          action: 'set_alarm',
          params: {'hour': hour, 'minute': minute, 'label': 'Alarm'},
          response: 'Setting alarm for ${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}.',
        ),
        reply: 'Setting alarm for ${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}.',
      );
    }

    // Timer
    final timerMatch = RegExp(r'(?:set|start).{0,12}?timer.{0,12}?(\d+)\s*(seconds?|minutes?|min|sec|s|m)')
        .firstMatch(lower);
    if (timerMatch != null) {
      final amount = int.parse(timerMatch.group(1)!);
      final unit = timerMatch.group(2)!;
      final seconds = unit.startsWith('m') ? amount * 60 : amount;
      return OfflineResult(
        action: AgentAction(
          action: 'set_timer',
          params: {'seconds': seconds, 'label': 'Timer'},
          response: 'Starting a $amount ${unit.startsWith('m') ? 'minute' : 'second'} timer.',
        ),
        reply: 'Starting a $amount ${unit.startsWith('m') ? 'minute' : 'second'} timer.',
      );
    }

    // Open app
    final openApp = RegExp(r'open (?:the )?(?:app )?(.+)').firstMatch(lower);
    if (openApp != null && !lower.contains('setting')) {
      final app = openApp.group(1)!.trim();
      if (_looksLikeAppName(app)) {
        return OfflineResult(
          action: AgentAction(
            action: 'open_app',
            params: {'app_name': app},
            response: 'Opening $app.',
          ),
          reply: 'Opening $app.',
        );
      }
    }

    // Screenshot
    if (lower.contains('screenshot') || lower.contains('capture') || lower.contains('screen shot')) {
      return const OfflineResult(
        action: AgentAction(
          action: 'take_screenshot',
          params: {},
          response: 'Taking a screenshot.',
        ),
        reply: 'Taking a screenshot.',
      );
    }

    // Lock screen
    if (lower.contains('lock') && (lower.contains('screen') || lower.contains('phone') || lower.contains('device'))) {
      return const OfflineResult(
        action: AgentAction(
          action: 'lock_screen',
          params: {},
          response: 'Locking the screen.',
        ),
        reply: 'Locking the screen.',
      );
    }

    // Wake screen
    if (lower.contains('wake') || lower.contains('turn on screen')) {
      return const OfflineResult(
        action: AgentAction(
          action: 'wake_screen',
          params: {},
          response: 'Waking the screen.',
        ),
        reply: 'Waking the screen.',
      );
    }

    // Go home
    if (lower.contains('go home') || lower.contains('home screen')) {
      return const OfflineResult(
        action: AgentAction(
          action: 'go_home',
          params: {},
          response: 'Going to the home screen.',
        ),
        reply: 'Going to the home screen.',
      );
    }

    // Open system settings
    final settingMatch = RegExp(r'(open|go to).{0,8}?(wifi|bluetooth|display|battery|sound|notifications|location|accessibility) settings')
        .firstMatch(lower);
    if (settingMatch != null) {
      final setting = settingMatch.group(2)!;
      return OfflineResult(
        action: AgentAction(
          action: 'open_system_setting',
          params: {'setting': setting},
          response: 'Opening $setting settings.',
        ),
        reply: 'Opening $setting settings.',
      );
    }

    // Battery
    if (lower.contains('battery')) {
      return const OfflineResult(
        action: AgentAction(
          action: 'get_battery',
          params: {},
          response: 'Reading battery status.',
        ),
        reply: 'Reading battery status.',
      );
    }

    // Device info
    if (lower.contains('device info') || lower.contains('about my phone') || lower.contains('phone model')) {
      return const OfflineResult(
        action: AgentAction(
          action: 'get_device_info',
          params: {},
          response: 'Reading device info.',
        ),
        reply: 'Reading device info.',
      );
    }

    // ── Fallback ─────────────────────────────────────────────────────────
    return OfflineResult(
      reply: 'I\u2019m running offline, so I can handle device commands and simple '
          'questions only. Try "help" to see my full list, or switch back to the '
          'online AI in Settings for deeper answers. Here\u2019s what I understood: '
          '"$text"',
    );
  }

  static OfflineResult _media(String command) {
    return OfflineResult(
      action: AgentAction(
        action: 'control_media',
        params: {'command': command},
        response: command == 'play' ? 'Playing media.' : command == 'pause' ? 'Pausing media.' : 'Skipping.',
      ),
      reply: command == 'play' ? 'Playing media.' : command == 'pause' ? 'Pausing media.' : 'Skipping.',
    );
  }

  static bool? _booleanFor(String lower) {
    if (RegExp(r'\b(off|disable|disable it|turn off)\b').hasMatch(lower)) return false;
    if (RegExp(r'\b(on|enable|enable it|turn on)\b').hasMatch(lower)) return true;
    return null;
  }

  static bool _looksLikeAppName(String s) {
    if (s.isEmpty || s.length > 40) return false;
    if (RegExp(r'\b(please|now|quickly)\b').hasMatch(s)) return false;
    return true;
  }

  static const String _help =
      'I can do these offline:\n\n'
      'WiFi / Bluetooth / Hotspot / Mobile data / Airplane mode — "turn on wifi"\n'
      'Do Not Disturb — "enable do not disturb"\n'
      'Brightness — "set brightness to 50"\n'
      'Volume — "set volume to 70"\n'
      'Silent / Vibrate — "silent mode"\n'
      'Media — "pause", "play", "next track"\n'
      'Alarm — "set alarm for 7:30"\n'
      'Timer — "set a 5 minute timer"\n'
      'Open apps — "open YouTube"\n'
      'System settings — "open wifi settings"\n'
      'Screenshot — "take a screenshot"\n'
      'Lock / wake screen, go home\n'
      'Battery & device info\n'
      'Time & date, simple chat\n\n'
      'For anything smarter, enable the online AI in Settings.';
}
