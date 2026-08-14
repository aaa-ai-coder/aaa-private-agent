import 'package:flutter/material.dart';

/// Decorative mesh-gradient glows for the chat background.
class HomeBackgroundGlows extends StatelessWidget {
  final bool isDark;

  const HomeBackgroundGlows({super.key, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: Stack(
        children: [
          Positioned(
            top: -150,
            left: -50,
            child: Container(
              width: 400,
              height: 400,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    isDark
                        ? const Color(0xFFFF6B4A).withValues(alpha: 0.22)
                        : const Color(0xFFFF8A5C).withValues(alpha: 0.14),
                    isDark
                        ? const Color(0xFFFF6B4A).withValues(alpha: 0)
                        : const Color(0xFFFF8A5C).withValues(alpha: 0),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            bottom: 50,
            right: -100,
            child: Container(
              width: 350,
              height: 350,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    isDark
                        ? const Color(0xFFFFB86B).withValues(alpha: 0.18)
                        : const Color(0xFFFFB86B).withValues(alpha: 0.12),
                    isDark
                        ? const Color(0xFFFFB86B).withValues(alpha: 0)
                        : const Color(0xFFFFB86B).withValues(alpha: 0),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
