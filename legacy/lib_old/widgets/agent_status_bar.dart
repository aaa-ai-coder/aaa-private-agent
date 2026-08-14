import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Compact dashboard strip on the home screen: shows the active AI provider,
/// the current model, and one-tap access to the full Accounts & Cloud Health
/// screen with the backend status dots.
class AgentStatusBar extends StatelessWidget {
  final String providerName;
  final String model;
  final bool r2Configured;
  final bool cloudSynced;
  final VoidCallback onOpenHealth;
  final bool isDark;

  const AgentStatusBar({
    super.key,
    required this.providerName,
    required this.model,
    required this.r2Configured,
    required this.cloudSynced,
    required this.onOpenHealth,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Material(
        color: isDark ? const Color(0xFF1B1A33) : Colors.white,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onOpenHealth,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: isDark
                    ? AppColors.darkBorder
                    : AppColors.lightBorder,
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    gradient: AppGradients.brand,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.smart_toy_rounded,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        providerName,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 13.5,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        model,
                        style: TextStyle(
                          fontSize: 11.5,
                          color: isDark
                              ? AppColors.darkMuted
                              : AppColors.lightMuted,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                _StatusDot(
                  icon: Icons.cloud_rounded,
                  ok: r2Configured,
                  tooltip: 'R2 storage ${r2Configured ? 'configured' : 'not configured'}',
                  isDark: isDark,
                ),
                const SizedBox(width: 8),
                _StatusDot(
                  icon: Icons.sync_rounded,
                  ok: cloudSynced,
                  tooltip: cloudSynced ? 'Cloud sync active' : 'Signed out',
                  isDark: isDark,
                ),
                const SizedBox(width: 4),
                Icon(
                  Icons.chevron_right_rounded,
                  size: 18,
                  color: isDark ? AppColors.darkMuted : AppColors.lightMuted,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StatusDot extends StatelessWidget {
  final IconData icon;
  final bool ok;
  final String tooltip;
  final bool isDark;

  const _StatusDot({
    required this.icon,
    required this.ok,
    required this.tooltip,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: (ok ? AppColors.success : Colors.grey).withValues(alpha: 0.15),
          shape: BoxShape.circle,
        ),
        child: Icon(
          icon,
          size: 14,
          color: ok ? AppColors.success : (isDark ? AppColors.darkMuted : Colors.grey),
        ),
      ),
    );
  }
}
