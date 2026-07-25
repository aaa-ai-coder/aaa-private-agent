import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// A collapsible grid of quick-action chips for common device tasks.
class QuickActions extends StatelessWidget {
  final void Function(String command) onSend;
  final bool isDark;

  const QuickActions({
    super.key,
    required this.onSend,
    required this.isDark,
  });

  static const List<_QuickAction> _actions = [
    _QuickAction(icon: Icons.videocam_rounded, label: 'YouTube', command: 'Open YouTube'),
    _QuickAction(icon: Icons.phone_rounded, label: 'Call', command: 'Call Mom'),
    _QuickAction(icon: Icons.alarm_rounded, label: 'Alarm', command: 'Set an alarm for 7 AM'),
    _QuickAction(icon: Icons.visibility_rounded, label: 'Screen', command: 'What\'s on my screen?'),
    _QuickAction(icon: Icons.wb_sunny_rounded, label: 'Volume', command: 'Set volume to 50%'),
    _QuickAction(icon: Icons.message_rounded, label: 'SMS', command: 'Send a text message'),
    _QuickAction(icon: Icons.search_rounded, label: 'Search', command: 'Search Google'),
    _QuickAction(icon: Icons.brightness_6_rounded, label: 'Brightness', command: 'Set brightness to 70%'),
    _QuickAction(icon: Icons.bluetooth_rounded, label: 'Bluetooth', command: 'Turn on Bluetooth'),
    _QuickAction(icon: Icons.wifi_rounded, label: 'WiFi', command: 'Turn on WiFi'),
  ];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(
                Icons.flash_on_rounded,
                size: 12,
                color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
              ),
              const SizedBox(width: 4),
              Text(
                'QUICK ACTIONS',
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
            height: 36,
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
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: isDark
                ? const Color(0xFF151D30)
                : Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isDark
                  ? const Color(0xFF243049).withOpacity(0.4)
                  : const Color(0xFFE2E8F0),
              width: 1.2,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: Theme.of(context).colorScheme.primary),
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
    );
  }
}
