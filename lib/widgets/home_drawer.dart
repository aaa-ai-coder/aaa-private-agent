import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../services/database_service.dart';
import '../services/chat_history_service.dart';
import '../main.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Navigation drawer for the home screen.
class HomeDrawer extends StatefulWidget {
  final bool isDark;
  final String currentSessionId;
  final VoidCallback onNewChat;
  final Function(String sessionId, String title) onLoadSession;
  final VoidCallback onTaskHistory;
  final VoidCallback onSettings;

  const HomeDrawer({
    super.key,
    required this.isDark,
    required this.currentSessionId,
    required this.onNewChat,
    required this.onLoadSession,
    required this.onTaskHistory,
    required this.onSettings,
  });

  @override
  State<HomeDrawer> createState() => _HomeDrawerState();
}

class _HomeDrawerState extends State<HomeDrawer> {
  final AuthService _authService = authService;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final drawerBg = widget.isDark ? const Color(0xFF0B0F19) : const Color(0xFFF8FAFC);
    final textStyle = TextStyle(
      color: widget.isDark ? const Color(0xFF94A3B8) : const Color(0xFF475569),
      fontWeight: FontWeight.w600,
      fontSize: 13.5,
    );
    final headerStyle = TextStyle(
      color: widget.isDark ? Colors.white : const Color(0xFF1E293B),
      fontSize: 17,
      fontWeight: FontWeight.w900,
      letterSpacing: -0.5,
    );

    return Drawer(
      backgroundColor: drawerBg,
      child: Column(
        children: [
          // Drawer Header
          Container(
            padding: const EdgeInsets.only(top: 60, bottom: 20, left: 24, right: 24),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: widget.isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0),
                  width: 0.5,
                ),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: theme.primaryColor.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        Icons.smart_toy_rounded,
                        color: theme.primaryColor,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text('AAA Private Agent', style: headerStyle),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    CircleAvatar(
                      radius: 16,
                      backgroundColor: theme.primaryColor.withOpacity(0.15),
                      child: Icon(Icons.person_rounded, size: 18, color: theme.primaryColor),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _authService.email ?? 'User',
                        style: TextStyle(
                          fontSize: 13,
                          color: widget.isDark ? const Color(0xFF94A3B8) : const Color(0xFF475569),
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      icon: Icon(Icons.logout_rounded, size: 18, color: Colors.redAccent.withOpacity(0.7)),
                      tooltip: 'Sign out',
                      onPressed: () async {
                        Navigator.pop(context);
                        await _authService.signOut();
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),

          // New Chat Button
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Container(
              width: double.infinity,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    theme.colorScheme.primary,
                    theme.colorScheme.primary.withOpacity(0.8),
                  ],
                ),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: theme.colorScheme.primary.withOpacity(0.3),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () {
                    Navigator.pop(context);
                    widget.onNewChat();
                  },
                  borderRadius: BorderRadius.circular(16),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(vertical: 13),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.add_comment_rounded, color: Colors.white, size: 16),
                        SizedBox(width: 8),
                        Text(
                          'New Chat',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 13.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),

          // Section CHAT HISTORY
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'CHAT HISTORY',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  color: theme.primaryColor,
                  letterSpacing: 1.5,
                ),
              ),
            ),
          ),

          // Chat Sessions List
          Expanded(
            child: FutureBuilder<List<Map<String, dynamic>>>(
              future: _authService.userId != null
                  ? DatabaseService.getSessions(_authService.userId!)
                  : Future.value([]),
              builder: (context, snapshot) {
                if (!snapshot.hasData || snapshot.data!.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.chat_bubble_outline_rounded,
                          size: 32,
                          color: widget.isDark ? Colors.grey[800] : Colors.grey[300],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'No recent chats',
                          style: TextStyle(
                            color: widget.isDark ? Colors.grey[800] : Colors.grey[400],
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  );
                }

                final sessions = snapshot.data!;
                return ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  itemCount: sessions.length,
                  itemBuilder: (context, index) {
                    final session = sessions[index];
                    final sessionId = session['id'] as String;
                    final sessionTitle = session['title'] as String? ?? 'Chat';
                    final isCurrent = sessionId == widget.currentSessionId;

                    return Container(
                      margin: const EdgeInsets.symmetric(vertical: 2, horizontal: 8),
                      decoration: BoxDecoration(
                        color: isCurrent
                            ? theme.colorScheme.primary.withOpacity(0.08)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(12),
                        border: isCurrent
                            ? Border.all(
                                color: theme.colorScheme.primary.withOpacity(0.15),
                              )
                            : null,
                      ),
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                        dense: true,
                        leading: Icon(
                          Icons.chat_bubble_outline_rounded,
                          size: 15,
                          color: isCurrent
                              ? theme.colorScheme.primary
                              : (widget.isDark ? Colors.grey[600] : Colors.grey[500]),
                        ),
                        title: Text(
                          sessionTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: textStyle.copyWith(
                            fontWeight: isCurrent ? FontWeight.bold : FontWeight.w500,
                            color: isCurrent
                                ? (widget.isDark ? Colors.white : const Color(0xFF1E293B))
                                : null,
                          ),
                        ),
                        trailing: IconButton(
                          icon: Icon(
                            Icons.delete_outline_rounded,
                            size: 16,
                            color: Colors.redAccent.withOpacity(0.7),
                          ),
                          onPressed: () async {
                            await DatabaseService.deleteSession(sessionId);
                            await ChatHistoryService.deleteSession(sessionId);
                            if (mounted) setState(() {});
                          },
                        ),
                        onTap: () {
                          Navigator.pop(context);
                          widget.onLoadSession(sessionId, sessionTitle);
                        },
                      ),
                    );
                  },
                );
              },
            ),
          ),

          // Bottom section
          Container(
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(
                  color: widget.isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0),
                  width: 0.5,
                ),
              ),
            ),
            child: Column(
              children: [
                ListTile(
                  horizontalTitleGap: 8,
                  leading: Icon(
                    Icons.history_rounded,
                    color: widget.isDark ? Colors.grey[400] : Colors.grey[600],
                    size: 20,
                  ),
                  title: Text('Task History', style: textStyle),
                  onTap: () {
                    Navigator.pop(context);
                    widget.onTaskHistory();
                  },
                ),
                ListTile(
                  horizontalTitleGap: 8,
                  leading: Icon(
                    Icons.settings_rounded,
                    color: widget.isDark ? Colors.grey[400] : Colors.grey[600],
                    size: 20,
                  ),
                  title: Text('Settings', style: textStyle),
                  onTap: () {
                    Navigator.pop(context);
                    widget.onSettings();
                  },
                ),
                const SizedBox(height: 12),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
