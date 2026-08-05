import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import '../models/chat_message.dart';

class MessageBubble extends StatelessWidget {
  final ChatMessage message;
  final VoidCallback? onSpeakTap;
  final VoidCallback? onCopyTap;
  final VoidCallback? onDeleteTap;
  final VoidCallback? onRegenerateTap;

  const MessageBubble({
    super.key,
    required this.message,
    this.onSpeakTap,
    this.onCopyTap,
    this.onDeleteTap,
    this.onRegenerateTap,
  });

  @override
  Widget build(BuildContext context) {
    final isUser = message.isUser;

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onLongPress: () => _showActions(context),
        child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.82,
        ),
        margin: EdgeInsets.only(
          left: isUser ? 48 : 8,
          right: isUser ? 8 : 48,
          top: 4,
          bottom: 4,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: isUser
              ? Theme.of(context).colorScheme.primary
              : Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(20),
            topRight: const Radius.circular(20),
            bottomLeft: Radius.circular(isUser ? 20 : 4),
            bottomRight: Radius.circular(isUser ? 4 : 20),
          ),
          border: isUser
              ? null
              : Border.all(
                  color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.08),
                  width: 1.2,
                ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: Theme.of(context).brightness == Brightness.dark ? 0.15 : 0.02),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
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
                      message.actionResult!.actionType.toUpperCase().replaceAll('_', ' '),
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
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onPrimary,
                  fontSize: 15,
                  height: 1.4,
                ),
              )
            else
              MarkdownBody(
                data: message.content,
                selectable: true,
                styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
                  p: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface,
                    fontSize: 15,
                    height: 1.45,
                  ),
                  listBullet: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface,
                    fontSize: 15,
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
                        ? Theme.of(context)
                            .colorScheme
                            .onPrimary
                            .withValues(alpha: 0.7)
                        : Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withValues(alpha: 0.5),
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
                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                            child: Icon(
                              Icons.volume_up_rounded,
                              size: 16,
                              color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.85),
                            ),
                          ),
                        ),
                      const SizedBox(width: 6),
                      InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () {
                          Clipboard.setData(ClipboardData(text: message.content));
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
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                          child: Icon(
                            Icons.copy_rounded,
                            size: 15,
                            color: Theme.of(context)
                                .colorScheme
                                .onSurface
                                .withValues(alpha: 0.6),
                          ),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ],
        ),
        ),
      ),
    );
  }

  /// Long-press action sheet: copy/speak/regenerate/delete per message role.
  void _showActions(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isUser = message.isUser;
    final bg = isDark ? const Color(0xFF1E1B4B) : Colors.white;
    final sub = isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);

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
              color: isDark ? const Color(0xFF8B5CF6).withValues(alpha: 0.25) : const Color(0xFFE2E8F0),
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
    final fg = isDark ? const Color(0xFFF8FAFC) : const Color(0xFF1E293B);
    final color = destructive ? const Color(0xFFEF4444) : fg;
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
