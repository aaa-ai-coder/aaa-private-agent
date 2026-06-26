class ChatMessage {
  final String role; // 'user' or 'assistant'
  final String content;
  final DateTime timestamp;
  final AgentActionResult? actionResult;

  ChatMessage({
    required this.role,
    required this.content,
    DateTime? timestamp,
    this.actionResult,
  }) : timestamp = timestamp ?? DateTime.now();

  bool get isUser => role == 'user';
}

class AgentActionResult {
  final String actionType;
  final bool success;
  final String? details;

  AgentActionResult({
    required this.actionType,
    required this.success,
    this.details,
  });
}
