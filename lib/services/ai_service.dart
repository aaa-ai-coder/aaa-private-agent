import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:math';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/agent_action.dart';
import '../models/api_key_config.dart';
import 'database_service.dart';

class AiResponse {
  final String content;
  final int totalTokens;
  AiResponse(this.content, this.totalTokens);
}

class AiService {
  static const String _defaultBaseUrl = 'https://api.groq.com/openai/v1';
  static const String _defaultModel = 'llama-3.3-70b-versatile';
  static const String nvidiaBaseUrl = 'https://integrate.api.nvidia.com/v1';
  static const String nvidiaDefaultModel = 'z-ai/glm-5.2';
  static const String ollamaCloudBaseUrl = 'https://api.ollama.com/v1';
  static const String openRouterBaseUrl = 'https://openrouter.ai/api/v1';
  static const String groqBaseUrl = 'https://api.groq.com/openai/v1';
  static const String geminiBaseUrl = 'https://generativelanguage.googleapis.com/v1beta/openai/';
  static const String togetherAiBaseUrl = 'https://api.together.xyz/v1';
  static const String mistralAiBaseUrl = 'https://api.mistral.ai/v1';

  /// Free, general-purpose chat endpoints verified in NVIDIA's NIM catalog.
  /// The live /models response is intersected with this list so unavailable or
  /// non-chat models never appear in PrivateAgent's NVIDIA model picker.
  static const List<String> nvidiaFreeChatModels = [
    'z-ai/glm-5.2',
    'nvidia/nemotron-3-nano-30b-a3b',
    'nvidia/nemotron-3-super-120b-a12b',
    'nvidia/nemotron-3-ultra-550b-a55b',
    'nvidia/nvidia-nemotron-nano-9b-v2',
    'openai/gpt-oss-20b',
    'openai/gpt-oss-120b',
    'meta/llama-3.3-70b-instruct',
    'meta/llama-3.2-3b-instruct',
    'meta/llama-3.1-8b-instruct',
    'meta/llama-3.1-70b-instruct',
    'mistralai/mistral-nemotron',
    'deepseek-ai/deepseek-v4-flash',
    'deepseek-ai/deepseek-v4-pro',
  ];

  static bool isNvidiaBaseUrl(String baseUrl) {
    final uri = Uri.tryParse(baseUrl.trim());
    return uri?.host.toLowerCase() == 'integrate.api.nvidia.com';
  }

  static List<String> filterNvidiaFreeModels(Iterable<String> models) {
    final availableModels = models.toSet();
    return nvidiaFreeChatModels
        .where(availableModels.contains)
        .toList(growable: false);
  }

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

  // ─── Model Cache ────────────────────────────────────────────────
  static const String _modelsCacheKey = 'cached_models';
  List<String> _cachedModels = [];

  /// Cached list of models fetched from the provider API.
  List<String> get cachedModels => List.unmodifiable(_cachedModels);

  /// Fetch and cache models from the active provider endpoint.
  /// Call this whenever the API key or base URL changes.
  Future<List<String>> refreshCachedModels() async {
    if (_baseUrl.isEmpty) return [];
    try {
      _cachedModels = await fetchLiveModels();
      // Cache to SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_modelsCacheKey, jsonEncode(_cachedModels));
      return _cachedModels;
    } catch (e) {
      developer.log('Failed to refresh models: $e', name: 'AiService');
      return _cachedModels;
    }
  }

  /// Load cached models from SharedPreferences
  Future<void> _loadCachedModels() async {
    final prefs = await SharedPreferences.getInstance();
    final cached = prefs.getString(_modelsCacheKey);
    if (cached != null) {
      try {
        _cachedModels = (jsonDecode(cached) as List).cast<String>();
      } catch (_) {
        _cachedModels = [];
      }
    }
  }

  // ─── Multi-Key Support ──────────────────────────────────────────
  static const String _keysCacheKey = 'api_keys_cache';
  List<ApiKeyConfig> _apiKeys = [];

  /// All configured API keys
  List<ApiKeyConfig> get allKeys => List.unmodifiable(_apiKeys);

  /// The currently active key, or null if none
  ApiKeyConfig? get activeKey => _apiKeys.cast<ApiKeyConfig?>().firstWhere(
    (k) => k!.isActive,
    orElse: () => null,
  );

