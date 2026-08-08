import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import '../models/chat_message.dart';
import 'agent_orb.dart';

class MessageBubble extends StatelessWidget {
  final ChatMessage message;
  final String? modelLabel;
  final bool highlight;
  final VoidCallback? onSpeakTap;
  final VoidCallback? onCopyTap;
  final VoidCallback? onDeleteTap;
  final VoidCallback? onRegenerateTap;
  final VoidCallback? onRewriteTap;
  final VoidCallback? onTranslateTap;

  const MessageBubble({
    super.key,
    required this.message,
    this.modelLabel,
    this.highlight = false,
    this.onSpeakTap,
    this.onCopyTap,
    this.onDeleteTap,
    this.onRegenerateTap,
    this.onRewriteTap,
    this.onTranslateTap,
  });

  @override
  Widget build(BuildContext context) {
    final isUser = message.isUser;
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final bubble = Container(
      constraints: BoxConstraints(
        maxWidth: MediaQuery.of(context).size.width * 0.78,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        gradient: isUser
            ? const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFFFF6B4A), Color(0xFFF65E8B)],
              )
            : null,
        color: isUser ? null : (isDark ? const Color(0xFF241B21) : const Color(0xFFFFFBF4)),
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(20),
          topRight: const Radius.circular(20),
          bottomLeft: Radius.circular(isUser ? 20 : 4),
          bottomRight: Radius.circular(isUser ? 4 : 20),
        ),
        border: isUser
            ? (highlight
                ? Border.all(color: const Color(0xFFFFB86B), width: 2)
                : null)
            : Border.all(
                color: highlight
                    ? const Color(0xFFFFB86B)
                    : isDark
                        ? const Color(0xFFFF6B4A).withValues(alpha: 0.25)
                        : const Color(0xFFF0E3D3),
                width: highlight ? 2 : 1.2,
              ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.18 : 0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Action result badge
          if (message.actionResult != null) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              margin: const EdgeInsets.only(bottom: 8),
              decoration: BoxDecoration(
                color: message.actionResult!.success
                    ? Colors.green.withValues(alpha: 0.12)
                    : Colors.red.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: message.actionResult!.success
                      ? Colors.green.withValues(alpha: 0.3)
                      : Colors.red.withValues(alpha: 0.3),
                  width: 1,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    message.actionResult!.success
                        ? Icons.check_circle_rounded
                        : Icons.error_rounded,
                    size: 14,
                    color: message.actionResult!.success
                        ? Colors.green
                        : Colors.red,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    message.actionResult!.actionType
                        .toUpperCase()
                        .replaceAll('_', ' '),
                    style: TextStyle(
                      fontSize: 10,
                      color: message.actionResult!.success
                          ? Colors.green
                          : Colors.red,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
            ),
          ],
          // Message text
          if (isUser)
            SelectableText(
              message.content,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                height: 1.4,
              ),
            )
          else
            MarkdownBody(
              data: message.content,
              selectable: true,
              styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context))
                  .copyWith(
                p: TextStyle(
                  color: scheme.onSurface,
                  fontSize: 15,
                  height: 1.45,
                ),
                listBullet: TextStyle(
                  color: scheme.onSurface,
                  fontSize: 15,
                ),
                strong: TextStyle(
                  color: isDark ? const Color(0xFFFFC9A8) : const Color(0xFFC2503A),
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          // Bottom Action Bar & Timestamp
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _formatTime(message.timestamp),
                style: TextStyle(
                  fontSize: 11,
                  color: isUser
                      ? Colors.white.withValues(alpha: 0.75)
                      : scheme.onSurface.withValues(alpha: 0.45),
                ),
              ),
              if (!isUser)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (onSpeakTap != null)
                      InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: onSpeakTap,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 4, vertical: 2),
                          child: Icon(
                            Icons.volume_up_rounded,
                            size: 16,
                            color: scheme.primary.withValues(alpha: 0.85),
                          ),
                        ),
                      ),
                    const SizedBox(width: 6),
                    InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () {
                        Clipboard.setData(
                          ClipboardData(text: message.content),
                        );
                        if (onCopyTap != null) {
                          onCopyTap!();
                        } else {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Message copied to clipboard'),
                              duration: Duration(seconds: 2),
                            ),
                          );
                        }
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 4, vertical: 2),
                        child: Icon(
                          Icons.copy_rounded,
                          size: 15,
                          color: scheme.onSurface.withValues(alpha: 0.55),
                        ),
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ],
      ),
    );

    // AI bubbles get a small orb avatar + model label column.
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!isUser) ...[
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: AgentOrb(size: 26, glow: false),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Column(
              crossAxisAlignment: isUser
                  ? CrossAxisAlignment.end
                  : CrossAxisAlignment.start,
              children: [
                if (!isUser && modelLabel != null && modelLabel!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(left: 4, bottom: 3),
                    child: Text(
                      modelLabel!,
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.4,
                        color: scheme.primary.withValues(alpha: 0.85),
                      ),
                    ),
                  ),
                GestureDetector(
                  onLongPress: () => _showActions(context),
                  child: bubble,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Long-press action sheet: copy/speak/regenerate/delete per message role.
  void _showActions(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isUser = message.isUser;
    final bg = isDark ? const Color(0xFF241B21) : Colors.white;
    final sub = isDark ? const Color(0xFFA8938C) : const Color(0xFF8C7A6E);

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Container(
          margin: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isDark
                  ? const Color(0xFFFF6B4A).withValues(alpha: 0.25)
                  : const Color(0xFFF0E3D3),
            ),
          ),
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: sub.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(height: 14),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Text(
                    isUser ? 'Message actions' : 'Assistant response',
                    style: TextStyle(
                      fontSize: 13,
                      color: sub,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.3,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                _actionTile(
                  ctx,
                  icon: Icons.copy_rounded,
                  label: 'Copy text',
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: message.content));
                    Navigator.pop(ctx);
                    ScaffoldMessenger.of(ctx).showSnackBar(
                      const SnackBar(
                        content: Text('Message copied to clipboard'),
                        duration: Duration(seconds: 2),
                      ),
                    );
                  },
                ),
                if (!isUser && onSpeakTap != null)
                  _actionTile(
                    ctx,
                    icon: Icons.volume_up_rounded,
                    label: 'Speak aloud',
                    onTap: () {
                      Navigator.pop(ctx);
                      onSpeakTap!();
                    },
                  ),
                if (!isUser && onRegenerateTap != null)
                  _actionTile(
                    ctx,
                    icon: Icons.refresh_rounded,
                    label: 'Regenerate response',
                    onTap: () {
                      Navigator.pop(ctx);
                      onRegenerateTap!();
                    },
                  ),
                if (onRewriteTap != null)
                  _actionTile(
                    ctx,
                    icon: Icons.auto_fix_high_rounded,
                    label: 'Rewrite with AI',
                    onTap: () {
                      Navigator.pop(ctx);
                      onRewriteTap!();
                    },
                  ),
                if (onTranslateTap != null)
                  _actionTile(
                    ctx,
                    icon: Icons.translate_rounded,
                    label: 'Translate with AI',
                    onTap: () {
                      Navigator.pop(ctx);
                      onTranslateTap!();
                    },
                  ),
                _actionTile(
                  ctx,
                  icon: Icons.delete_outline_rounded,
                  label: 'Delete message',
                  destructive: true,
                  onTap: () {
                    Navigator.pop(ctx);
                    onDeleteTap?.call();
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _actionTile(
    BuildContext context, {
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool destructive = false,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fg = isDark ? const Color(0xFFF9F1EA) : const Color(0xFF2E1F1A);
    final color = destructive ? const Color(0xFFFF4D5E) : fg;
    return ListTile(
      dense: true,
      leading: Icon(icon, size: 20, color: color),
      title: Text(
        label,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
      onTap: onTap,
    );
  }

  String _formatTime(DateTime dt) {
    final hour = dt.hour.toString().padLeft(2, '0');
    final minute = dt.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }
}
