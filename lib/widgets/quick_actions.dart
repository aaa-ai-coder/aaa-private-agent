import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// A sleek, glassmorphic horizontal list of quick action chips for the AI Agent.
class QuickActions extends StatelessWidget {
  final void Function(String command) onSend;
  final bool isDark;

  const QuickActions({
    super.key,
    required this.onSend,
    required this.isDark,
  });

  static const List<_QuickAction> _actions = [
    _QuickAction(icon: Icons.graphic_eq_rounded, label: 'Voice Chat', command: 'Start listening'),
    _QuickAction(icon: Icons.wifi_find_rounded, label: 'Scan Wi-Fi', command: 'Scan available Wi-Fi networks'),
    _QuickAction(icon: Icons.play_circle_fill_rounded, label: 'YouTube', command: 'Open YouTube'),
    _QuickAction(icon: Icons.phone_in_talk_rounded, label: 'Call', command: 'Make a phone call'),
    _QuickAction(icon: Icons.alarm_rounded, label: 'Alarm', command: 'Set an alarm for 7 AM'),
    _QuickAction(icon: Icons.timer_rounded, label: 'Timer', command: 'Set a 10 minute timer'),
    _QuickAction(icon: Icons.chat_rounded, label: 'WhatsApp', command: 'Open WhatsApp and send a message'),
    _QuickAction(icon: Icons.notifications_active_rounded, label: 'Read Notifs', command: 'Read my latest notifications'),
    _QuickAction(icon: Icons.bluetooth_rounded, label: 'Bluetooth', command: 'Turn on Bluetooth'),
    _QuickAction(icon: Icons.volume_off_rounded, label: 'Mute', command: 'Mute the ringer'),
    _QuickAction(icon: Icons.screenshot_monitor_rounded, label: 'Screenshot', command: 'Take a screenshot'),
    _QuickAction(icon: Icons.battery_charging_full_rounded, label: 'Battery', command: 'Show battery and device info'),
    _QuickAction(icon: Icons.flash_on_rounded, label: 'Flashlight', command: 'Turn on flashlight'),
    _QuickAction(icon: Icons.play_arrow_rounded, label: 'Media Play', command: 'Play media'),
    _QuickAction(icon: Icons.translate_rounded, label: 'Translate', command: 'Translate this sentence into Spanish: hello world'),
    _QuickAction(icon: Icons.content_copy_rounded, label: 'Clipboard', command: 'Read my clipboard'),
    _QuickAction(icon: Icons.calculate_rounded, label: 'Calculator', command: 'What is 384 times 27?'),
    _QuickAction(icon: Icons.share_rounded, label: 'Export Chat', command: 'Export this chat session'),
    _QuickAction(icon: Icons.summarize_rounded, label: 'Summarize', command: 'Summarize our conversation so far'),
    _QuickAction(icon: Icons.phone_android_rounded, label: 'Device Info', command: 'Show device info'),
    _QuickAction(icon: Icons.password_rounded, label: 'WiFi Pass', command: 'Reveal my saved WiFi passwords'),
  ];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: const Color(0xFF8B5CF6).withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.auto_awesome_rounded,
                  size: 11,
                  color: Color(0xFFA78BFA),
                ),
              ),
              const SizedBox(width: 6),
              Text(
                'QUICK COMMANDS',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.2,
                  color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 38,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              itemCount: _actions.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final action = _actions[index];
                return _ActionChip(
                  icon: action.icon,
                  label: action.label,
                  isDark: isDark,
                  onTap: () {
                    HapticFeedback.lightImpact();
                    onSend(action.command);
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _QuickAction {
  final IconData icon;
  final String label;
  final String command;
  const _QuickAction({
    required this.icon,
    required this.label,
    required this.command,
  });
}

class _ActionChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isDark;
  final VoidCallback onTap;

  const _ActionChip({
    required this.icon,
    required this.label,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final primary = isDark ? const Color(0xFFA78BFA) : const Color(0xFF7C3AED);
    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1B4B).withValues(alpha: 0.4) : const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark ? const Color(0xFF8B5CF6).withValues(alpha: 0.2) : const Color(0xFFCBD5E1),
          width: 1.0,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          splashColor: primary.withValues(alpha: 0.15),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 14, color: primary),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: isDark ? const Color(0xFFF8FAFC) : const Color(0xFF1E293B),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
