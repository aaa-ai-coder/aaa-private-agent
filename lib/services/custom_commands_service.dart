import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// A user-defined quick command chip shown alongside the built-in ones.
class CustomCommand {
  final String label;
  final String command;
  final int iconCode;

  const CustomCommand({
    required this.label,
    required this.command,
    required this.iconCode,
  });

  Map<String, dynamic> toJson() => {
        'label': label,
        'command': command,
        'iconCode': iconCode,
      };

  factory CustomCommand.fromJson(Map<String, dynamic> json) => CustomCommand(
        label: json['label'] as String? ?? 'Command',
        command: json['command'] as String? ?? '',
        iconCode: json['iconCode'] as int? ?? 0xe150,
      );
}

/// Persists custom quick-command chips in SharedPreferences so users can
/// pin their own frequent requests to the home screen.
class CustomCommandsService {
  CustomCommandsService._();

  static const String _key = 'custom_quick_commands';
  static const int maxCustom = 12;

  static Future<List<CustomCommand>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .take(maxCustom)
          .map((e) => CustomCommand.fromJson(
              Map<String, dynamic>.from(e as Map)))
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> save(List<CustomCommand> commands) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      jsonEncode(commands.take(maxCustom).map((c) => c.toJson()).toList()),
    );
  }

  static Future<bool> add(CustomCommand command) async {
    final commands = await load();
    if (commands.length >= maxCustom) return false;
    commands.add(command);
    await save(commands);
    return true;
  }

  static Future<void> removeAt(int index) async {
    final commands = await load();
    if (index < 0 || index >= commands.length) return;
    commands.removeAt(index);
    await save(commands);
  }
}
