import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:math';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/agent_action.dart';
import '../models/api_key_config.dart';
import 'database_service.dart';
import 'ari_ai_engine.dart';
import 'memory_service.dart';

class AiResponse {
  final String content;
  final int totalTokens;
  AiResponse(this.content, this.totalTokens);
}

class AiService {
  static final AiService instance = AiService();

  /// Free, keyless, OpenAI-compatible chat endpoint. Used as the out-of-the-box
  /// default so the agent works with zero configuration. As of 2026 the
  /// anonymous tier serves the GPT-OSS 20B reasoning model (`openai-fast` /
  /// alias `openai`); everything else on the legacy surface 404s for
  /// anonymous requests, so the quick list stays honest.
  static const String keylessBaseUrl = 'https://text.pollinations.ai/openai';
  static const String keylessDefaultModel = 'openai-fast';
  static const List<String> keylessModels = ['openai-fast', 'openai'];

  /// Puter.js free AI gateway (https://puter.com). Now OpenAI-compatible:
  /// `POST /puterai/openai/v1/chat/completions` with a free personal access
  /// token minted at https://puter.com (anonymous access was retired in 2026;
  /// each user covers their own usage). Model ids verified live against
  /// `api.puter.com/puterai/chat/models/details`.
  static const String puterBaseUrl = 'https://api.puter.com/puterai/openai/v1';
  static const String puterDefaultModel = 'gpt-5.4-nano';
  static const List<String> puterModels = [
    'gpt-5.4-nano',
    'gpt-5.4-mini',
    'gpt-5.4',
    'gpt-5.2',
    'gpt-5',
    'gpt-4o',
    'claude-fable-5',
    'claude-haiku-4-5-20251001',
    'claude-sonnet-5',
    'claude-opus-5',
    'gemini-3.5-flash',
    'gemini-3-flash-preview',
    'gemini-2.5-pro',
    'grok-4.3',
    'grok-4-1-fast-reasoning',
    'deepseek-v4-pro',
    'deepseek-v4-flash',
    'qwen3.6-plus',
    'qwen3.5-plus',
    'qwen3-max',
  ];

  static const String _defaultBaseUrl = keylessBaseUrl;
  static const String _defaultModel = keylessDefaultModel;
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

  /// True when the active endpoint is the free keyless backend.
  bool get _isKeyless => _baseUrl.trim().contains('text.pollinations.ai');

  String? _pollinationsUserId;

