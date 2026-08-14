import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:math';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/api_key_config.dart';

class AriProviderConfig {
  final String name;
  final String baseUrl;
  final String model;
  final String? apiKey;

  const AriProviderConfig({
    required this.name,
    required this.baseUrl,
    required this.model,
    this.apiKey,
  });
}

class AriAiEngine {
  static final AriAiEngine instance = AriAiEngine();

  static const String _userIdPrefsKey = 'pollinations_user_id';

  /// Stable anonymous identity shared with AiService so the keyless backend
  /// recognizes the same user across every request.
  Future<String> _anonymousUserId() async {
    final prefs = await SharedPreferences.getInstance();
    var id = prefs.getString(_userIdPrefsKey);
    if (id == null || id.isEmpty) {
      final r = Random.secure();
      id = List.generate(16, (_) {
        return r.nextInt(256).toRadixString(16).padLeft(2, '0');
      }).join();
      await prefs.setString(_userIdPrefsKey, id);
    }
    return id;
  }

  /// Execute streaming chat completion using the user-configured API key.
  /// When no usable key is configured (or the configured provider fails), the
  /// free keyless backend is used as an automatic fallback so the agent keeps
  /// working out of the box.
  Stream<String> executeStreamWithFailover({
    required List<Map<String, String>> messages,
    required double temperature,
    required int maxTokens,
    ApiKeyConfig? activeCustomKey,
    String keylessBaseUrl = 'https://text.pollinations.ai/openai',
    String keylessModel = 'openai-fast',
  }) async* {
    final candidates = <AriProviderConfig>[];

    if (activeCustomKey != null && activeCustomKey.apiKey.trim().isNotEmpty) {
      candidates.add(AriProviderConfig(
        name: activeCustomKey.name.isNotEmpty ? activeCustomKey.name : 'Configured Key',
        baseUrl: activeCustomKey.baseUrl,
        model: activeCustomKey.model,
        apiKey: activeCustomKey.apiKey,
      ));
    }

    // Always append the free keyless provider as the final fallback.
    candidates.add(AriProviderConfig(
      name: 'Free Keyless AI',
      baseUrl: keylessBaseUrl,
      model: keylessModel,
      apiKey: null,
    ));

    Object? lastError;

    for (final provider in candidates) {
      try {
        developer.log('ARI AI attempting provider: ${provider.name}', name: 'AriAiEngine');
        
        final url = _buildUrl(provider.baseUrl);
        final headers = {
          'Content-Type': 'application/json',
          if (provider.apiKey != null && provider.apiKey!.isNotEmpty)
            'Authorization': 'Bearer ${provider.apiKey}',
          if (provider.apiKey == null) 'X-User-ID': await _anonymousUserId(),
          'HTTP-Referer': 'https://github.com/aaa-ai-coder/aaa-private-agent',
          'X-Title': 'ARI AI Engine',
        };

        final body = jsonEncode({
          'model': provider.model,
          'messages': messages,
          'temperature': temperature,
          'max_tokens': maxTokens,
          'stream': true,
        });

        final request = http.Request('POST', Uri.parse(url))..headers.addAll(headers)..body = body;
        final client = http.Client();
        http.StreamedResponse response;
        try {
          response = await client.send(request).timeout(const Duration(seconds: 12));
        } catch (e) {
          client.close();
          rethrow;
        }

        if (response.statusCode != 200) {
          final errBody = await response.stream.bytesToString();
          client.close();
          throw Exception('HTTP ${response.statusCode}: $errBody');
        }

        // Stream successful — yield chunks
        bool emittedAny = false;
        await for (final chunk in _parseSseStream(response.stream)) {
          emittedAny = true;
          yield chunk;
        }
        client.close();

        if (emittedAny) {
          // Success! Return cleanly
          return;
        }
      } catch (e) {
        developer.log('ARI AI failover caught error on ${provider.name}: $e', name: 'AriAiEngine');
        lastError = e;
        // Continue loop to try next provider in pool
      }
    }

    // If all providers failed, throw last error
    throw Exception('ARI AI Engine connection error across all providers: $lastError');
  }

  String _buildUrl(String baseUrl) {
    String clean = baseUrl.trim();
    if (clean.endsWith('/')) clean = clean.substring(0, clean.length - 1);
    if (!clean.endsWith('/chat/completions')) {
      clean = '$clean/chat/completions';
    }
    return clean;
  }

  Stream<String> _parseSseStream(Stream<List<int>> stream) async* {
    // Decode incrementally so multi-byte UTF-8 characters split across
    // network chunks (emojis, Bengali/Hindi text) are never corrupted.
    final lines = stream.transform(utf8.decoder).transform(const LineSplitter());
    await for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty || trimmed.startsWith(':')) continue;

      if (trimmed.startsWith('data:')) {
        final data = trimmed.substring(5).trim();
        if (data == '[DONE]') return;

        try {
          final json = jsonDecode(data);
          if (json is Map<String, dynamic> && json.containsKey('choices')) {
            final choices = json['choices'] as List;
            if (choices.isNotEmpty) {
              final delta = choices[0]['delta'];
              if (delta != null && delta['content'] != null) {
                yield delta['content'].toString();
              }
            }
          }
        } catch (_) {}
      }
    }
  }
}
