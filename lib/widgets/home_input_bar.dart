import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Bottom input bar with voice button, text field, and send button.
class HomeInputBar extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.transparent,
            isDark ? const Color(0xFF0A0E1A).withOpacity(0.9) : Colors.white.withOpacity(0.9),
          ],
        ),
      ),
      child: Row(
        children: [
          // Glowing Voice Mic button
          AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOutCubic,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isListening
                  ? Colors.redAccent
                  : theme.cardTheme.color ?? Colors.white,
              border: Border.all(
                color: isListening
                    ? Colors.redAccent
                    : theme.colorScheme.onSurface.withOpacity(0.08),
                width: 1.2,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(isDark ? 0.2 : 0.03),
                  blurRadius: 8,
                  offset: const Offset(0, 4),
                ),
                if (isListening)
                  BoxShadow(
                    color: Colors.redAccent.withOpacity(0.4),
                    blurRadius: 12,
                    spreadRadius: 2,
                  ),
              ],
            ),
            child: IconButton(
              icon: Icon(
                isListening ? Icons.mic_rounded : Icons.mic_none_rounded,
                color: isListening
                    ? Colors.white
                    : theme.colorScheme.primary,
              ),
              onPressed: isLoading ? null : () {
                HapticFeedback.mediumImpact();
                onMicTap();
              },
            ),
          ),
          const SizedBox(width: 10),

          // Text input container
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: theme.cardTheme.color,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: theme.colorScheme.onSurface.withOpacity(0.08),
                  width: 1.2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(isDark ? 0.2 : 0.03),
                    blurRadius: 8,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: controller,
                      style: const TextStyle(fontSize: 14),
                      decoration: InputDecoration(
                        hintText: isListening ? 'Listening...' : 'Type a command...',
                        hintStyle: TextStyle(
                          fontSize: 13,
                          color: isDark ? Colors.grey[600] : Colors.grey[400],
                        ),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                        border: InputBorder.none,
                      ),
                      textInputAction: TextInputAction.send,
                      onSubmitted: isLoading ? null : (text) => onSend(text),
                    ),
                  ),

                  // Send button
                  Container(
                    margin: const EdgeInsets.only(right: 6),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        colors: [
                          theme.colorScheme.primary,
                          theme.colorScheme.primary.withOpacity(0.8),
                        ],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: theme.colorScheme.primary.withOpacity(0.3),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: IconButton(
                      icon: const Icon(Icons.send_rounded, size: 16, color: Colors.white),
                      onPressed: isLoading
                          ? null
                          : () {
                              HapticFeedback.lightImpact();
                              onSend(controller.text);
                            },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
