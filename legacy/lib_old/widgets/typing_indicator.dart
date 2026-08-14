import 'package:flutter/material.dart';

/// Animated three-dot typing indicator shown while the AI is composing.
class TypingIndicator extends StatefulWidget {
  final Color color;
  final double dotSize;

  const TypingIndicator({
    super.key,
    this.color = const Color(0xFFF65E8B),
    this.dotSize = 6,
  });

  @override
  State<TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<TypingIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (i) {
            // Stagger each dot by a third of the cycle.
            final phase = (_controller.value - i * 0.2);
            final v = (phase % 1.0).clamp(0.0, 1.0);
            final opacity = 0.35 + (0.65 * (1 - (v - 0.5).abs() * 2));
            final scale = 0.7 + (0.5 * (1 - (v - 0.5).abs() * 2));
            return Padding(
              padding: EdgeInsets.only(
                right: i == 2 ? 0 : widget.dotSize * 0.8,
              ),
              child: Transform.scale(
                scale: scale.clamp(0.6, 1.2),
                child: Opacity(
                  opacity: opacity.clamp(0.3, 1.0),
                  child: Container(
                    width: widget.dotSize,
                    height: widget.dotSize,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: widget.color,
                    ),
                  ),
                ),
              ),
            );
          }),
        );
      },
    );
  }
}
