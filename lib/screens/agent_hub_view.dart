import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/custom_commands_service.dart';
import '../theme/app_theme.dart';
import '../widgets/quick_actions.dart';

/// Agent Hub tab: one-tap quick actions, custom commands, the hands-free voice
/// toggle and shortcuts to the agent's power tools.
class AgentHubView extends StatelessWidget {
  final bool isDark;
  final bool voiceActive;
  final void Function(String text) onSendCommand;
  final List<CustomCommand> customCommands;
  final VoidCallback? onEditCustom;
  final VoidCallback onToggleVoice;
  final VoidCallback onOpenControlPanel;
  final VoidCallback onOpenMemory;
  final VoidCallback onOpenTaskHistory;
  final VoidCallback onOpenPermissions;
  final VoidCallback onOpenDiscover;
  final VoidCallback onOpenAccounts;

  const AgentHubView({
    super.key,
    required this.isDark,
    required this.voiceActive,
    required this.onSendCommand,
    required this.customCommands,
    this.onEditCustom,
    required this.onToggleVoice,
    required this.onOpenControlPanel,
    required this.onOpenMemory,
    required this.onOpenTaskHistory,
    required this.onOpenPermissions,
    required this.onOpenDiscover,
    required this.onOpenAccounts,
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
          'Agent Hub',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w900,
            letterSpacing: -0.3,
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          'One-tap commands, voice mode and agent tools',
          style: TextStyle(fontSize: 12.5, color: subColor),
        ),
        const SizedBox(height: 16),

        // Hands-free voice mode
        Card(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            child: SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text(
                'Hands-Free Voice Mode',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
              subtitle: Text(
                voiceActive
                    ? 'Active — the agent speaks and listens continuously'
                    : 'Turn on to chat with the agent hands-free',
                style: TextStyle(fontSize: 12, color: subColor),
              ),
              secondary: Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: const Color(0xFFFFB86B).withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  voiceActive
                      ? Icons.record_voice_over_rounded
                      : Icons.voice_over_off_rounded,
                  size: 18,
                  color: const Color(0xFFFFB86B),
                ),
              ),
              value: voiceActive,
              onChanged: (val) {
                HapticFeedback.selectionClick();
                onToggleVoice();
              },
            ),
          ),
        ),
        const SizedBox(height: 12),

        Text(
          'Quick Commands',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w800,
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: 8),
        QuickActions(
          onSend: onSendCommand,
          isDark: isDark,
          customCommands: customCommands,
          onEditCustom: onEditCustom,
        ),
        const SizedBox(height: 20),

        Text(
          'Agent Tools',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w800,
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: 10),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 1.55,
          children: [
            _toolTile(
              context,
              icon: Icons.bolt_rounded,
              color: const Color(0xFFFF8A3D),
              label: 'Control Panel',
              onTap: onOpenControlPanel,
            ),
            _toolTile(
              context,
              icon: Icons.psychology_rounded,
              color: const Color(0xFFF65E8B),
              label: 'AI Memory',
              onTap: onOpenMemory,
            ),
            _toolTile(
              context,
              icon: Icons.history_rounded,
              color: const Color(0xFF38A6F5),
              label: 'Task History',
              onTap: onOpenTaskHistory,
            ),
            _toolTile(
              context,
              icon: Icons.verified_user_rounded,
              color: const Color(0xFF2FBF8F),
              label: 'Permissions',
              onTap: onOpenPermissions,
            ),
            _toolTile(
              context,
              icon: Icons.explore_rounded,
              color: const Color(0xFFB86BFF),
              label: 'Discover',
              onTap: onOpenDiscover,
            ),
            _toolTile(
              context,
              icon: Icons.cloud_sync_rounded,
              color: const Color(0xFFFFB020),
              label: 'Accounts',
              onTap: onOpenAccounts,
            ),
          ],
        ),
      ],
    );
  }

  Widget _toolTile(
    BuildContext context, {
    required IconData icon,
    required Color color,
    required String label,
    required VoidCallback onTap,
  }) {
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, size: 18, color: color),
              ),
              const SizedBox(height: 8),
              Text(
                label,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
