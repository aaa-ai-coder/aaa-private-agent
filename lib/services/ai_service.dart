import 'dart:convert';
import 'dart:developer' as developer;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/agent_action.dart';
class AiResponse {
  final String content;
  final int totalTokens;
  AiResponse(this.content, this.totalTokens);
}

class AiService {
  static const String _defaultBaseUrl = 'https://api.deepseek.com';
  static const String _defaultModel = 'deepseek-chat';

  String? _apiKey;
  String _baseUrl = _defaultBaseUrl;
  String _model = _defaultModel;
  int _maxSteps = 15;
  bool _disableMaxSteps = false;
  double _temperature = 1.0;
  int _maxTokens = 1024;
  bool _useScreenCompression = true;
  bool _useSystemPrompt = true;
  final List<Map<String, String>> _conversationHistory = [];

  static const String _systemPrompt = '''
You are an AI that controls an Android phone.
Reply ONLY with a raw JSON object. Do NOT add extra text.

Format: {"action": "action_name", "params": {"key": "value"}, "response": "Message to user"}

Available actions:
- launch_package: {"package_name": "com.package.name"}
- macro_meet: {}

EXAMPLES:

User: Set up a meeting with Orailnoor on Google Meet.
{"action": "macro_meet", "params": {}, "response": "Setting up a Google Meet with Orailnoor."}

User: Open the PrivateLM app and say hi.
{"action": "launch_package", "params": {"package_name": "com.orailnoor.privatelm"}, "response": "Hi there! Opening PrivateLM."}
''';

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _apiKey = prefs.getString('api_key');
    _baseUrl = prefs.getString('api_base_url') ?? _defaultBaseUrl;
    _model = prefs.getString('api_model') ?? _defaultModel;
    _maxSteps = prefs.getInt('api_max_steps') ?? 15;
    _disableMaxSteps = prefs.getBool('api_disable_max_steps') ?? false;
    _temperature = prefs.getDouble('api_temperature') ?? 1.0;
    _maxTokens = prefs.getInt('api_max_tokens') ?? 1024;
    _useScreenCompression = prefs.getBool('api_use_screen_compression') ?? true;
    _useSystemPrompt = prefs.getBool('api_use_system_prompt') ?? true;
  }

  Future<void> saveSettings({
    required String apiKey,
    String? baseUrl,
    String? model,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    
    // Clean up the API key in case the user pasted "Bearer sk-..."
    String cleanApiKey = apiKey.trim();
    if (cleanApiKey.toLowerCase().startsWith('bearer ')) {
      cleanApiKey = cleanApiKey.substring(7).trim();
    }
    
    _apiKey = cleanApiKey;
    await prefs.setString('api_key', cleanApiKey);

    if (baseUrl != null && baseUrl.isNotEmpty) {
      _baseUrl = baseUrl;
      await prefs.setString('api_base_url', baseUrl);
    }
    if (model != null && model.isNotEmpty) {
      _model = model;
      await prefs.setString('api_model', model);
    }
  }

  Future<void> saveMaxSteps(int steps) async {
    final prefs = await SharedPreferences.getInstance();
    _maxSteps = steps;
    await prefs.setInt('api_max_steps', steps);
  }

  Future<void> saveDisableMaxSteps(bool disable) async {
    final prefs = await SharedPreferences.getInstance();
    _disableMaxSteps = disable;
    await prefs.setBool('api_disable_max_steps', disable);
  }

  Future<void> saveAdvancedSettings({
    required double temperature,
    required int maxTokens,
    required bool useScreenCompression,
    required bool useSystemPrompt,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    _temperature = temperature;
    _maxTokens = maxTokens;
    _useScreenCompression = useScreenCompression;
    _useSystemPrompt = useSystemPrompt;
    await prefs.setDouble('api_temperature', temperature);
    await prefs.setInt('api_max_tokens', maxTokens);
    await prefs.setBool('api_use_screen_compression', useScreenCompression);
    await prefs.setBool('api_use_system_prompt', useSystemPrompt);
  }

  bool get isConfigured => _apiKey != null && _apiKey!.isNotEmpty;
  String get baseUrl => _baseUrl;
  String get model => _model;
  String get apiKey => _apiKey ?? '';
  int get maxSteps => _disableMaxSteps ? 999 : _maxSteps;
  int get rawMaxSteps => _maxSteps; // For the slider UI
  bool get disableMaxSteps => _disableMaxSteps;
  double get temperature => _temperature;
  int get maxTokens => _maxTokens;
  bool get useScreenCompression => _useScreenCompression;
  bool get useSystemPrompt => _useSystemPrompt;

  void clearHistory() {
    _conversationHistory.clear();
  }

  /// Send a message to the AI and get a response.
  Future<String> sendMessage(String message) async {
    if (_apiKey == null || _apiKey!.isEmpty) {
      throw Exception('API Key is not configured. Please go to Settings.');
    }

    // Add ONLY the text to the persistent conversation history to save tokens.
    _conversationHistory.add({
      'role': 'user',
      'content': message,
    });

    // Keep conversation history manageable (last 20 messages)
    if (_conversationHistory.length > 20) {
      _conversationHistory.removeRange(0, _conversationHistory.length - 20);
    }

    try {
      // Build the prompt including system instructions
      final messages = [
        if (_useSystemPrompt) {'role': 'system', 'content': _systemPrompt},
        ..._conversationHistory,
      ];

      String requestUrl = _baseUrl;
      if (requestUrl.endsWith('/chat/completions')) {
        requestUrl = requestUrl; // User already included it
      } else {
        if (requestUrl.endsWith('/')) {
          requestUrl = '${requestUrl}chat/completions';
        } else {
          requestUrl = '$requestUrl/chat/completions';
        }
      }

      final response = await http.post(
        Uri.parse(requestUrl),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $_apiKey',
          'HTTP-Referer': 'https://github.com/orailnoor/private-agent',
          'X-Title': 'PrivateAgent',
        },
        body: jsonEncode({
          'model': _model,
          'messages': messages,
          'temperature': _temperature,
          'max_tokens': _maxTokens,
        }),
      ).timeout(const Duration(minutes: 30));

      if (response.statusCode != 200) {
        String errorMessage = response.body;
        try {
          final decoded = jsonDecode(response.body);
          if (decoded is Map<String, dynamic>) {
            if (decoded['error'] is Map<String, dynamic>) {
              errorMessage = decoded['error']['message']?.toString() ?? response.body;
            } else if (decoded['error'] is String) {
              errorMessage = decoded['error'];
            }
          }
        } catch (_) {
          // ignore parsing errors, use raw body
        }
        throw Exception('API error (${response.statusCode}): $errorMessage');
      }

      final data = jsonDecode(response.body);
      if (data is! Map<String, dynamic> || !data.containsKey('choices')) {
        throw Exception('Unexpected API response format: $data');
      }

      String assistantMessage =
          data['choices'][0]['message']['content'] as String;

      // Strip <think> blocks commonly produced by reasoning models
      assistantMessage = assistantMessage.replaceAll(RegExp(r'<think>.*?</think>', dotAll: true), '').trim();

      if (assistantMessage.trim().isEmpty) {
        throw Exception('API returned an empty response. This may be due to rate limits or API instability.');
      }

      _conversationHistory.add({
        'role': 'assistant',
        'content': assistantMessage,
      });

      return assistantMessage;
    } catch (e) {
      if (e is Exception) rethrow;
      throw Exception('Network error: $e');
    }
  }

  /// Send a task execution message — no conversation history, low temperature, limited tokens.
  /// This is much faster and cheaper than sendMessage.
  Future<AiResponse> sendTaskMessage(String systemPrompt, String prompt) async {
    if (_apiKey == null || _apiKey!.isEmpty) {
      throw Exception('API Key is not configured. Please go to Settings.');
    }

    int maxRetries = 4;
    int currentTry = 0;

    while (true) {
      try {
        currentTry++;
      final messages = [
        if (_useSystemPrompt) {'role': 'system', 'content': systemPrompt},
        {'role': 'user', 'content': prompt},
      ];

      String requestUrl = _baseUrl;
      if (!requestUrl.endsWith('/chat/completions')) {
        if (requestUrl.endsWith('/')) {
          requestUrl = '${requestUrl}chat/completions';
        } else {
          requestUrl = '$requestUrl/chat/completions';
        }
      }

      final response = await http.post(
        Uri.parse(requestUrl),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $_apiKey',
          'HTTP-Referer': 'https://github.com/orailnoor/private-agent',
          'X-Title': 'PrivateAgent',
        },
        body: jsonEncode({
          'model': _model,
          'messages': messages,
          'temperature': _temperature,
          'max_tokens': _maxTokens,
        }),
      ).timeout(const Duration(minutes: 30));

      if (response.statusCode != 200) {
        String errorMessage = response.body;
        try {
          final decoded = jsonDecode(response.body);
          if (decoded is Map<String, dynamic>) {
            if (decoded['error'] is Map<String, dynamic>) {
              errorMessage = decoded['error']['message'] ?? response.body;
            } else if (decoded['error'] is String) {
              errorMessage = decoded['error'];
            }
          }
        } catch (_) {
          // ignore parsing errors, use raw body
        }
        throw Exception('API error (${response.statusCode}): $errorMessage');
      }

      final data = jsonDecode(response.body);
      if (data is! Map<String, dynamic> || !data.containsKey('choices')) {
        throw Exception('Unexpected API response format: $data');
      }
      String content = data['choices'][0]['message']['content'] as String;
      
      // Strip <think> blocks commonly produced by reasoning models
      content = content.replaceAll(RegExp(r'<think>.*?</think>', dotAll: true), '').trim();
      
      if (content.trim().isEmpty) {
        throw Exception('API returned an empty response. This may be due to strict rate limits or safety filters.');
      }

      int tokens = 0;
      if (data.containsKey('usage') && data['usage']['total_tokens'] != null) {
        tokens = data['usage']['total_tokens'] as int;
      }
      return AiResponse(content, tokens);
    } catch (e) {
      if (currentTry > maxRetries) {
        if (e is Exception) rethrow;
        throw Exception('Network error after $maxRetries retries: $e');
      }
      int delaySeconds = 3 * currentTry;
      developer.log('API call failed ($e), retrying $currentTry/$maxRetries in $delaySeconds seconds...', name: 'PrivateAgent');
      await Future.delayed(Duration(seconds: delaySeconds));
    }
    }
  }

  /// Parse the AI response to check if it's an action or plain text
  AgentAction? parseAction(String response) {
    // Try to parse as JSON action
    try {
      final trimmed = response.trim();
      // Handle if the response is wrapped in code fences
      String jsonStr = trimmed;
      if (trimmed.startsWith('```')) {
        final lines = trimmed.split('\n');
        lines.removeAt(0); // Remove opening fence
        if (lines.isNotEmpty && lines.last.trim() == '```') {
          lines.removeLast(); // Remove closing fence
        }
        jsonStr = lines.join('\n').trim();
      }

      // If it looks like JSON but is missing a closing brace (common with some local models)
      if (jsonStr.startsWith('{') && !jsonStr.endsWith('}')) {
        jsonStr += '\n}';
      }

      if (jsonStr.startsWith('{') && jsonStr.contains('"action"')) {
        try {
          final json = jsonDecode(jsonStr) as Map<String, dynamic>;
          if (json.containsKey('action')) {
            return AgentAction.fromJson(json);
          }
        } catch (e) {
          // If it still fails, it might be deeply truncated, try adding another brace
          if (e.toString().contains('Unexpected end of input')) {
            jsonStr += '\n}';
            final json = jsonDecode(jsonStr) as Map<String, dynamic>;
            if (json.containsKey('action')) {
              return AgentAction.fromJson(json);
            }
          }
        }
      }
    } catch (_) {
      // Not JSON, it's plain text conversation
    }
    return null;
  }

  /// Fetches available models from the provider's /models endpoint
  Future<List<String>> fetchAvailableModels(String baseUrl, String apiKey) async {
    try {
      String cleanBaseUrl = baseUrl;
      // Many providers host it at /models, but some require the base URL without /chat/completions logic
      if (cleanBaseUrl.endsWith('/chat/completions')) {
        cleanBaseUrl = cleanBaseUrl.replaceAll('/chat/completions', '');
      }

      final response = await http.get(
        Uri.parse('$cleanBaseUrl/models'),
        headers: {
          'Authorization': 'Bearer $apiKey',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data is Map && data.containsKey('data')) {
          final modelsList = data['data'] as List;
          return modelsList.map((m) => m['id'].toString()).toList();
        } else if (data is List) {
          return data.map((m) => m['id'].toString()).toList();
        }
      }
      return [];
    } catch (e) {
      print('Error fetching models: $e');
      return [];
    }
  }
}
