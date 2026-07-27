import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'package:http/http.dart' as http;
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

  /// Execute streaming chat completion using the user-configured API key
  Stream<String> executeStreamWithFailover({
    required List<Map<String, String>> messages,
    required double temperature,
    required int maxTokens,
    ApiKeyConfig? activeCustomKey,
  }) async* {
    if (activeCustomKey == null || activeCustomKey.apiKey.trim().isEmpty) {
      throw Exception('API Key is not configured. Please go to Settings and enter your API key.');
    }

    final provider = AriProviderConfig(
      name: activeCustomKey.name.isNotEmpty ? activeCustomKey.name : 'Configured Key',
      baseUrl: activeCustomKey.baseUrl,
      model: activeCustomKey.model,
      apiKey: activeCustomKey.apiKey,
    );

    final candidates = [provider];
    Object? lastError;

    for (final provider in candidates) {
      try {
        developer.log('ARI AI attempting provider: ${provider.name}', name: 'AriAiEngine');
        
        final url = _buildUrl(provider.baseUrl);
        final headers = {
          'Content-Type': 'application/json',
          if (provider.apiKey != null && provider.apiKey!.isNotEmpty)
            'Authorization': 'Bearer ${provider.apiKey}',
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
        final response = await client.send(request).timeout(const Duration(seconds: 12));

        if (response.statusCode != 200) {
          final errBody = await response.stream.bytesToString();
          throw Exception('HTTP ${response.statusCode}: $errBody');
        }

        // Stream successful — yield chunks
        bool emittedAny = false;
        await for (final chunk in _parseSseStream(response.stream)) {
          emittedAny = true;
          yield chunk;
        }

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
    String buffer = '';
    await for (final bytes in stream) {
      buffer += utf8.decode(bytes, allowMalformed: true);
      final lines = buffer.split('\n');
      buffer = lines.removeLast();

      for (final line in lines) {
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
}
