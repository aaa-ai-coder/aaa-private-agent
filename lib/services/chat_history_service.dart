import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';

class ChatSession {
  final String id;
  final String title;
  final DateTime timestamp;
  final List<Map<String, dynamic>> messages;

  ChatSession({
    required this.id,
    required this.title,
    required this.timestamp,
    required this.messages,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'timestamp': timestamp.toIso8601String(),
        'messages': messages,
      };

  factory ChatSession.fromJson(Map<String, dynamic> json) => ChatSession(
        id: json['id'] as String,
        title: json['title'] as String,
        timestamp: DateTime.parse(json['timestamp'] as String),
        messages: List<Map<String, dynamic>>.from(json['messages'] as List),
      );
}

class ChatHistoryService {
  static Future<File> get _localFile async {
    final directory = await getApplicationDocumentsDirectory();
    return File('${directory.path}/chat_history_sessions.json');
  }

  /// Saves a session. Overwrites if ID already exists.
  static Future<void> saveSession(ChatSession session) async {
    try {
      final file = await _localFile;
      List<ChatSession> sessions = await loadSessions();
      
      final index = sessions.indexWhere((s) => s.id == session.id);
      if (index >= 0) {
        sessions[index] = session;
      } else {
        sessions.insert(0, session); // Newest first
      }

      final jsonList = sessions.map((s) => s.toJson()).toList();
      await file.writeAsString(jsonEncode(jsonList));
    } catch (e) {
      print('Error saving chat session: $e');
    }
  }

  /// Loads all saved chat sessions.
  static Future<List<ChatSession>> loadSessions() async {
    try {
      final file = await _localFile;
      if (!await file.exists()) return [];

      final content = await file.readAsString();
      if (content.trim().isEmpty) return [];

      final decoded = jsonDecode(content) as List;
      return decoded.map((item) => ChatSession.fromJson(item as Map<String, dynamic>)).toList();
    } catch (e) {
      print('Error loading chat sessions: $e');
      return [];
    }
  }

  /// Deletes a specific session.
  static Future<void> deleteSession(String id) async {
    try {
      final file = await _localFile;
      List<ChatSession> sessions = await loadSessions();
      sessions.removeWhere((s) => s.id == id);

      final jsonList = sessions.map((s) => s.toJson()).toList();
      await file.writeAsString(jsonEncode(jsonList));
    } catch (e) {
      print('Error deleting chat session: $e');
    }
  }

  /// Clears all saved chat sessions.
  static Future<void> clearAll() async {
    try {
      final file = await _localFile;
      if (await file.exists()) {
        await file.delete();
      }
    } catch (e) {
      print('Error clearing chat history: $e');
    }
  }
}
