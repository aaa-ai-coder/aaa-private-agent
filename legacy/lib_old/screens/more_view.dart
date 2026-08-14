import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_theme.dart';
import '../utils/app_info.dart';

/// "More" tab: the things that don't belong to the Agent Hub tools grid —
/// settings, conversation actions and app info. Nothing here duplicates the
/// Agent Hub tab, so every tab stays focused and discoverable.
class MoreView extends StatelessWidget {
  final bool isDark;
  final VoidCallback onOpenSettings;
  final VoidCallback onExportChat;
  final VoidCallback onNewChat;
  final VoidCallback onShareApp;
  final VoidCallback onOpenAbout;

  const MoreView({
    super.key,
    required this.isDark,
    required this.onOpenSettings,
    required this.onExportChat,
    required this.onNewChat,
    required this.onShareApp,
    required this.onOpenAbout,
  });

  @override
  Widget build(BuildContext context) {
    final subColor =
        isDark ? const Color(0xFFA8938C) : const Color(0xFF6B5A52);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        const SizedBox(height: 4),
        Text(
          'More',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w900,
            letterSpacing: -0.3,
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          '$kAppName v$kAppVersion · $kAppTagline Edition',
          style: TextStyle(fontSize: 12.5, color: subColor),
        ),
        const SizedBox(height: 16),

        _sectionTitle(context, 'Quick Actions'),
        const SizedBox(height: 8),
        _menuItem(
          context,
          icon: Icons.settings_rounded,
          color: const Color(0xFFFF8A5C),
          title: 'Settings',
          subtitle: 'AI providers, offline AI, voice, backup & more',
          onTap: onOpenSettings,
        ),
        _menuItem(
          context,
          icon: Icons.ios_share_rounded,
          color: const Color(0xFF38A6F5),
          title: 'Export Chat',
          subtitle: 'Save the current conversation to a text file',
          onTap: onExportChat,
        ),
        _menuItem(
          context,
          icon: Icons.add_comment_rounded,
          color: const Color(0xFF2FBF8F),
          title: 'New Chat',
          subtitle: 'Clear this conversation and start fresh',
          onTap: onNewChat,
        ),
        _menuItem(
          context,
          icon: Icons.share_rounded,
          color: const Color(0xFFB86BFF),
          title: 'Share the App',
          subtitle: 'Invite someone to try AAA Private Agent',
          onTap: onShareApp,
        ),
        const SizedBox(height: 18),

        _sectionTitle(context, 'About'),
        const SizedBox(height: 8),
        _menuItem(
          context,
          icon: Icons.info_outline_rounded,
          color: const Color(0xFF38A6F5),
          title: 'About & What\u2019s New',
          subtitle: 'Version $kAppVersion, changelog and credits',
          onTap: onOpenAbout,
        ),
        const SizedBox(height: 20),

        Card(
          color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.08),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: Theme.of(context)
                        .colorScheme
                        .primary
                        .withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.auto_awesome_rounded,
                    size: 18,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Tip: Open the Agent Hub tab for one-tap commands, '
                    'custom actions and hands-free voice.',
                    style: TextStyle(fontSize: 12.5, height: 1.4, color: subColor),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _sectionTitle(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.8,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }

  Widget _menuItem(
    BuildContext context, {
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    final subColor =
        isDark ? const Color(0xFFA8938C) : const Color(0xFF6B5A52);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Card(
        child: InkWell(
          borderRadius: BorderRadius.circular(22),
          onTap: () {
            HapticFeedback.selectionClick();
            onTap();
          },
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, size: 20, color: color),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: TextStyle(fontSize: 11.5, color: subColor),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  color: subColor.withValues(alpha: 0.6),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
