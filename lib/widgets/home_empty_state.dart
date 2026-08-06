import 'package:flutter/material.dart';
import 'agent_orb.dart';

/// Redesigned empty-state: glowing agent orb, gradient greeting, and
/// suggestion chips with gradient icons.
class HomeEmptyState extends StatelessWidget {
  final String mode;
  final bool isDark;
  final void Function(String text) onSend;

  const HomeEmptyState({
    super.key,
    required this.mode,
    required this.isDark,
    required this.onSend,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final time = DateTime.now();
    String greeting;
    if (time.hour >= 5 && time.hour < 12) {
      greeting = 'Good morning.';
    } else if (time.hour >= 12 && time.hour < 17) {
      greeting = 'Good afternoon.';
    } else if (time.hour >= 17 && time.hour < 22) {
      greeting = 'Good evening.';
    } else {
      greeting = 'Hello.';
    }

    final suggestions = mode == 'chat'
        ? [
            'Write a professional email',
            'Explain quantum computing simply',
            'Brainstorm mobile app ideas',
            'Write a poem about robots',
          ]
        : [
            'Open YouTube and search for cats',
            'Call Mom',
            'Set volume to 80%',
            "What's on my screen?",
          ];

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        child: Column(
          children: [
            const SizedBox(height: 14),
            const AgentOrb(size: 76),
            const SizedBox(height: 22),
            Text(
              greeting,
              style: TextStyle(
                fontSize: 30,
                fontWeight: FontWeight.w300,
                color: scheme.onSurface.withValues(alpha: 0.55),
                letterSpacing: -1.5,
                height: 1.1,
              ),
            ),
            const SizedBox(height: 4),
            ShaderMask(
              shaderCallback: (bounds) => const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF22D3EE), Color(0xFF8B5CF6)],
              ).createShader(bounds),
              child: Text(
                'How can I help you?',
                style: TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                  letterSpacing: -1.5,
                  height: 1.2,
                ),
              ),
            ),
            const SizedBox(height: 36),
            Align(
              alignment: Alignment.centerLeft,
              child: Row(
                children: [
                  Icon(
                    Icons.auto_awesome_rounded,
                    size: 13,
                    color: scheme.primary,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'SUGGESTIONS',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: scheme.onSurface.withValues(alpha: 0.6),
                      letterSpacing: 1.5,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 52,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                itemCount: suggestions.length,
                itemBuilder: (context, index) {
                  final suggestion = suggestions[index];
                  return Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: InkWell(
                      onTap: () => onSend(suggestion),
                      borderRadius: BorderRadius.circular(16),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 12),
                        decoration: BoxDecoration(
                          color: isDark
                              ? const Color(0xFF151430)
                              : Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: isDark
                                ? const Color(0xFF8B5CF6).withValues(alpha: 0.3)
                                : const Color(0xFFE2E8F0),
                            width: 1.2,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(
                                  alpha: isDark ? 0.15 : 0.03),
                              blurRadius: 8,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: Center(
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.bolt_rounded,
                                size: 14,
                                color: const Color(0xFF8B5CF6),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                suggestion,
                                style: TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w600,
                                  color: isDark
                                      ? const Color(0xFFF8FAFC)
                                      : const Color(0xFF1E293B),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
