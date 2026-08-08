import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// A single remembered fact about the user, stored locally on device.
class MemoryFact {
  final String id;
  final String text;
  final DateTime createdAt;

  const MemoryFact({
    required this.id,
    required this.text,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'text': text,
        'createdAt': createdAt.toIso8601String(),
      };

  factory MemoryFact.fromJson(Map<String, dynamic> json) => MemoryFact(
        id: json['id'] as String? ?? DateTime.now().millisecondsSinceEpoch.toString(),
        text: json['text'] as String? ?? '',
        createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ??
            DateTime.now(),
      );
}

/// Lightweight on-device "AI memory": stores facts the user shares so the
/// assistant can recall them in later conversations. Facts are injected into
/// the system prompt and surfaced in a small manager screen.
class MemoryService {
  MemoryService._();

  static const String _key = 'ai_memory_facts';

  static Future<List<MemoryFact>> loadFacts() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecodeList(raw);
      return list.map((e) => MemoryFact.fromJson(e)).toList();
    } catch (_) {
      return [];
    }
  }

  static List<Map<String, dynamic>> jsonDecodeList(String raw) {
    return (const JsonDecoder().convert(raw) as List<dynamic>)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }

  static Future<void> saveFacts(List<MemoryFact> facts) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      const JsonEncoder().convert(facts.map((f) => f.toJson()).toList()),
    );
  }

  static Future<MemoryFact> addFact(String text) async {
    final facts = await loadFacts();
    final fact = MemoryFact(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      text: text.trim(),
      createdAt: DateTime.now(),
    );
    facts.insert(0, fact);
    if (facts.length > 60) facts.removeRange(60, facts.length);
    await saveFacts(facts);
    return fact;
  }

  static Future<void> removeFact(String id) async {
    final facts = await loadFacts();
    facts.removeWhere((f) => f.id == id);
    await saveFacts(facts);
  }

  static Future<void> clearAll() async {
    await saveFacts([]);
  }

  /// Detects "remember this about me" phrasing. Returns a confirmation reply
  /// to show the user, or null when the text is not a memory statement.
  static Future<String?> tryRemember(String text) async {
    final lower = text.toLowerCase().trim();

    String? fact;
    if (lower.startsWith('remember that ')) {
      fact = _phrase('', lower.substring('remember that '.length));
    } else if (lower.startsWith('remember ')) {
      fact = _phrase('', lower.substring('remember '.length));
    } else {
      for (final pattern in _patterns) {
        final match = RegExp(pattern.regex, caseSensitive: false).firstMatch(text);
        if (match != null) {
          final last = match.groupCount > 0 ? match.group(match.groupCount) : '';
          fact = _phrase(pattern.prefix, last ?? '');
          break;
        }
      }
    }

    if (fact == null || fact.isEmpty) return null;
    await addFact(fact);
    return 'Got it. I\u2019ll remember: $fact';
  }

  static String _phrase(String prefix, String value) {
    final cleaned = value.trim().replaceFirst(RegExp(r'[.!?]+$'), '');
    if (cleaned.isEmpty) return '';
    return prefix + _capitalize(cleaned);
  }

  static String _capitalize(String s) {
    if (s.isEmpty) return s;
    return s[0].toUpperCase() + s.substring(1);
  }

  static final List<_Pattern> _patterns = [
    _Pattern(r'my name is ([A-Za-z\s\-.]+)', 'Your name is '),
    _Pattern(r'call me ([A-Za-z\s\-.]+)', 'Your name is '),
    _Pattern(r'i am (\d{1,3}) years old', 'You are '),
    _Pattern(r'i\s*\'?m (\d{1,3}) years old', 'You are '),
    _Pattern(r'i\s*\'?m from ([A-Za-z\s\-.]+)', 'You are from '),
    _Pattern(r'i live in ([A-Za-z\s\-.]+)', 'You live in '),
    _Pattern(r'my birthday is ([A-Za-z0-9\s\-,/]+)', 'Your birthday is '),
    _Pattern(r'i like ([A-Za-z\s\-,]+)', 'You like '),
    _Pattern(r'i love ([A-Za-z\s\-,]+)', 'You love '),
    _Pattern(r'my favorite (.+)', 'Your favorite '),
    _Pattern(r'i work (as|at) (.+)', 'You work '),
    _Pattern(r'my phone number is ([\d+\s\-]+)', 'Your phone number is '),
    _Pattern(r'my email is ([\w.@\-\+]+)', 'Your email is '),
  ];

  /// Renders the memory block appended to the AI system prompt. Empty when
  /// the user has not shared anything yet.
  static Future<String> memoryBlock() async {
    final facts = await loadFacts();
    if (facts.isEmpty) return '';
    final lines = facts.take(12).map((f) => '- ${f.text}').join('\n');
    return '\n\nUSER MEMORY (facts the user told you \u2014 use them naturally):\n$lines';
  }
}

class _Pattern {
  final String regex;
  final String prefix;
  const _Pattern(this.regex, this.prefix);
}
