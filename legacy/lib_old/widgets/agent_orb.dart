import 'package:flutter/material.dart';

/// Reusable "agent orb" — a warm sunrise orb with a soft halo, used as the
/// brand avatar across the app (header, empty state, message bubbles).
class AgentOrb extends StatelessWidget {
  final double size;
  final bool glow;

  const AgentOrb({super.key, this.size = 40, this.glow = true});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFFFFB86B),
            Color(0xFFFF6B4A),
            Color(0xFFF65E8B),
          ],
        ),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.5),
          width: 1.4,
        ),
        boxShadow: glow
            ? [
                BoxShadow(
                  color: const Color(0xFFFF6B4A).withValues(alpha: 0.45),
                  blurRadius: size * 0.55,
                  spreadRadius: size * 0.12,
                ),
              ]
            : null,
      ),
      child: Center(
        child: Container(
          width: size * 0.38,
          height: size * 0.38,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white,
          ),
          child: Center(
            child: Container(
              width: size * 0.18,
              height: size * 0.18,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFFFFB86B), Color(0xFFFF6B4A)],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
