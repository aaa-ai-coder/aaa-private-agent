import 'package:flutter/material.dart';
import 'agent_orb.dart';

/// Compact greeting header: agent orb + time-aware greeting + provider/model.
/// Used at the top of the conversation list and in the empty state.
class HomeHeader extends StatelessWidget {
  final String providerLabel;
  final String model;
  final bool isDark;
  final bool isOnline;

  const HomeHeader({
    super.key,
    required this.providerLabel,
    required this.model,
    required this.isDark,
    this.isOnline = true,
  });

  String get _greeting {
    final time = DateTime.now();
    if (time.hour >= 5 && time.hour < 12) return 'Good morning';
    if (time.hour >= 12 && time.hour < 17) return 'Good afternoon';
    if (time.hour >= 17 && time.hour < 22) return 'Good evening';
    return 'Hello';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 6),
      child: Row(
        children: [
          const AgentOrb(size: 44),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$_greeting, I\'m online',
                  style: TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.3,
                    color: scheme.onSurface,
                  ),
                ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isOnline
                            ? const Color(0xFF34D399)
                            : const Color(0xFFF87171),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        providerLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: scheme.onSurface.withValues(alpha: 0.55),
                        ),
                      ),
                    ),
                    if (model.isNotEmpty) ...[
                      Text(
                        ' · ',
                        style: TextStyle(
                          fontSize: 12,
                          color: scheme.onSurface.withValues(alpha: 0.4),
                        ),
                      ),
                      Flexible(
                        child: Text(
                          model,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: scheme.primary,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
