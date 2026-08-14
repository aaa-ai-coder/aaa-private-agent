import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Glassmorphic bottom input bar with pulsing voice mic, live status badge, and send button.
class HomeInputBar extends StatefulWidget {
  final TextEditingController controller;
  final bool isListening;
  final bool isLoading;
  final bool isDark;
  final VoidCallback onMicTap;
  final ValueChanged<String> onSend;
  final ValueChanged<String>? onTyped;

  const HomeInputBar({
    super.key,
    required this.controller,
    required this.isListening,
    required this.isLoading,
    required this.isDark,
    required this.onMicTap,
    required this.onSend,
    this.onTyped,
  });

  @override
  State<HomeInputBar> createState() => _HomeInputBarState();
}

class _HomeInputBarState extends State<HomeInputBar> with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    if (widget.isListening) {
      _pulseController.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(HomeInputBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isListening && !oldWidget.isListening) {
      _pulseController.repeat(reverse: true);
    } else if (!widget.isListening && oldWidget.isListening) {
      _pulseController.stop();
      _pulseController.reset();
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final primaryColor = widget.isDark ? const Color(0xFFFF8A5C) : const Color(0xFFFF6B4A);

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.transparent,
            widget.isDark
                ? const Color(0xFF171015).withValues(alpha: 0.96)
                : Colors.white.withValues(alpha: 0.96),
          ],
        ),
        border: Border(
          top: BorderSide(
            color: primaryColor.withValues(alpha: widget.isDark ? 0.25 : 0.15),
            width: 0.8,
          ),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Live status badge if listening or loading
          if (widget.isListening || widget.isLoading)
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: widget.isListening
                    ? Colors.redAccent.withValues(alpha: 0.15)
                    : primaryColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: widget.isListening
                      ? Colors.redAccent.withValues(alpha: 0.4)
                      : primaryColor.withValues(alpha: 0.4),
                  width: 1.0,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: widget.isListening ? Colors.redAccent : primaryColor,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    widget.isListening
                        ? 'Listening... Speak now'
                        : 'AI Agent is thinking & executing...',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: widget.isListening
                          ? Colors.redAccent
                          : (widget.isDark ? const Color(0xFFFF9A6B) : const Color(0xFFC2503A)),
                    ),
                  ),
                ],
              ),
            ),

          Row(
            children: [
              // Pulsing Voice Mic Button
              AnimatedBuilder(
                animation: _pulseController,
                builder: (context, child) {
                  final scale = 1.0 + (_pulseController.value * 0.12);
                  return Transform.scale(
                    scale: scale,
                    child: Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: widget.isListening
                            ? null
                            : const LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [
                                  Color(0xFFFF8A5C),
                                  Color(0xFFF65E8B),
                                ],
                              ),
                        color: widget.isListening ? Colors.redAccent : null,
                        border: Border.all(
                          color: widget.isListening
                              ? Colors.redAccent
                              : primaryColor.withValues(alpha: 0.45),
                          width: 1.4,
                        ),
                        boxShadow: [
                          if (widget.isListening)
                            BoxShadow(
                              color: Colors.redAccent.withValues(alpha: 0.5 * _pulseController.value),
                              blurRadius: 16,
                              spreadRadius: 4,
                            )
                          else
                            BoxShadow(
                              color: Colors.black.withValues(alpha: widget.isDark ? 0.3 : 0.05),
                              blurRadius: 8,
                              offset: const Offset(0, 3),
                            ),
                        ],
                      ),
                      child: IconButton(
                        icon: Icon(
                          widget.isListening ? Icons.mic_rounded : Icons.mic_none_rounded,
                          color: widget.isListening ? Colors.white : primaryColor,
                        ),
                        onPressed: widget.isLoading
                            ? null
                            : () {
                                HapticFeedback.mediumImpact();
                                widget.onMicTap();
                              },
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(width: 10),

              // Text Input Container
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: widget.isDark
                        ? const Color(0xFF241B21)
                        : Colors.white,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: widget.isDark
                          ? const Color(0xFFFF8A5C).withValues(alpha: 0.3)
                          : const Color(0xFFF0E3D3),
                      width: 1.2,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFFFF6B4A).withValues(alpha: widget.isDark ? 0.12 : 0.08),
                        blurRadius: 14,
                        offset: const Offset(0, 4),
                      ),
                      BoxShadow(
                        color: Colors.black.withValues(alpha: widget.isDark ? 0.3 : 0.04),
                        blurRadius: 10,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: widget.controller,
                          style: TextStyle(
                            fontSize: 14,
                            color: widget.isDark ? Colors.white : const Color(0xFF2E1F1A),
                          ),
                          decoration: InputDecoration(
                            hintText: widget.isListening
                                ? 'Listening...'
                                : 'Type anything or ask AI to execute...',
                            hintStyle: TextStyle(
                              fontSize: 13,
                              color: widget.isDark
                                  ? const Color(0xFFA8938C)
                                  : const Color(0xFF8C7A6E),
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 18, vertical: 12),
                            border: InputBorder.none,
                          ),
                          textInputAction: TextInputAction.send,
                          onChanged: widget.onTyped,
                          onSubmitted: widget.isLoading
                              ? null
                              : (text) => widget.onSend(text),
                        ),
                      ),

                      // Send Button
                      Container(
                        margin: const EdgeInsets.only(right: 6),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: const LinearGradient(
                            colors: [
                              Color(0xFFFF6B4A),
                              Color(0xFFF65E8B),
                              Color(0xFFFF8A5C),
                            ],
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFFF65E8B).withValues(alpha: 0.45),
                              blurRadius: 10,
                              spreadRadius: 1,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: IconButton(
                          icon: const Icon(Icons.arrow_upward_rounded,
                              size: 17, color: Colors.white),
                          onPressed: widget.isLoading
                              ? null
                              : () {
                                  HapticFeedback.lightImpact();
                                  widget.onSend(widget.controller.text);
                                },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