  /// Stable anonymous identity for the keyless backend. Pollinations uses this
  /// header to treat requests as a single user instead of throwing every call
  /// into the anonymous rate-limit pool.
  Future<String> _getAnonymousUserId() async {
    if (_pollinationsUserId != null) return _pollinationsUserId!;
    final prefs = await SharedPreferences.getInstance();
    var id = prefs.getString('pollinations_user_id');
    if (id == null || id.isEmpty) {
      final r = Random.secure();
      id = List.generate(16, (_) {
        return r.nextInt(256).toRadixString(16).padLeft(2, '0');
      }).join();
      await prefs.setString('pollinations_user_id', id);
    }
    _pollinationsUserId = id;
    return id;
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
  String _memory = '';
  final List<Map<String, String>> _conversationHistory = [];

  /// Separate history for the Telegram channel. Kept independent from the
  /// in-app chat so a Telegram exchange never pollutes the home-chat context
  /// (and vice versa).
  final List<Map<String, String>> _telegramHistory = [];

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

  /// User id keys are permanently synced to Supabase for (null when signed out).
  String? _syncUserId;

  /// Bind (or unbind, with null) the signed-in user so every key mutation is
  /// persisted to Supabase permanently, not only cached on the device.
  void setSyncUserId(String? userId) => _syncUserId = userId;

  /// All configured API keys
  List<ApiKeyConfig> get allKeys => List.unmodifiable(_apiKeys);

  /// The currently active key, or null if none
  ApiKeyConfig? get activeKey {
    for (final key in _apiKeys) {
      if (key.isActive) return key;
    }
    return null;
  }

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
    await _syncKeyToSupabase(newKey);
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
    await _syncKeyToSupabase(updated);
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

    final userId = _syncUserId;
    if (userId != null) {
      try {
        await DatabaseService.deleteApiKey(id);
      } catch (e) {
        developer.log('Failed to delete key $id from Supabase: $e', name: 'AiService');
      }
    }
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

      final userId = _syncUserId;
      if (userId != null) {
        try {
          await DatabaseService.setActiveApiKey(userId, id);
        } catch (e) {
          developer.log('Failed to activate key $id in Supabase: $e', name: 'AiService');
        }
      }
    }
  }

  /// Persist a single key to Supabase permanently for the signed-in user.
  Future<void> _syncKeyToSupabase(ApiKeyConfig key) async {
    final userId = _syncUserId;
    if (userId == null) return;
    try {
      await DatabaseService.saveApiKey(userId: userId, key: key);
    } catch (e) {
      developer.log('Failed to sync key ${key.id} to Supabase: $e', name: 'AiService');
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
You are AAA Private Agent, an Android phone automation assistant. You can control this device through a set of predefined actions (open apps, make calls, send messages, manage settings, control media, manage WiFi, read the screen, run automation, interact with cloud storage) and you can also chat like a normal assistant.

OUTPUT RULES:
1. When the user asks you to PERFORM an action on this device, output ONLY a single JSON action object with no other text, no markdown fences, no explanation:
{"action": "action_name", "params": {"key": "value"}, "response": "Short confirmation in the user's language"}
2. When the user asks for general chat, advice, explanations, or ideas, reply in natural plain text. Be clear, well-organized, and concise. Use short paragraphs, bullet points, and bold for key terms when helpful.
3. If the action needs information you do not have (e.g. an unknown contact name), pick the best available value and say so briefly in your plain-text reply.
4. For multi-step or compound requests, use the execute_task action with a clear goal.
5. Always reply in the exact same language the user used.

TONE & HONESTY:
- Sound warm, natural and human. Never use emoji or exaggerated enthusiasm.
- Never claim you performed an action you did not perform. If an action failed or is unavailable, say so plainly and suggest the next step.
- If you do not know something, say you do not know instead of guessing.
- Keep answers focused: answer the question first, then add helpful context only if it adds value.

=== ACTION CATALOG ===

APPS & COMMUNICATIONS
- open_app: {"app_name": "YouTube"} - Open any app by name
- launch_package: {"package_name": "com.example.app"} - Open app by package name
- make_call: {"contact_name": "Mom"} OR {"phone_number": "123"} - Make phone call
- send_sms: {"contact_name": "John", "message": "Hello"} - Send SMS
- search_contact: {"query": "John"} - Search contacts
- send_email: {"to": "a@b.com", "subject": "Hi", "body": "Hello"} - Send email
- open_url: {"url": "https://..."} - Open URL in browser

SYSTEM CONTROL & SETTINGS
- set_volume: {"level": 50} - Set media volume (0-100)
- set_brightness: {"level": 50} - Set screen brightness (0-100)
- open_system_setting: {"setting": "wifi"} - Open settings page (wifi, bluetooth, display, accessibility, notifications, location, apps, battery, sound)
- control_media: {"command": "play"} - Control media playback (play, pause, next, previous, stop)
- set_alarm: {"hour": 7, "minute": 30, "label": "Wake up"} - Set alarm
- set_timer: {"seconds": 300, "label": "Pasta"} - Set timer
- lock_screen: {} - Lock the device
- wake_screen: {} - Wake/turn on the screen
- go_home: {} - Go to the launcher home screen
- open_recent_apps: {} - Open recent-apps overview
- take_screenshot: {} - Take screenshot and save to storage
- set_ringer_mode: {"mode": 2} - 0=silent, 1=vibrate, 2=normal
- toggle_dnd: {"enable": true} - Turn Do Not Disturb on/off
- set_auto_rotate: {"enable": true} - Turn auto-rotate on/off
- clear_notifications: {} - Dismiss all active notifications
- run_adb_command: {"command": "settings put global ..."} - Run an ADB/shell command via Shizuku or root
- setup_shizuku: {} - On a ROOTED device, start the Shizuku server and grant this app permission automatically

NETWORK & CONNECTIVITY
- scan_wifi: {} - Scan and list ALL available WiFi networks
- connect_wifi: {"ssid": "MyWiFi", "password": "pass123"} - Connect to a WiFi network with a password
- connect_saved_wifi: {"ssid": "MyWiFi"} - Connect to a SAVED WiFi network using its stored password
- connect_best_wifi: {} - Connect to the best SAVED network currently in range (no password needed)
- connect_available_wifi: {} - Fully autonomous: connect to the best saved network in range, or if none, connect to the best OPEN (password-less) network
- connect_open_wifi: {"ssid": "PublicWifi"} - Connect to a specific OPEN (password-less) network
- get_current_wifi: {} - Show current WiFi network name
- get_wifi_password: {"ssid": "MyWiFi"} - Retrieve a saved WiFi password (root/Shizuku)
- reveal_wifi_password: {"ssid": "MyWiFi"} - Recover a saved network's password from device config or Android's own Share-QR screen, then cache it
- toggle_wifi: {"enable": true} - Turn WiFi on or off
- toggle_mobile_data: {"enable": true} - Turn mobile data on or off
- toggle_bluetooth: {"enable": true} - Turn Bluetooth on or off
- toggle_airplane_mode: {"enable": true} - Turn airplane mode on or off
- toggle_hotspot: {"enable": true} - Turn the Wi-Fi hotspot on or off

APP MANAGEMENT (Root / Shizuku / ADB)
- force_stop_app: {"package_name": "com.example"} - Force stop running app
- clear_app_data: {"package_name": "com.example"} - Clear app data/cache
- install_apk: {"apk_path": "/sdcard/Download/app.apk"} - Install an APK file
- uninstall_app: {"package_name": "com.example"} - Uninstall an app
- list_installed_apps: {} - List all installed apps and packages
- grant_permission: {"package_name": "com.example", "permission": "android.permission.CAMERA"} - Grant app permission

SCREEN & UI AUTOMATION (Shizuku & Accessibility)
- read_screen: {} - Read and describe everything visible on screen
- press_back: {} - Press the back button
- click_element: {"text": "Submit"} - Click/tap button or text on screen
- type_on_screen: {"text": "hello", "field_hint": "Search"} - Type text into input field
- scroll_screen: {"direction": "down"} - Scroll screen (up/down/left/right)
- tap_screen: {"x": 500, "y": 1000} - Tap at screen coordinates (x, y)
- swipe_screen: {"x1": 500, "y1": 1500, "x2": 500, "y2": 500, "duration": 300} - Swipe on screen
- input_text: {"text": "Hello"} - Type text into active input field
- press_key: {"keycode": 4} - Press key (3=Home, 4=Back, 26=Power, 187=App Switch)
- get_ui_dump: {} - Get XML layout dump of current screen

DEVICE INFO & UTILITIES
- get_device_info: {} - Get device model, Android version, manufacturer
- get_battery: {} - Get battery percentage
- get_storage: {} - Get storage usage info
- copy_clipboard: {"text": "Hello"} - Copy text to clipboard
- paste_clipboard: {} - Read and return clipboard contents
- get_memory: {} - Get RAM usage info

CLOUD & SYNC (Firebase + Cloudflare R2 + Supabase)
- fcm_subscribe: {"topic": "news"} - Subscribe to push notification topics
- fcm_unsubscribe: {"topic": "news"} - Unsubscribe from push topics
- list_storage_files: {"prefix": "screenshots/"} - List files in cloud storage
- get_storage_url: {"path": "screenshots/photo.jpg"} - Get download link for cloud file
- save_message_to_cloud: {"text": "Buy milk", "label": "notes"} - Save note/message to cloud
- r2_upload: {"content": "File contents", "file_name": "note.txt", "folder": "notes"} - Upload text to Cloudflare R2
- r2_list: {"prefix": "notes/"} - List files in Cloudflare R2 storage
- r2_delete: {"path": "notes/old.txt"} - Delete file from Cloudflare R2

ADVANCED AUTOMATION
- execute_task: {"goal": "description of the full multi-step task"} - For complex workflows like:
  "Open YouTube and search for music"
  "Scan available WiFi networks and connect to HomeNet"
  "Open WhatsApp and send message to Alex"
  "Turn off WiFi, turn on Mobile Data, and launch Chrome"

For general chat, requests, advice, coding, or discussion, respond with natural PLAIN TEXT. Keep answers focused and avoid unnecessary fluff.
''';

  /// Chat-mode system prompt: conversation-first, but still able to act on the
  /// device. Kept separate from the agent prompt so chat replies stay natural.
  static const String _chatSystemPrompt = '''
You are AAA Private Agent, a helpful assistant that runs on an Android phone and can also control the device through actions (open apps, make calls, send messages, adjust settings, control media, manage WiFi, read the screen, automation).

RULES:
1. Chat normally in the user's language. Be friendly, clear and concise. Use short paragraphs, bullet lists and bold for key terms when useful. Do not over-explain.
2. If the user asks you to PERFORM a device action, output ONLY a single JSON object with no extra text and no markdown fences:
{"action": "action_name", "params": {"key": "value"}, "response": "Short confirmation in the user's language"}
3. For multi-step tasks use execute_task: {"goal": "the full task"}.
4. Available actions include: open_app, make_call, send_sms, set_volume, set_brightness, control_media, set_alarm, set_timer, scan_wifi, connect_wifi, connect_saved_wifi, connect_available_wifi, toggle_wifi, toggle_bluetooth, toggle_airplane_mode, get_device_info, get_battery, take_screenshot, read_screen, click_element, type_on_screen, scroll_screen, press_back, open_url, run_adb_command, reveal_wifi_password, and more.
5. TONE & HONESTY: Sound warm and natural, never use emoji, never claim to have performed an action you did not actually perform, and say so plainly if an action failed or is unavailable.
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

    // Load remembered facts about the user into the system prompt.
    _memory = await MemoryService.memoryBlock();

    // Load cached models and multi-key cache
    await _loadCachedModels();
    await _loadApiKeys();

    // Auto-refresh models if we have an API key configured
    if (_apiKey != null && _apiKey!.isNotEmpty) {
      unawaited(refreshCachedModels());
    }
  }

  /// Reloads the on-device memory block so new facts take effect immediately.
  Future<void> reloadMemory() async {
    _memory = await MemoryService.memoryBlock();
  }

  /// Sends a single turn to a real on-device/local LLM (e.g. Ollama running
  /// on the phone at http://127.0.0.1:11434/v1) over the OpenAI-compatible
  /// chat endpoint. Fully offline, no API key. Used by Offline AI mode.
  Future<String> sendToLocalEndpoint(
    String message, {
    required String baseUrl,
    required String model,
  }) async {
    final systemPrompt = _chatSystemPrompt + _memory;
    final messages = [
      if (_useSystemPrompt) {'role': 'system', 'content': systemPrompt},
      ..._conversationHistory,
      {'role': 'user', 'content': message},
    ];
    final response = await http
        .post(
          Uri.parse('$baseUrl/chat/completions'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'model': model,
            'messages': messages,
            'temperature': _temperature,
            'max_tokens': _effectiveMaxTokens,
          }),
        )
        .timeout(const Duration(minutes: 2));
    if (response.statusCode != 200) {
      throw Exception('Local model error (${response.statusCode})');
    }
    final data = jsonDecode(response.body);
    if (data is! Map<String, dynamic> ||
        !data.containsKey('choices') ||
        data['choices'].isEmpty) {
      throw Exception('Unexpected local model response');
    }
    String content = data['choices'][0]['message']['content'] as String;
    content = content
        .replaceAll(RegExp(r'<think>.*?</think>', dotAll: true), '')
        .trim();
    if (content.isEmpty) {
      throw Exception('Local model returned an empty response');
    }
    _conversationHistory.add({'role': 'assistant', 'content': content});
    return content;
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

    // Puter has no public /models endpoint; serve the curated catalog.
    if (urlToUse.contains('api.puter.com')) {
      return List.of(puterModels);
    }

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
        final dynamic decoded = jsonDecode(response.body);
        final List<dynamic> modelList;
        if (decoded is List) {
          // Some providers (e.g. Pollinations) return a bare array.
          modelList = decoded;
        } else if (decoded is Map<String, dynamic>) {
          modelList = decoded['data'] ?? decoded['models'] ?? [];
        } else {
          modelList = [];
        }
        final List<String> modelIds = [];
        for (final item in modelList) {
          if (item is Map && item.containsKey('id') && item['id'] is String) {
            modelIds.add(item['id'] as String);
          } else if (item is Map && item['name'] is String) {
            // Pollinations-style listing: top-level array of {name, aliases}
            modelIds.addAll((item['aliases'] as List?)?.cast<String>() ?? [item['name'] as String]);
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

  bool get isConfigured => _isKeyless || (_apiKey != null && _apiKey!.isNotEmpty);
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

  /// The chat-mode system prompt (same rules used by cloud chat), exposed so
  /// the bundled on-device LLM keeps identical tone and action behavior.
  String get chatSystemPrompt => _chatSystemPrompt;

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
    _telegramHistory.clear();
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
    if ((_apiKey == null || _apiKey!.isEmpty) && !_isKeyless) {
      throw Exception('API Key is not configured. Please go to Settings.');
    }

    // Add ONLY the text to the Telegram conversation history to save tokens.
    _telegramHistory.add({'role': 'user', 'content': message});

    // Keep conversation history manageable (last 20 messages)
    if (_telegramHistory.length > 20) {
      _telegramHistory.removeRange(0, _telegramHistory.length - 20);
    }

    try {
      // Build the prompt including system instructions
      final systemPrompt = (isAgentMode ? _systemPrompt : _chatSystemPrompt) + _memory;
      final messages = [
        if (_useSystemPrompt) {'role': 'system', 'content': systemPrompt},
        ..._telegramHistory,
      ];

      // Puter now speaks the OpenAI wire shape on `/puterai/openai/v1`, so it
      // flows through the standard path below with its Bearer token.

      final requestUrl = _buildChatUrl(_baseUrl);

      final requestBody = jsonEncode({
        'model': _model,
        'messages': messages,
        'temperature': _temperature,
        'max_tokens': _effectiveMaxTokens,
      });

      developer.log(
        'API Request: $requestUrl model=$_model',
        name: 'AiService',
      );

      final response = await http
          .post(
            Uri.parse(requestUrl),
            headers: {
              'Content-Type': 'application/json',
              if (_apiKey != null && _apiKey!.isNotEmpty)
                'Authorization': 'Bearer $_apiKey',
              if (_isKeyless) 'X-User-ID': await _getAnonymousUserId(),
              'HTTP-Referer': 'https://github.com/aaa-ai-coder/aaa-private-agent',
              'X-Title': 'AAA Private Agent',
            },
            body: requestBody,
          )
          .timeout(const Duration(minutes: 30));

      developer.log(
        'API Response [${response.statusCode}]',
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

      _telegramHistory.add({
        'role': 'assistant',
        'content': assistantMessage,
      });

      return assistantMessage;
    } catch (e) {
      if (_telegramHistory.isNotEmpty &&
          _telegramHistory.last['role'] == 'user') {
        _telegramHistory.removeLast();
      }
      if (e is Exception) rethrow;
      throw Exception('Network error: $e');
    }
  }

  /// Send a message and stream the response chunk-by-chunk using ARI AI Failover Engine.
  Stream<String> sendMessageStream(
    String message, {
    bool isAgentMode = true,
  }) async* {
    _conversationHistory.add({'role': 'user', 'content': message});

    if (_conversationHistory.length > 20) {
      _conversationHistory.removeRange(0, _conversationHistory.length - 20);
    }

    try {
      final systemPrompt = (isAgentMode ? _systemPrompt : _chatSystemPrompt) + _memory;
      final messagesList = [
        if (_useSystemPrompt) {'role': 'system', 'content': systemPrompt},
        ..._conversationHistory,
      ];

      final castMessages = messagesList
          .map((m) => {
                'role': m['role'].toString(),
                'content': m['content'].toString(),
              })
          .toList();

      String fullResponse = '';
      final stream = AriAiEngine.instance.executeStreamWithFailover(
        messages: castMessages,
        temperature: _temperature,
        maxTokens: _effectiveMaxTokens,
        activeCustomKey: activeKey,
      );

      await for (final chunk in stream) {
        fullResponse += chunk;
        yield chunk;
      }

      if (fullResponse.trim().isNotEmpty) {
        _conversationHistory.add({
          'role': 'assistant',
          'content': fullResponse.trim(),
        });
      }
    } catch (e) {
      if (_conversationHistory.isNotEmpty &&
          _conversationHistory.last['role'] == 'user') {
        _conversationHistory.removeLast();
      }
      rethrow;
    }
  }

  /// Send a task execution message — no conversation history, low temperature, limited tokens.
  /// This is much faster and cheaper than sendMessage.
  Future<AiResponse> sendTaskMessage(String systemPrompt, String prompt) async {
    if ((_apiKey == null || _apiKey!.isEmpty) && !_isKeyless) {
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
                if (_apiKey != null && _apiKey!.isNotEmpty)
                  'Authorization': 'Bearer $_apiKey',
                if (_isKeyless) 'X-User-ID': await _getAnonymousUserId(),
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
      // Handle if the response is wrapped in code fences (``` or ```json)
      String jsonStr = trimmed;
      final fenceMatch = RegExp(r'^```[a-zA-Z]*\s*\n([\s\S]*?)\n?```\s*$')
          .firstMatch(trimmed);
      if (fenceMatch != null) {
        jsonStr = fenceMatch.group(1)!.trim();
      } else if (trimmed.startsWith('```')) {
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
            if (m is Map && m['id'] != null) {
              models.add(m['id'].toString());
            } else if (m is String) {
              models.add(m);
            }
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
            if (m is Map && m['id'] != null) {
              models.add(m['id'].toString());
            } else if (m is String) {
              models.add(m);
            }
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
