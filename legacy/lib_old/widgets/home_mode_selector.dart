import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Pill-shaped Chat/Agent mode toggle.
class HomeModeSelector extends StatelessWidget {
  final String currentMode;
  final ValueChanged<String> onModeChanged;
  final bool isDark;

  const HomeModeSelector({
    super.key,
    required this.currentMode,
    required this.onModeChanged,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final activeBg = isDark ? const Color(0xFF2E2228) : const Color(0xFFF0E3D3);

    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 12),
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: activeBg,
          borderRadius: BorderRadius.circular(30),
          border: Border.all(
            color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.06),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildButton('chat', 'Chat', Icons.chat_bubble_outline_rounded, Theme.of(context)),
            _buildButton('agent', 'Agent', Icons.smart_toy_outlined, Theme.of(context)),
          ],
        ),
      ),
    );
  }

  Widget _buildButton(String modeId, String label, IconData icon, [ThemeData? theme]) {
    final isSelected = currentMode == modeId;
    final t = theme ?? ThemeData();

    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        onModeChanged(modeId);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(26),
          color: isSelected ? t.colorScheme.primary : Colors.transparent,
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: t.colorScheme.primary.withValues(alpha: 0.25),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ]
              : null,
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 15,
              color: isSelected
                  ? Colors.white
                  : (isDark ? const Color(0xFFA8938C) : const Color(0xFF6B5A52)),
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color: isSelected
                    ? Colors.white
                    : (isDark ? const Color(0xFFA8938C) : const Color(0xFF6B5A52)),
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
