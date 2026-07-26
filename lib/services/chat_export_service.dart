import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../models/chat_message.dart';

class ChatExportService {
  /// Export chat session messages to a Markdown file and offer share option
  static Future<String> exportChatToMarkdown({
    required String title,
    required List<ChatMessage> messages,
  }) async {
    try {
      final buffer = StringBuffer();
      buffer.writeln('# $title');
      buffer.writeln('Exported on: ${DateTime.now().toLocal().toString()}\n');
      buffer.writeln('---\n');

      for (final msg in messages) {
        final role = msg.isUser ? '👤 User' : '🤖 Assistant';
        buffer.writeln('### $role');
        buffer.writeln('${msg.content}\n');
      }

      final dir = await getApplicationDocumentsDirectory();
      final cleanTitle = title.replaceAll(RegExp(r'[^\w\s\-]'), '').trim().replaceAll(' ', '_');
      final fileName = 'chat_export_${cleanTitle.isEmpty ? "session" : cleanTitle}.md';
      final file = File('${dir.path}/$fileName');
      await file.writeAsString(buffer.toString());

      await Share.shareXFiles(
        [XFile(file.path)],
        text: 'Exported chat session "$title"',
      );

      return 'Chat exported successfully to ${file.path}';
    } catch (e) {
      return 'Failed to export chat: $e';
    }
  }
}