  /// Generate a simple unique ID for local use before Supabase sync
  static String _genKeyId() {
    final r = Random.secure();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final random = r.nextInt(999999);
    return 'key_${timestamp}_$random';
  }

  /// Load the cached keys list from SharedPreferences and apply the active key
  Future<void> _loadApiKeys() async {
    final prefs = await SharedPreferences.getInstance();
    final cached = prefs.getString(_keysCacheKey);
    if (cached != null && cached.isNotEmpty) {
      try {
        final list = jsonDecode(cached) as List;
        _apiKeys = list
            .map((e) => ApiKeyConfig.fromJson(Map<String, dynamic>.from(e)))
            .toList();
      } catch (_) {
        _apiKeys = [];
      }
    }
    _applyActiveKeyFromList();
  }

  /// Persist the keys list to SharedPreferences cache
  Future<void> _saveKeysCache() async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = jsonEncode(_apiKeys.map((k) => k.toJson()).toList());
    await prefs.setString(_keysCacheKey, encoded);
  }

  /// Set _apiKey, _baseUrl, _model from the active key in the list
  void _applyActiveKeyFromList() {
    final active = activeKey;
    if (active != null) {
      _apiKey = active.apiKey.isNotEmpty ? active.apiKey : _apiKey;
      _baseUrl = active.baseUrl.isNotEmpty ? active.baseUrl : _baseUrl;
      _model = active.model.isNotEmpty ? active.model : _model;
      // Trigger async model refresh if key/baseUrl changed
      unawaited(refreshCachedModels());
    }
  }

  /// Add a new API key configuration. If it's the only key, it becomes active.
  Future<void> addApiKey(ApiKeyConfig key) async {
    // If this is the first key, make it active
    final shouldActivate = _apiKeys.isEmpty || key.isActive;
    final newKey = key.copyWith(
      isActive: shouldActivate && _apiKeys.every((k) => !k.isActive),
    );
    _apiKeys.add(newKey);
    if (newKey.isActive) {
      _applyActiveKeyFromList();
    }
    await _saveKeysCache();
  }

  /// Update an existing API key configuration
  Future<void> updateApiKey(ApiKeyConfig updated) async {
    final index = _apiKeys.indexWhere((k) => k.id == updated.id);
    if (index == -1) return;
    _apiKeys[index] = updated;
    if (updated.isActive) {
      // Deactivate all others
      for (int i = 0; i < _apiKeys.length; i++) {
        if (i != index && _apiKeys[i].isActive) {
          _apiKeys[i] = _apiKeys[i].copyWith(isActive: false);
        }
      }
      _applyActiveKeyFromList();
    }
    await _saveKeysCache();
  }

  /// Delete an API key by ID
  Future<void> deleteApiKey(String id) async {
    final wasActive = _apiKeys.where((k) => k.id == id).firstOrNull?.isActive ?? false;
    _apiKeys.removeWhere((k) => k.id == id);

    if (wasActive && _apiKeys.isNotEmpty) {
      // Activate the first remaining key
      _apiKeys[0] = _apiKeys[0].copyWith(isActive: true);
    }
    _applyActiveKeyFromList();
    await _saveKeysCache();
  }

  /// Set the active API key by ID
  Future<void> setActiveApiKey(String id) async {
    bool found = false;
    for (int i = 0; i < _apiKeys.length; i++) {
      final isTarget = _apiKeys[i].id == id;
      _apiKeys[i] = _apiKeys[i].copyWith(isActive: isTarget);
      if (isTarget) found = true;
    }
    if (found) {
      _applyActiveKeyFromList();
      await _saveKeysCache();
    }
  }

  /// Sync local keys to Supabase for the given userId.
  /// Returns the number of keys synced.
  Future<int> syncKeysToSupabase(String userId) async {
    if (_apiKeys.isEmpty) return 0;
    int synced = 0;
    for (final key in _apiKeys) {
      try {
        await DatabaseService.saveApiKey(userId: userId, key: key);
        synced++;
      } catch (e) {
        developer.log('Failed to sync key ${key.id}: $e', name: 'AiService');
      }
    }
    return synced;
  }

  /// Load keys from Supabase for the given userId and merge with local cache.
  /// Supabase keys take precedence.
  Future<void> loadKeysFromSupabase(String userId) async {
    try {
      final remoteKeys = await DatabaseService.getApiKeys(userId);
      if (remoteKeys.isNotEmpty) {
        // Merge: remote keys override local, add new local keys to remote
        final remoteMap = {for (final k in remoteKeys) k.id: k};
        final localMap = {for (final k in _apiKeys) k.id: k};

        // Start with remote keys
        final merged = Map<String, ApiKeyConfig>.from(remoteMap);

        // Add local keys not in remote
        for (final entry in localMap.entries) {
          if (!merged.containsKey(entry.key)) {
            merged[entry.key] = entry.value;
          }
        }

        _apiKeys = merged.values.toList();
        _applyActiveKeyFromList();
        await _saveKeysCache();

        // Sync any local-only keys to Supabase
        for (final key in localMap.entries) {
          if (!remoteMap.containsKey(key.key)) {
            try {
              await DatabaseService.saveApiKey(userId: userId, key: key.value);
            } catch (_) {}
          }
        }
      }
    } catch (e) {
      developer.log('Failed to load keys from Supabase: $e', name: 'AiService');
    }
  }

  static const String _systemPrompt = '''
You are AAA Private Agent, a powerful AI assistant with FULL control over this Android phone. You can do ANYTHING the user asks - control apps, settings, network, files, and more.

IMPORTANT: When the user wants you to DO something (not just chat), respond with ONLY a JSON object in this exact format:
{"action": "action_name", "params": {"key": "value"}, "response": "Brief message to the user"}

No markdown, no code fences, no extra text around the JSON.

=== COMPLETE ACTION LIST ===

📱 APPS & COMMUNICATION
- open_app: {"app_name": "YouTube"} - Open any app by name
- launch_package: {"package_name": "com.example.app"} - Open app by package name
- make_call: {"contact_name": "Mom"} OR {"phone_number": "123"} - Make phone call
- send_sms: {"contact_name": "John", "message": "Hello"} - Send SMS
- search_contact: {"query": "John"} - Search contacts
- send_email: {"to": "a@b.com", "subject": "Hi", "body": "Hello"} - Send email
- open_url: {"url": "https://..."} - Open URL in browser

⚙️ SYSTEM CONTROL
- set_volume: {"level": 50} - Set volume (0-100)
- set_brightness: {"level": 50} - Set brightness (0-100)
- set_alarm: {"hour": 7, "minute": 30, "label": "Wake up"} - Set alarm
- set_timer: {"seconds": 300, "label": "Pasta"} - Set timer
- lock_screen: {} - Lock the device
- take_screenshot: {} - Take a screenshot and save to /sdcard/
- set_ringer_mode: {"mode": 2} - 0=silent, 1=vibrate, 2=normal
- toggle_flashlight: {"enable": true} - Turn flashlight on/off

📶 NETWORK & CONNECTIVITY
- scan_wifi: {} - Scan and list ALL available WiFi networks
- connect_wifi: {"ssid": "MyWiFi", "password": "pass123"} - Connect to a WiFi network
- get_wifi_password: {"ssid": "MyWiFi"} - Get saved WiFi password for a network
- get_current_wifi: {} - Show the currently connected WiFi network name
- toggle_wifi: {"enable": true} - Turn WiFi on or off
- toggle_mobile_data: {"enable": true} - Turn mobile data on or off
- toggle_bluetooth: {"enable": true} - Turn Bluetooth on or off

🗂️ APP MANAGEMENT (requires Shizuku)
- force_stop_app: {"package_name": "com.example"} - Force stop any running app
- clear_app_data: {"package_name": "com.example"} - Clear app data/cache
- install_apk: {"apk_path": "/sdcard/Download/app.apk"} - Install an APK file
- uninstall_app: {"package_name": "com.example"} - Uninstall an app
- list_installed_apps: {} - List all installed apps and packages
- grant_permission: {"package_name": "com.example", "permission": "android.permission.CAMERA"} - Grant app permission

👆 SCREEN & UI AUTOMATION (Shizuku & Accessibility)
- read_screen: {} - Read and describe everything visible on screen
- press_back: {} - Press the back button
- click_element: {"text": "Submit"} - Click/tap any button or text on screen
- type_on_screen: {"text": "hello", "field_hint": "Search"} - Type text into a field
- scroll_screen: {"direction": "down"} - Scroll the screen (up/down/left/right)
- tap_screen: {"x": 500, "y": 1000} - Tap at screen coordinates (x, y)
- swipe_screen: {"x1": 500, "y1": 1500, "x2": 500, "y2": 500, "duration": 300} - Swipe on screen
- input_text: {"text": "Hello"} - Type text into active input field
- press_key: {"keycode": 4} - Press key (3=Home, 4=Back, 26=Power, 187=App Switch)
- get_ui_dump: {} - Get XML layout dump of current screen

🔧 ADVANCED
- execute_task: {"goal": "description of the full task"} - For COMPLEX multi-step tasks

📋 DEVICE INFO & UTILITIES (no root needed)
- get_device_info: {} - Get device model, Android version, manufacturer
- get_battery: {} - Get battery percentage
- get_storage: {} - Get storage usage info
- copy_clipboard: {"text": "Hello"} - Copy text to clipboard
- paste_clipboard: {} - Read and return clipboard contents
- get_memory: {} - Get RAM usage info

☁️ CLOUD & SYNC (Firebase + Cloudflare R2)
- fcm_subscribe: {"topic": "news"} - Subscribe to push notification topics
- fcm_unsubscribe: {"topic": "news"} - Unsubscribe from push topics
- list_storage_files: {"prefix": "screenshots/"} - List files in cloud storage
- get_storage_url: {"path": "screenshots/photo.jpg"} - Get download link for a cloud file
- save_message_to_cloud: {"text": "Buy milk", "label": "notes"} - Save a note/message to the cloud
- r2_upload: {"content": "File contents", "file_name": "note.txt", "folder": "notes"} - Upload text content to Cloudflare R2
- r2_list: {"prefix": "notes/"} - List files in Cloudflare R2 storage
- r2_delete: {"path": "notes/old.txt"} - Delete a file from Cloudflare R2

🎯 EXECUTE_TASK USE: For ANY request with multiple steps like:
  "Open YouTube and search for cats"
  "Create a new alarm for 7 AM"
  "Go to YouTube and search for cats"  
  "Open WhatsApp and send hello to John"
  "Find WiFi password and connect to network"
  "Install this APK and open it"
  "Take a screenshot and send it"
  "Turn on WiFi, connect to HomeWiFi, then open YouTube"

💬 For normal conversation (questions, chat, info requests), respond with PLAIN TEXT naturally.

🌐 MULTILINGUAL SUPPORT: Always detect the user's language and RESPOND IN THE SAME LANGUAGE.
- If user speaks English → respond in English
- If user speaks Bengali (Bangla) → respond in Bengali
- If user speaks Spanish → respond in Spanish
- If user speaks Hindi → respond in Hindi
- Support ALL languages naturally without being asked
''';

  static const String _chatSystemPrompt = '''
You are AAA Private Agent, a helpful conversational AI assistant. 
Provide direct, natural, and friendly text responses. You cannot perform device actions or run tools. 
Answer questions, explain concepts, brainstorm, write emails/messages, and chat with the user in plain text or markdown format.
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

    // Load cached models and multi-key cache
    await _loadCachedModels();
    await _loadApiKeys();

    // Auto-refresh models if we have an API key configured
    if (_apiKey != null && _apiKey!.isNotEmpty) {
      unawaited(refreshCachedModels());
    }
  }

  Future<void> saveSettings({
    required String apiKey,
    String? baseUrl,
    String? model,
    String? name,
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

    // Also update/create an entry in the multi-key list
    final active = activeKey;
    if (active != null) {
      // Update the existing active key
      final updated = active.copyWith(
        apiKey: cleanApiKey,
        baseUrl: baseUrl ?? active.baseUrl,
        model: model ?? active.model,
        name: name ?? active.name,
      );
      await updateApiKey(updated);
    } else {
      // Create a new key entry
      final newKey = ApiKeyConfig(
        id: _genKeyId(),
        userId: '',
        name: name ?? 'Default',
        provider: 'custom',
        baseUrl: baseUrl ?? _baseUrl,
        model: model ?? _model,
        apiKey: cleanApiKey,
        isActive: true,
      );
      await addApiKey(newKey);
    }

    // Auto-refresh available models from the provider
    unawaited(refreshCachedModels());
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

  /// Query the OpenAI-compatible `/models` endpoint to list available live models for the given endpoint & key.
  Future<List<String>> fetchLiveModels({String? apiKey, String? baseUrl}) async {
    final keyToUse = (apiKey ?? _apiKey ?? '').trim().replaceAll(RegExp(r'^bearer\s+', caseSensitive: false), '');
    final urlToUse = (baseUrl ?? _baseUrl).trim().replaceAll(RegExp(r'/+$'), '');

    if (urlToUse.isEmpty) return [];

    final modelsEndpoint = '$urlToUse/models';
    try {
      final response = await http.get(
        Uri.parse(modelsEndpoint),
        headers: {
          'Accept': 'application/json',
          if (keyToUse.isNotEmpty) 'Authorization': 'Bearer $keyToUse',
        },
      ).timeout(const Duration(seconds: 12));

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = jsonDecode(response.body);
        final List<dynamic> modelList = data['data'] ?? data['models'] ?? [];
        final List<String> modelIds = [];
        for (final item in modelList) {
          if (item is Map && item.containsKey('id') && item['id'] is String) {
            modelIds.add(item['id'] as String);
          } else if (item is String) {
            modelIds.add(item);
          }
        }
        modelIds.sort();
        if (isNvidiaBaseUrl(urlToUse)) {
          return filterNvidiaFreeModels(modelIds);
        }
        return modelIds;
      }
    } catch (e) {
      developer.log('Error fetching live models from $modelsEndpoint: $e', name: 'PrivateAgent');
    }
    return [];
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

  int get _effectiveMaxTokens {
    // GLM is a reasoning model. With the app's 1,024-token default it can
    // consume the whole budget reasoning and finish without visible content.
    if (isNvidiaBaseUrl(_baseUrl) &&
        _model == nvidiaDefaultModel &&
        _maxTokens < 4096) {
      return 4096;
    }
    return _maxTokens;
  }

  void clearHistory() {
    _conversationHistory.clear();
  }

  void addHistoryMessage(String role, String content) {
    _conversationHistory.add({'role': role, 'content': content});
    if (_conversationHistory.length > 20) {
      _conversationHistory.removeRange(0, _conversationHistory.length - 20);
    }
  }

  /// Send a message to the AI and get a response.
  /// Ensures the base URL ends with /chat/completions
  String _buildChatUrl(String baseUrl) {
    String url = baseUrl.trim();
    if (url.endsWith('/chat/completions')) return url;
    if (url.endsWith('/')) return '${url}chat/completions';
    return '$url/chat/completions';
  }

  Future<String> sendMessage(String message, {bool isAgentMode = true}) async {
    if (_apiKey == null || _apiKey!.isEmpty) {
      throw Exception('API Key is not configured. Please go to Settings.');
    }

    // Add ONLY the text to the persistent conversation history to save tokens.
    _conversationHistory.add({'role': 'user', 'content': message});

    // Keep conversation history manageable (last 20 messages)
    if (_conversationHistory.length > 20) {
      _conversationHistory.removeRange(0, _conversationHistory.length - 20);
    }

    try {
      // Build the prompt including system instructions
      final systemPrompt = isAgentMode ? _systemPrompt : _chatSystemPrompt;
      final messages = [
        if (_useSystemPrompt) {'role': 'system', 'content': systemPrompt},
        ..._conversationHistory,
      ];

      final requestUrl = _buildChatUrl(_baseUrl);

      final requestBody = jsonEncode({
        'model': _model,
        'messages': messages,
        'temperature': _temperature,
        'max_tokens': _effectiveMaxTokens,
      });

      developer.log(
        'API Request: $requestUrl\n$requestBody',
        name: 'AiService',
      );

      final response = await http
          .post(
            Uri.parse(requestUrl),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $_apiKey',
              'HTTP-Referer': 'https://github.com/orailnoor/private-agent',
              'X-Title': 'AAA Private Agent',
            },
            body: requestBody,
          )
          .timeout(const Duration(minutes: 30));

      developer.log(
        'API Response [${response.statusCode}]: ${response.body}',
        name: 'AiService',
      );

      if (response.statusCode != 200) {
        String errorMessage = response.body;
        try {
          final decoded = jsonDecode(response.body);
          if (decoded is Map<String, dynamic>) {
            if (decoded['error'] is Map<String, dynamic>) {
              errorMessage =
                  decoded['error']['message']?.toString() ?? response.body;
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
      assistantMessage = assistantMessage
          .replaceAll(RegExp(r'<think>.*?</think>', dotAll: true), '')
          .trim();

      if (assistantMessage.trim().isEmpty) {
        throw Exception(
          'API returned an empty response. This may be due to rate limits or API instability.',
        );
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

  /// Send a message and stream the response chunk-by-chunk.
  Stream<String> sendMessageStream(
    String message, {
    bool isAgentMode = true,
  }) async* {
    if (_apiKey == null || _apiKey!.isEmpty) {
      throw Exception('API Key is not configured. Please go to Settings.');
    }

    _conversationHistory.add({'role': 'user', 'content': message});

    if (_conversationHistory.length > 20) {
      _conversationHistory.removeRange(0, _conversationHistory.length - 20);
    }

    try {
      final systemPrompt = isAgentMode ? _systemPrompt : _chatSystemPrompt;
      final messages = [
        if (_useSystemPrompt) {'role': 'system', 'content': systemPrompt},
        ..._conversationHistory,
      ];

      final requestUrl = _buildChatUrl(_baseUrl);

      final client = http.Client();
      final request = http.Request('POST', Uri.parse(requestUrl));
      request.headers.addAll({
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $_apiKey',
        'HTTP-Referer': 'https://github.com/orailnoor/private-agent',
        'X-Title': 'PrivateAgent',
      });

      request.body = jsonEncode({
        'model': _model,
        'messages': messages,
        'temperature': _temperature,
        'max_tokens': _effectiveMaxTokens,
        'stream': true,
      });

      final response = await client
          .send(request)
          .timeout(const Duration(minutes: 30));

      if (response.statusCode != 200) {
        final body = await response.stream.bytesToString();
        String errorMessage = body;
        try {
          final decoded = jsonDecode(body);
          if (decoded is Map<String, dynamic>) {
            if (decoded['error'] is Map<String, dynamic>) {
              errorMessage = decoded['error']['message']?.toString() ?? body;
            } else if (decoded['error'] is String) {
              errorMessage = decoded['error'];
            }
          }
        } catch (_) {}
        client.close();
        throw Exception('API error (${response.statusCode}): $errorMessage');
      }

      final accumulatedContent = StringBuffer();
      bool inThinkBlock = false;

      // Listen to response stream
      final lineStream = response.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter());

      await for (final line in lineStream) {
        final trimmedLine = line.trim();
        if (trimmedLine.isEmpty) continue;
        if (trimmedLine.startsWith('data:')) {
          final dataStr = trimmedLine.substring(5).trim();
          if (dataStr == '[DONE]') break;
          try {
            final json = jsonDecode(dataStr);
            if (json is Map && json['choices'] is List) {
              final choices = json['choices'] as List;
              if (choices.isNotEmpty) {
                final choice = choices[0];
                if (choice is! Map) continue;
                final rawDelta = choice['delta'];
                final delta = rawDelta is Map ? rawDelta : const {};
                final rawContent = delta['content'];
                if (rawContent is String && rawContent.isNotEmpty) {
                  final content = rawContent;
                  accumulatedContent.write(content);

                  // Handle <think> block stripping on the fly for better stream styling
                  if (content.contains('<think>')) {
                    inThinkBlock = true;
                    // If there is text before <think>, yield it
                    final parts = content.split('<think>');
                    if (parts[0].isNotEmpty) {
                      yield parts[0];
                    }
                  } else if (content.contains('</think>')) {
                    inThinkBlock = false;
                    // If there is text after </think>, yield it
                    final parts = content.split('</think>');
                    if (parts.length > 1 && parts[1].isNotEmpty) {
                      yield parts[1];
                    }
                  } else if (!inThinkBlock) {
                    yield content;
                  }
                }
                if (choice['finish_reason'] != null) break;
              }
            }
          } catch (_) {
            // Ignore incomplete chunks
          }
        }
      }

      client.close();

      // Clean up final accumulated response and add to history
      String finalResponse = accumulatedContent.toString().trim();
      finalResponse = finalResponse
          .replaceAll(RegExp(r'<think>.*?</think>', dotAll: true), '')
          .trim();

      if (finalResponse.isEmpty) {
        throw Exception(
          'The model finished without a visible answer. Increase Max Tokens '
          'or try another NVIDIA model.',
        );
      }
      _conversationHistory.add({'role': 'assistant', 'content': finalResponse});
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

        final requestUrl = _buildChatUrl(_baseUrl);

        final response = await http
            .post(
              Uri.parse(requestUrl),
              headers: {
                'Content-Type': 'application/json',
                'Authorization': 'Bearer $_apiKey',
                'HTTP-Referer': 'https://github.com/aaa-ai-coder/aaa-private-agent',
                'X-Title': 'PrivateAgent',
              },
              body: jsonEncode({
                'model': _model,
                'messages': messages,
                'temperature': _temperature,
                'max_tokens': _effectiveMaxTokens,
              }),
            )
            .timeout(const Duration(minutes: 30));

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
        content = content
            .replaceAll(RegExp(r'<think>.*?</think>', dotAll: true), '')
            .trim();

        if (content.trim().isEmpty) {
          throw Exception(
            'API returned an empty response. This may be due to strict rate limits or safety filters.',
          );
        }

        int tokens = 0;
        if (data.containsKey('usage') &&
            data['usage']['total_tokens'] != null) {
          tokens = data['usage']['total_tokens'] as int;
        }
        return AiResponse(content, tokens);
      } catch (e) {
        if (currentTry > maxRetries) {
          if (e is Exception) rethrow;
          throw Exception('Network error after $maxRetries retries: $e');
        }
        int delaySeconds = 3 * currentTry;
        developer.log(
          'API call failed ($e), retrying $currentTry/$maxRetries in $delaySeconds seconds...',
          name: 'PrivateAgent',
        );
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

  /// Fetches available models from the provider's /models endpoint with support for all providers (OpenAI, Gemini, Groq, OpenRouter, DeepSeek, Ollama, etc.)
  Future<List<String>> fetchAvailableModels(
    String baseUrl,
    String apiKey,
  ) async {
    try {
      String cleanBaseUrl = baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
      if (cleanBaseUrl.endsWith('/chat/completions')) {
        cleanBaseUrl = cleanBaseUrl.replaceAll('/chat/completions', '');
      }
      final cleanKey = apiKey.trim().replaceAll(RegExp(r'^bearer\s+', caseSensitive: false), '');

      String endpoint = cleanBaseUrl.endsWith('/models') ? cleanBaseUrl : '$cleanBaseUrl/models';

      // Gemini specific parameter
      if (cleanBaseUrl.contains('generativelanguage.googleapis.com') && cleanKey.isNotEmpty) {
        endpoint = '$endpoint?key=$cleanKey';
      }

      final response = await http.get(
        Uri.parse(endpoint),
        headers: {
          'Accept': 'application/json',
          if (cleanKey.isNotEmpty) 'Authorization': 'Bearer $cleanKey',
        },
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        List<String> models = [];
        if (data is Map && data.containsKey('data')) {
          final modelsList = data['data'] as List;
          for (var m in modelsList) {
            if (m is Map && m['id'] != null) models.add(m['id'].toString());
            else if (m is String) models.add(m);
          }
        } else if (data is Map && data.containsKey('models')) {
          final modelsList = data['models'] as List;
          for (var m in modelsList) {
            if (m is Map && m['name'] != null) {
              final name = m['name'].toString();
              models.add(name.startsWith('models/') ? name.substring(7) : name);
            } else if (m is Map && m['id'] != null) {
              models.add(m['id'].toString());
            } else if (m is String) {
              models.add(m);
            }
          }
        } else if (data is List) {
          for (var m in data) {
            if (m is Map && m['id'] != null) models.add(m['id'].toString());
            else if (m is String) models.add(m);
          }
        }

        if (isNvidiaBaseUrl(cleanBaseUrl)) {
          return filterNvidiaFreeModels(models);
        }
        models = models.toSet().toList();
        models.sort();
        return models;
      }
      return [];
    } catch (e) {
      developer.log('Error fetching models: $e', name: 'PrivateAgent');
      return [];
    }
  }
}
