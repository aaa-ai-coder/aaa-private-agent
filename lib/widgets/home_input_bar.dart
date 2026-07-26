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

  const HomeInputBar({
    super.key,
    required this.controller,
    required this.isListening,
    required this.isLoading,
    required this.isDark,
    required this.onMicTap,
    required this.onSend,
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
    final theme = Theme.of(context);
    final primaryColor = widget.isDark ? const Color(0xFFA78BFA) : const Color(0xFF7C3AED);

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.transparent,
            widget.isDark ? const Color(0xFF0F172A).withOpacity(0.95) : Colors.white.withOpacity(0.95),
          ],
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
                    ? Colors.redAccent.withOpacity(0.15)
                    : primaryColor.withOpacity(0.15),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: widget.isListening
                      ? Colors.redAccent.withOpacity(0.4)
                      : primaryColor.withOpacity(0.4),
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
                          : (widget.isDark ? const Color(0xFFC084FC) : const Color(0xFF6D28D9)),
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
                        color: widget.isListening
                            ? Colors.redAccent
                            : (widget.isDark ? const Color(0xFF1E1B4B) : const Color(0xFFF1F5F9)),
                        border: Border.all(
                          color: widget.isListening
                              ? Colors.redAccent
                              : primaryColor.withOpacity(0.3),
                          width: 1.2,
                        ),
                        boxShadow: [
                          if (widget.isListening)
                            BoxShadow(
                              color: Colors.redAccent.withOpacity(0.5 * _pulseController.value),
                              blurRadius: 16,
                              spreadRadius: 4,
                            )
                          else
                            BoxShadow(
                              color: Colors.black.withOpacity(widget.isDark ? 0.3 : 0.05),
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
                    color: widget.isDark ? const Color(0xFF1E293B) : Colors.white,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: widget.isDark
                          ? const Color(0xFF334155)
                          : const Color(0xFFE2E8F0),
                      width: 1.2,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(widget.isDark ? 0.3 : 0.05),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
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
                            color: widget.isDark ? Colors.white : const Color(0xFF0F172A),
                          ),
                          decoration: InputDecoration(
                            hintText: widget.isListening ? 'Listening...' : 'Type anything or ask AI to execute...',
                            hintStyle: TextStyle(
                              fontSize: 13,
                              color: widget.isDark ? const Color(0xFF64748B) : const Color(0xFF94A3B8),
                            ),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                            border: InputBorder.none,
                          ),
                          textInputAction: TextInputAction.send,
                          onSubmitted: widget.isLoading ? null : (text) => widget.onSend(text),
                        ),
                      ),

                      // Send Button
                      Container(
                        margin: const EdgeInsets.only(right: 6),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: const LinearGradient(
                            colors: [
                              Color(0xFF7C3AED),
                              Color(0xFF8B5CF6),
                            ],
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF7C3AED).withOpacity(0.4),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: IconButton(
                          icon: const Icon(Icons.send_rounded, size: 16, color: Colors.white),
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
