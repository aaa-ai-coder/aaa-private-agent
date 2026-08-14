import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Curated const icon set for custom quick commands. Kept as const
/// [IconData] so Flutter's icon tree-shaking (--tree-shake-icons) can
/// include only the glyphs that are actually referenced.
const List<IconData> kCommandIcons = [
  Icons.star_rounded,
  Icons.favorite_rounded,
  Icons.home_rounded,
  Icons.email_rounded,
  Icons.work_rounded,
  Icons.restaurant_rounded,
  Icons.directions_car_rounded,
  Icons.school_rounded,
  Icons.shopping_bag_rounded,
  Icons.fitness_center_rounded,
  Icons.lightbulb_rounded,
  Icons.bolt_rounded,
  Icons.music_note_rounded,
  Icons.flashlight_on_rounded,
];

/// Resolves a stored icon codepoint back to a const [IconData] from
/// [kCommandIcons]. Falls back to a safe default for unknown codes.
IconData commandIcon(int code) {
  for (final icon in kCommandIcons) {
    if (icon.codePoint == code) return icon;
  }
  return Icons.star_rounded;
}

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
