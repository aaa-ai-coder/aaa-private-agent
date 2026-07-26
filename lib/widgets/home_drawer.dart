import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../services/database_service.dart';
import '../services/chat_history_service.dart';
import '../main.dart';

/// Modern navigation drawer with search, cloud backend badges, and session history.
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
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final drawerBg = widget.isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC);
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
            padding: const EdgeInsets.only(top: 56, bottom: 16, left: 20, right: 20),
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
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF7C3AED), Color(0xFF8B5CF6)],
                        ),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.smart_toy_rounded,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text('AAA Private Agent', style: headerStyle),
                  ],
                ),
                const SizedBox(height: 14),

                // Cloud Storage Badges
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _CloudBadge(label: 'Supabase', color: const Color(0xFF10B981), isDark: widget.isDark),
                      const SizedBox(width: 6),
                      _CloudBadge(label: 'Firebase', color: Colors.amber, isDark: widget.isDark),
                      const SizedBox(width: 6),
                      _CloudBadge(label: 'Cloudflare R2', color: Colors.orange, isDark: widget.isDark),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // User Info
                Row(
                  children: [
                    CircleAvatar(
                      radius: 14,
                      backgroundColor: const Color(0xFF7C3AED).withOpacity(0.15),
                      child: const Icon(Icons.person_rounded, size: 16, color: Color(0xFFA78BFA)),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _authService.email ?? 'User Account',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
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
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Container(
              width: double.infinity,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF7C3AED), Color(0xFF8B5CF6)],
                ),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF7C3AED).withOpacity(0.3),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
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
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.add_comment_rounded, color: Colors.white, size: 16),
                        SizedBox(width: 8),
                        Text(
                          'New Conversation',
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

          // Search Chat History Input
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Container(
              height: 36,
              decoration: BoxDecoration(
                color: widget.isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0),
                borderRadius: BorderRadius.circular(12),
              ),
              child: TextField(
                controller: _searchController,
                onChanged: (val) => setState(() => _searchQuery = val.trim().toLowerCase()),
                style: TextStyle(
                  fontSize: 12.5,
                  color: widget.isDark ? Colors.white : Colors.black,
                ),
                decoration: InputDecoration(
                  hintText: 'Search chats...',
                  hintStyle: TextStyle(
                    fontSize: 12,
                    color: widget.isDark ? const Color(0xFF64748B) : const Color(0xFF94A3B8),
                  ),
                  prefixIcon: Icon(
                    Icons.search_rounded,
                    size: 16,
                    color: widget.isDark ? const Color(0xFF64748B) : const Color(0xFF94A3B8),
                  ),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.only(top: 8),
                ),
              ),
            ),
          ),

          const SizedBox(height: 8),

          // Section Title
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'CHAT HISTORY',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFFA78BFA),
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

                final allSessions = snapshot.data!;
                final sessions = _searchQuery.isEmpty
                    ? allSessions
                    : allSessions.where((s) {
                        final title = (s['title'] as String? ?? '').toLowerCase();
                        return title.contains(_searchQuery);
                      }).toList();

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
                            ? const Color(0xFF7C3AED).withOpacity(0.12)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(12),
                        border: isCurrent
                            ? Border.all(
                                color: const Color(0xFF7C3AED).withOpacity(0.3),
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
                              ? const Color(0xFFA78BFA)
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
                  title: Text('Task Execution History', style: textStyle),
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
                  title: Text('Settings & API Keys', style: textStyle),
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

class _CloudBadge extends StatelessWidget {
  final String label;
  final Color color;
  final bool isDark;

  const _CloudBadge({
    required this.label,
    required this.color,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: color.withOpacity(0.3),
          width: 0.8,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 5,
            height: 5,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 9.5,
              fontWeight: FontWeight.bold,
              color: isDark ? color : color.withOpacity(0.9),
            ),
          ),
        ],
      ),
    );
  }
}
