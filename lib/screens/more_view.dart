import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../utils/app_info.dart';

/// "More" tab: a beautiful menu of everything else — settings, accounts,
/// discovery, task history, memory, permissions and about.
class MoreView extends StatelessWidget {
  final bool isDark;
  final VoidCallback onOpenSettings;
  final VoidCallback onOpenAccounts;
  final VoidCallback onOpenDiscover;
  final VoidCallback onOpenTaskHistory;
  final VoidCallback onOpenMemory;
  final VoidCallback onOpenPermissions;
  final VoidCallback onOpenControlPanel;
  final VoidCallback onOpenAbout;

  const MoreView({
    super.key,
    required this.isDark,
    required this.onOpenSettings,
    required this.onOpenAccounts,
    required this.onOpenDiscover,
    required this.onOpenTaskHistory,
    required this.onOpenMemory,
    required this.onOpenPermissions,
    required this.onOpenControlPanel,
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
          icon: Icons.cloud_sync_rounded,
          color: const Color(0xFF38A6F5),
          title: 'Accounts & Sync',
          subtitle: 'Sign in, cloud sync and API key backup',
          onTap: onOpenAccounts,
        ),
        _menuItem(
          context,
          icon: Icons.explore_rounded,
          color: const Color(0xFFB86BFF),
          title: 'Discover Capabilities',
          subtitle: 'Everything the agent can do on your phone',
          onTap: onOpenDiscover,
        ),
        _menuItem(
          context,
          icon: Icons.history_rounded,
          color: const Color(0xFF2FBF8F),
          title: 'Task History',
          subtitle: 'Completed tasks and multi-step runs',
          onTap: onOpenTaskHistory,
        ),
        _menuItem(
          context,
          icon: Icons.psychology_rounded,
          color: const Color(0xFFF65E8B),
          title: 'AI Memory',
          subtitle: 'Facts the assistant remembers about you',
          onTap: onOpenMemory,
        ),
        _menuItem(
          context,
          icon: Icons.verified_user_rounded,
          color: const Color(0xFFB86BFF),
          title: 'Permissions & Access',
          subtitle: 'Shizuku, automation and overlay access',
          onTap: onOpenPermissions,
        ),
        _menuItem(
          context,
          icon: Icons.bolt_rounded,
          color: const Color(0xFFFFB020),
          title: 'Control Panel',
          subtitle: 'Advanced device controls and toggles',
          onTap: onOpenControlPanel,
        ),
        _menuItem(
          context,
          icon: Icons.info_outline_rounded,
          color: const Color(0xFF38A6F5),
          title: 'About & What\u2019s New',
          subtitle: 'Version, changelog and credits',
          onTap: onOpenAbout,
        ),
      ],
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
