import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Discover hub: browse every capability in one place. Tapping a card pops
/// back with a command string that the chat screen immediately sends to the
/// AI agent, so everything the app can do is discoverable and consistent.
class DiscoverScreen extends StatelessWidget {
  const DiscoverScreen({super.key});

  static const List<_CapabilityGroup> _groups = [
    _CapabilityGroup(
      title: 'Voice & Chat',
      icon: Icons.graphic_eq_rounded,
      color: AppColors.indigo,
      items: [
        _Capability(
          icon: Icons.mic_rounded,
          label: 'Start listening',
          subtitle: 'Hands-free voice chat',
          command: 'Start listening',
        ),
        _Capability(
          icon: Icons.notifications_active_rounded,
          label: 'Read notifications',
          subtitle: 'What is on my lock screen?',
          command: 'Read my latest notifications',
        ),
        _Capability(
          icon: Icons.summarize_rounded,
          label: 'Summarize chat',
          subtitle: 'Condense this conversation',
          command: 'Summarize our conversation so far',
        ),
        _Capability(
          icon: Icons.visibility_rounded,
          label: 'What is on screen?',
          subtitle: 'See the current display',
          command: "What's on my screen?",
        ),
      ],
    ),
    _CapabilityGroup(
      title: 'Connectivity',
      icon: Icons.wifi_rounded,
      color: AppColors.info,
      items: [
        _Capability(
          icon: Icons.wifi_find_rounded,
          label: 'Scan Wi-Fi',
          subtitle: 'List nearby networks',
          command: 'Scan available Wi-Fi networks',
        ),
        _Capability(
          icon: Icons.bluetooth_rounded,
          label: 'Bluetooth',
          subtitle: 'Toggle Bluetooth on',
          command: 'Turn on Bluetooth',
        ),
        _Capability(
          icon: Icons.network_cell_rounded,
          label: 'Mobile data',
          subtitle: 'Toggle cellular data',
          command: 'Turn on mobile data',
        ),
        _Capability(
          icon: Icons.wifi_tethering_rounded,
          label: 'Hotspot',
          subtitle: 'Share your connection',
          command: 'Turn on hotspot',
        ),
      ],
    ),
    _CapabilityGroup(
      title: 'Calls & Messages',
      icon: Icons.phone_in_talk_rounded,
      color: AppColors.success,
      items: [
        _Capability(
          icon: Icons.phone_in_talk_rounded,
          label: 'Make a call',
          subtitle: 'Call a saved contact',
          command: 'Make a phone call to Mom',
        ),
        _Capability(
          icon: Icons.sms_rounded,
          label: 'Send SMS',
          subtitle: 'Message any contact',
          command: 'Send an SMS to John saying hello',
        ),
        _Capability(
          icon: Icons.chat_rounded,
          label: 'Open WhatsApp',
          subtitle: 'Chat with someone',
          command: 'Open WhatsApp and send a message',
        ),
      ],
    ),
    _CapabilityGroup(
      title: 'Media & Entertainment',
      icon: Icons.play_circle_fill_rounded,
      color: AppColors.purple,
      items: [
        _Capability(
          icon: Icons.play_circle_fill_rounded,
          label: 'Open YouTube',
          subtitle: 'Watch or search videos',
          command: 'Open YouTube',
        ),
        _Capability(
          icon: Icons.play_arrow_rounded,
          label: 'Play media',
          subtitle: 'Start audio or video',
          command: 'Play media',
        ),
        _Capability(
          icon: Icons.screenshot_monitor_rounded,
          label: 'Screenshot',
          subtitle: 'Capture the screen',
          command: 'Take a screenshot',
        ),
        _Capability(
          icon: Icons.volume_up_rounded,
          label: 'Set volume',
          subtitle: 'Adjust audio level',
          command: 'Set volume to 80%',
        ),
      ],
    ),
    _CapabilityGroup(
      title: 'Device Controls',
      icon: Icons.tune_rounded,
      color: AppColors.warning,
      items: [
        _Capability(
          icon: Icons.alarm_rounded,
          label: 'Set alarm',
          subtitle: 'Wake up on time',
          command: 'Set an alarm for 7 AM',
        ),
        _Capability(
          icon: Icons.timer_rounded,
          label: 'Start timer',
          subtitle: 'Count down anything',
          command: 'Set a 10 minute timer',
        ),
        _Capability(
          icon: Icons.do_not_disturb_rounded,
          label: 'Do Not Disturb',
          subtitle: 'Silence the phone',
          command: 'Turn on Do Not Disturb',
        ),
        _Capability(
          icon: Icons.screen_rotation_rounded,
          label: 'Auto rotate',
          subtitle: 'Toggle rotation lock',
          command: 'Turn on auto rotate',
        ),
        _Capability(
          icon: Icons.phone_android_rounded,
          label: 'Device info',
          subtitle: 'Battery and hardware',
          command: 'Show device info',
        ),
      ],
    ),
    _CapabilityGroup(
      title: 'Productivity',
      icon: Icons.lightbulb_rounded,
      color: AppColors.orange,
      items: [
        _Capability(
          icon: Icons.calculate_rounded,
          label: 'Calculator',
          subtitle: 'Solve anything',
          command: 'What is 384 times 27?',
        ),
        _Capability(
          icon: Icons.email_rounded,
          label: 'Write an email',
          subtitle: 'Draft professional text',
          command: 'Write a professional email',
        ),
        _Capability(
          icon: Icons.psychology_rounded,
          label: 'Brainstorm',
          subtitle: 'Generate fresh ideas',
          command: 'Brainstorm mobile app ideas',
        ),
        _Capability(
          icon: Icons.translate_rounded,
          label: 'Translate',
          subtitle: 'Any language pair',
          command: 'Translate this sentence into Spanish: hello world',
        ),
      ],
    ),
    _CapabilityGroup(
      title: 'Privacy & Recovery',
      icon: Icons.shield_rounded,
      color: AppColors.danger,
      items: [
        _Capability(
          icon: Icons.password_rounded,
          label: 'WiFi passwords',
          subtitle: 'Recover saved networks',
          command: 'Reveal my saved WiFi passwords',
        ),
        _Capability(
          icon: Icons.content_copy_rounded,
          label: 'Read clipboard',
          subtitle: 'Access copied text',
          command: 'Read my clipboard',
        ),
        _Capability(
          icon: Icons.flashlight_on_rounded,
          label: 'Flashlight',
          subtitle: 'Quick light toggle',
          command: 'Turn on flashlight',
        ),
      ],
    ),
    _CapabilityGroup(
      title: 'Quick Settings',
      icon: Icons.toggle_on_rounded,
      color: AppColors.teal,
      items: [
        _Capability(
          icon: Icons.battery_saver_rounded,
          label: 'Battery saver',
          subtitle: 'Conserve battery life',
          command: 'Turn on battery saver',
        ),
        _Capability(
          icon: Icons.location_on_rounded,
          label: 'Location',
          subtitle: 'Toggle GPS service',
          command: 'Turn on location',
        ),
        _Capability(
          icon: Icons.brightness_medium_rounded,
          label: 'Brightness',
          subtitle: 'Set screen level',
          command: 'Set brightness to 70%',
        ),
        _Capability(
          icon: Icons.volume_down_rounded,
          label: 'Silence phone',
          subtitle: 'Mute the ringer',
          command: 'Mute the ringer',
        ),
      ],
    ),
    _CapabilityGroup(
      title: 'Web & AI',
      icon: Icons.language_rounded,
      color: AppColors.info,
      items: [
        _Capability(
          icon: Icons.quiz_rounded,
          label: 'Quick Q&A',
          subtitle: 'Ask anything',
          command: 'Explain black holes in simple terms',
        ),
        _Capability(
          icon: Icons.translate_rounded,
          label: 'Daily briefing',
          subtitle: 'Summarize your day',
          command: 'Give me a short summary of my day so far',
        ),
        _Capability(
          icon: Icons.menu_book_rounded,
          label: 'Learn a topic',
          subtitle: 'Deep dive on anything',
          command: 'Teach me the basics of photography',
        ),
        _Capability(
          icon: Icons.list_alt_rounded,
          label: 'Make a plan',
          subtitle: 'Turn goals into steps',
          command: 'Create a weekly workout plan',
        ),
      ],
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(title: const Text('Discover Capabilities')),
      body: ListView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          // Hero banner
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              gradient: AppGradients.brand,
              borderRadius: BorderRadius.circular(22),
              boxShadow: [
                BoxShadow(
                  color: AppColors.indigo.withValues(alpha: 0.35),
                  blurRadius: 18,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 22),
                    SizedBox(width: 8),
                    Text(
                      'Everything AAA Private Agent can do',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.3,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  'Tap any card to send it to the AI agent instantly.',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.9),
                    fontSize: 12.5,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          for (final group in _groups) ...[
            _sectionLabel(group, isDark),
            const SizedBox(height: 10),
            _capabilityGrid(group),
            const SizedBox(height: 18),
          ],
        ],
      ),
    );
  }

  Widget _sectionLabel(_CapabilityGroup group, bool isDark) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(5),
          decoration: BoxDecoration(
            color: group.color.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(group.icon, size: 14, color: group.color),
        ),
        const SizedBox(width: 8),
        Text(
          group.title.toUpperCase(),
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.2,
            color: isDark ? AppColors.darkText : AppColors.lightText,
          ),
        ),
      ],
    );
  }

  Widget _capabilityGrid(_CapabilityGroup group) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = (constraints.maxWidth - 12) / 2;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final item in group.items)
              SizedBox(
                width: width,
                child: _CapabilityCard(item: item),
              ),
          ],
        );
      },
    );
  }
}

class _Capability {
  final IconData icon;
  final String label;
  final String subtitle;
  final String command;

  const _Capability({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.command,
  });
}

class _CapabilityGroup {
  final String title;
  final IconData icon;
  final Color color;
  final List<_Capability> items;

  const _CapabilityGroup({
    required this.title,
    required this.icon,
    required this.color,
    required this.items,
  });
}

class _CapabilityCard extends StatelessWidget {
  final _Capability item;

  const _CapabilityCard({required this.item});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final scheme = Theme.of(context).colorScheme;

    return Material(
      color: isDark ? AppColors.darkSurface : AppColors.lightSurface,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => Navigator.pop(context, item.command),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
              width: 1.1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [scheme.primary, scheme.tertiary],
                  ),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(item.icon, size: 18, color: Colors.white),
              ),
              const SizedBox(height: 10),
              Text(
                item.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w800,
                  color: isDark ? AppColors.darkText : AppColors.lightText,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                item.subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  color: isDark ? AppColors.darkMuted : AppColors.lightMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
