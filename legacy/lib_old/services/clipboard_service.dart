import 'package:flutter/services.dart';

class ClipboardService {
  /// Copy text to clipboard and return confirmation.
  Future<String> copyToClipboard(String text) async {
    if (text.trim().isEmpty) {
      return 'Nothing to copy.';
    }
    try {
      await Clipboard.setData(ClipboardData(text: text));
      final preview = text.length > 50
          ? '${text.substring(0, 50)}...'
          : text;
      return 'Copied to clipboard: "$preview"';
    } catch (e) {
      return 'Error copying to clipboard: $e';
    }
  }

  /// Read text from clipboard and return it.
  Future<String> pasteFromClipboard() async {
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      if (data == null || data.text == null || data.text!.isEmpty) {
        return 'Clipboard is empty.';
      }
      final text = data.text!;
      final preview = text.length > 100
          ? '${text.substring(0, 100)}...'
          : text;
      return 'Clipboard contents: "$preview"';
    } catch (e) {
      return 'Error reading clipboard: $e';
    }
  }
}
