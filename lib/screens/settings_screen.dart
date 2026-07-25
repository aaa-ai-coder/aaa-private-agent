import 'dart:async';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../main.dart';
import '../services/auth_service.dart';
import '../services/database_service.dart';
import '../services/ai_service.dart';
import '../services/storage_service.dart';
import '../services/shizuku_service.dart';
import '../services/screen_automation_service.dart';
import '../services/telegram_service.dart';
import '../models/api_key_config.dart';
import 'task_history_screen.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import '../config/feature_flags.dart';

class SettingsScreen extends StatefulWidget {
  final AiService aiService;
  final ShizukuService shizukuService;
  final ScreenAutomationService screenAutomationService;
  final TelegramService telegramService;

  const SettingsScreen({
    super.key,
    required this.aiService,
    required this.shizukuService,
    required this.screenAutomationService,
    required this.telegramService,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen>
    with WidgetsBindingObserver {
  late TextEditingController _apiKeyController;
  late TextEditingController _baseUrlController;
  late TextEditingController _modelController;
  late TextEditingController _keyNameController;
  late TextEditingController _telegramTokenController;
  bool _obscureKey = true;
  bool _telegramEnabled = false;
  double _maxSteps = 15;
  bool _disableMaxSteps = false;
  late TextEditingController _maxTokensController;
  double _temperature = 1.0;
  bool _useScreenCompression = true;
  bool _useSystemPrompt = true;
  bool _floatingIconEnabled = false;
  bool _isOverlayPermissionGranted = false;
  bool _autoReadTts = true;
  double _ttsSpeechRate = 0.5;
  double _ttsPitch = 1.0;
  List<String> _liveModels = [];
  bool _isFetchingModels = false;
  List<ApiKeyConfig> _allKeys = [];
  late TextEditingController _r2AccountController;
  late TextEditingController _r2BucketController;
  late TextEditingController _r2TokenController;
  bool _obscureR2Token = true;

  final Map<String, PermissionStatus> _permissions = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _apiKeyController = TextEditingController(text: widget.aiService.apiKey);
    _baseUrlController = TextEditingController(text: widget.aiService.baseUrl);
    _modelController = TextEditingController(text: widget.aiService.model);
    _keyNameController = TextEditingController(
      text: widget.aiService.activeKey?.name ?? 'Default',
    );
    _telegramTokenController = TextEditingController(
      text: widget.telegramService.botToken,
    );
    _telegramEnabled = widget.telegramService.isEnabled;
    _maxSteps = widget.aiService.rawMaxSteps.toDouble();
    _disableMaxSteps = widget.aiService.disableMaxSteps;
    _temperature = widget.aiService.temperature;
    _maxTokensController = TextEditingController(
      text: widget.aiService.maxTokens.toString(),
    );
    _useScreenCompression = widget.aiService.useScreenCompression;
    _useSystemPrompt = widget.aiService.useSystemPrompt;

    // Auto-save listeners
    _apiKeyController.addListener(_autoSave);
    _baseUrlController.addListener(_autoSave);
    _modelController.addListener(_autoSave);
    _keyNameController.addListener(_autoSave);
    _telegramTokenController.addListener(_autoSave);
    _maxTokensController.addListener(_autoSave);

    _r2AccountController = TextEditingController();
    _r2BucketController = TextEditingController();
    _r2TokenController = TextEditingController();
    _loadVoiceSettings();
    _loadApiKeys();
    _loadR2Config();
    _checkPermissions();
    if (FeatureFlags.floatingOverlayEnabled) {
      _checkOverlayStatus();
    }
  }

  Future<void> _loadVoiceSettings() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _autoReadTts = prefs.getBool('auto_read_tts') ?? true;
        _ttsSpeechRate = prefs.getDouble('tts_speech_rate') ?? 0.5;
        _ttsPitch = prefs.getDouble('tts_pitch') ?? 1.0;
      });
    }
  }

  void _loadApiKeys() {
    _allKeys = widget.aiService.allKeys;
    // If no keys exist but settings have a key configured, create one
    if (_allKeys.isEmpty && widget.aiService.apiKey.isNotEmpty) {
      _syncTemporaryKeyToMultiKey();
    }
  }

  void _syncTemporaryKeyToMultiKey() {
    widget.aiService.saveSettings(
      apiKey: widget.aiService.apiKey,
      baseUrl: widget.aiService.baseUrl,
      model: widget.aiService.model,
      name: 'Default',
    );
    _allKeys = widget.aiService.allKeys;
  }

  Future<void> _switchKey(String id) async {
    try {
      await widget.aiService.setActiveApiKey(id);
      setState(() {
        _allKeys = widget.aiService.allKeys;
        final active = widget.aiService.activeKey;
        if (active != null) {
          _apiKeyController.text = active.apiKey;
          _baseUrlController.text = active.baseUrl;
          _modelController.text = active.model;
          _keyNameController.text = active.name;
        }
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error selecting key: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _showAddKeyDialog() async {
    final nameCtrl = TextEditingController();
    final apiKeyCtrl = TextEditingController();
    final baseUrlCtrl = TextEditingController(text: widget.aiService.baseUrl);
    final modelCtrl = TextEditingController(text: widget.aiService.model);
    bool obscure = true;

    await showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Add New API Key'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: nameCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Key Name',
                        hintText: 'My API Key',
                        prefixIcon: Icon(Icons.label_outline, size: 18),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: apiKeyCtrl,
                      decoration: InputDecoration(
                        labelText: 'API Key',
                        hintText: 'sk-...',
                        prefixIcon: const Icon(Icons.key_rounded, size: 18),
                        suffixIcon: IconButton(
                          icon: Icon(obscure ? Icons.visibility_off : Icons.visibility, size: 18),
                          onPressed: () => setDialogState(() => obscure = !obscure),
                        ),
                      ),
                      obscureText: obscure,
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: baseUrlCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Base URL',
                        hintText: 'https://api.groq.com/openai/v1',
                        prefixIcon: Icon(Icons.dns_rounded, size: 18),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: modelCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Model',
                        hintText: 'llama-3.3-70b-versatile',
                        prefixIcon: Icon(Icons.smart_toy_rounded, size: 18),
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text('Quick presets:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        ActionChip(
                          label: const Text('Groq', style: TextStyle(fontSize: 10)),
                          onPressed: () {
                            baseUrlCtrl.text = AiService.groqBaseUrl;
                            setDialogState(() {});
                            _autoFetchModels();
                          },
                        ),
                        ActionChip(
                          label: const Text('OpenRouter', style: TextStyle(fontSize: 10)),
                          onPressed: () {
                            baseUrlCtrl.text = AiService.openRouterBaseUrl;
                            setDialogState(() {});
                            _autoFetchModels();
                          },
                        ),
                        ActionChip(
                          label: const Text('Gemini', style: TextStyle(fontSize: 10)),
                          onPressed: () {
                            baseUrlCtrl.text = AiService.geminiBaseUrl;
                            setDialogState(() {});
                            _autoFetchModels();
                          },
                        ),
                        ActionChip(
                          label: const Text('NVIDIA', style: TextStyle(fontSize: 10)),
                          onPressed: () {
                            baseUrlCtrl.text = AiService.nvidiaBaseUrl;
                            setDialogState(() {});
                            _autoFetchModels();
                          },
                        ),
                        ActionChip(
                          label: const Text('DeepSeek', style: TextStyle(fontSize: 10)),
                          onPressed: () {
                            baseUrlCtrl.text = 'https://api.deepseek.com';
                            setDialogState(() {});
                            _autoFetchModels();
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () async {
                    final id = 'key_${DateTime.now().millisecondsSinceEpoch}_${DateTime.now().microsecondsSinceEpoch}';
                    final newKey = ApiKeyConfig(
                      id: id,
                      userId: authService.userId ?? '',
                      name: nameCtrl.text.trim().isNotEmpty ? nameCtrl.text.trim() : 'New Key',
                      provider: 'custom',
                      baseUrl: baseUrlCtrl.text.trim(),
                      model: modelCtrl.text.trim(),
                      apiKey: apiKeyCtrl.text.trim(),
                      isActive: _allKeys.isEmpty || _allKeys.every((k) => !k.isActive),
                    );
                    try {
                      await widget.aiService.addApiKey(newKey);
                      if (mounted) {
                        setState(() {
                          _allKeys = widget.aiService.allKeys;
                          final active = widget.aiService.activeKey;
                          if (active != null && active.id == newKey.id) {
                            _apiKeyController.text = active.apiKey;
                            _baseUrlController.text = active.baseUrl;
                            _modelController.text = active.model;
                            _keyNameController.text = active.name;
                          }
                        });
                      }
                      if (mounted) {
                        Navigator.of(dialogContext).pop();
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Key added successfully'), backgroundColor: Colors.teal),
                        );
                      }
                    } catch (e) {
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Error adding key: $e'), backgroundColor: Colors.red),
                        );
                      }
                    }
                  },
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );
    nameCtrl.dispose();
    apiKeyCtrl.dispose();
    baseUrlCtrl.dispose();
    modelCtrl.dispose();
  }

  Future<void> _deleteCurrentKey() async {
    final active = widget.aiService.activeKey;
    if (active == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No active key to delete'), backgroundColor: Colors.orange),
        );
      }
      return;
    }
    try {
      await widget.aiService.deleteApiKey(active.id);
      if (mounted) {
        setState(() {
          _allKeys = widget.aiService.allKeys;
          final nextActive = widget.aiService.activeKey;
          if (nextActive != null) {
            _apiKeyController.text = nextActive.apiKey;
            _baseUrlController.text = nextActive.baseUrl;
            _modelController.text = nextActive.model;
            _keyNameController.text = nextActive.name;
          } else {
            _apiKeyController.clear();
            _baseUrlController.clear();
            _modelController.clear();
            _keyNameController.clear();
          }
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Key deleted'), backgroundColor: Colors.teal),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error deleting key: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _syncKeysToCloud() async {
    final userId = authService.userId;
    if (userId == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Sign in to sync keys to cloud'), backgroundColor: Colors.orange),
        );
      }
      return;
    }
    try {
      final count = await widget.aiService.syncKeysToSupabase(userId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Synced $count key(s) to cloud'), backgroundColor: Colors.teal),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error syncing keys: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _autoFetchModels() {
    Future.delayed(const Duration(milliseconds: 500), () {
      widget.aiService.refreshCachedModels().then((_) {
        if (mounted) setState(() {});
      });
    });
  }

  Future<void> _saveVoiceSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('auto_read_tts', _autoReadTts);
    await prefs.setDouble('tts_speech_rate', _ttsSpeechRate);
    await prefs.setDouble('tts_pitch', _ttsPitch);
  }

  Future<void> _loadR2Config() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _r2AccountController.text = prefs.getString('r2_account_id') ?? '';
        _r2BucketController.text = prefs.getString('r2_bucket_name') ?? '';
        _r2TokenController.text = prefs.getString('r2_api_token') ?? '';
      });
    }
  }

  Future<void> _saveR2Config() async {
    try {
      await StorageService.saveConfig(
        accountId: _r2AccountController.text.trim(),
        bucketName: _r2BucketController.text.trim(),
        apiToken: _r2TokenController.text.trim(),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Cloudflare R2 configuration saved.'),
            backgroundColor: Colors.teal,
          ),
        );
        setState(() {});
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error saving R2 config: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  String? _apiUrlError;

  void _validateApiSettings() {
    final url = _baseUrlController.text.trim();
    final key = _apiKeyController.text.trim();
    setState(() {
      if (url.isNotEmpty && !Uri.tryParse(url)!.hasScheme) {
        _apiUrlError = 'URL must start with http:// or https://';
      } else if (url.isNotEmpty && !url.contains('.')) {
        _apiUrlError = 'URL seems invalid (missing domain)';
      } else {
        _apiUrlError = null;
      }
    });
  }

  Future<void> _loadLiveModels() async {
    setState(() => _isFetchingModels = true);
    final models = await widget.aiService.fetchLiveModels(
      apiKey: _apiKeyController.text,
      baseUrl: _baseUrlController.text,
    );
    if (mounted) {
      setState(() {
        _liveModels = models;
        _isFetchingModels = false;
      });
      if (models.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Fetched ${models.length} live models! Select any model below.'),
            backgroundColor: Colors.teal,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not fetch models. Verify API Key and Endpoint.'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    }
  }

  Future<void> _checkOverlayStatus() async {
    bool isActive = await FlutterOverlayWindow.isActive();
    bool isGranted = await FlutterOverlayWindow.isPermissionGranted();
    if (mounted) {
      setState(() {
        _floatingIconEnabled = isActive;
        _isOverlayPermissionGranted = isGranted;
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _autoSaveTimer?.cancel();
    _apiKeyController.removeListener(_autoSave);
    _baseUrlController.removeListener(_autoSave);
    _modelController.removeListener(_autoSave);
    _keyNameController.removeListener(_autoSave);
    _telegramTokenController.removeListener(_autoSave);
    _maxTokensController.removeListener(_autoSave);
    _apiKeyController.dispose();
    _baseUrlController.dispose();
    _modelController.dispose();
    _keyNameController.dispose();
    _telegramTokenController.dispose();
    _maxTokensController.dispose();
    _r2AccountController.dispose();
    _r2BucketController.dispose();
    _r2TokenController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkPermissions();
      if (FeatureFlags.floatingOverlayEnabled) {
        _checkOverlayStatus();
      }
    }
  }

  Future<void> _checkPermissions() async {
    final perms = {
      'Microphone': Permission.microphone,
      'Contacts': Permission.contacts,
      'Phone': Permission.phone,
      'SMS': Permission.sms,
      'Notifications': Permission.notification,
    };

    for (final entry in perms.entries) {
      _permissions[entry.key] = await entry.value.status;
    }
    final overlayGranted = FeatureFlags.floatingOverlayEnabled
        ? await FlutterOverlayWindow.isPermissionGranted()
        : false;
    if (mounted) {
      setState(() {
        _isOverlayPermissionGranted = overlayGranted;
      });
    }
  }

  Future<void> _requestPermission(String name, Permission permission) async {
    final status = await permission.request();
    setState(() => _permissions[name] = status);
  }

  Timer? _autoSaveTimer;

  void _autoSave() {
    final keyName = _keyNameController.text.trim();
    widget.aiService.saveSettings(
      apiKey: _apiKeyController.text.trim(),
      baseUrl: _baseUrlController.text.trim(),
      model: _modelController.text.trim(),
      name: keyName.isNotEmpty ? keyName : null,
    );

    widget.telegramService.saveSettings(
      botToken: _telegramTokenController.text.trim(),
      isEnabled: _telegramEnabled,
    );

    widget.aiService.saveMaxSteps(_maxSteps.toInt());
    widget.aiService.saveDisableMaxSteps(_disableMaxSteps);
    widget.aiService.saveAdvancedSettings(
      temperature: _temperature,
      maxTokens: int.tryParse(_maxTokensController.text) ?? 1024,
      useScreenCompression: _useScreenCompression,
      useSystemPrompt: _useSystemPrompt,
    );

    _autoSaveTimer?.cancel();
    _autoSaveTimer = Timer(const Duration(seconds: 1), () {
      _syncSettingsToSupabase();
    });
  }

  void _syncSettingsToSupabase() {
    final userId = authService.userId;
    if (userId == null) return;
    DatabaseService.saveSettings(
      userId: userId,
      settings: {
        'api_base_url': _baseUrlController.text.trim(),
        'api_model': _modelController.text.trim(),
        'api_max_steps': _maxSteps.toInt(),
        'api_disable_max_steps': _disableMaxSteps,
        'api_temperature': _temperature,
        'api_max_tokens': int.tryParse(_maxTokensController.text) ?? 1024,
        'api_use_screen_compression': _useScreenCompression,
        'api_use_system_prompt': _useSystemPrompt,
        'telegram_token': _telegramTokenController.text.trim(),
        'telegram_enabled': _telegramEnabled,
      },
    );
    // Sync all API keys to Supabase
    final keys = widget.aiService.allKeys;
    for (final key in keys) {
      DatabaseService.saveApiKey(userId: userId, key: key);
    }
  }

  Future<void> _fetchModels() async {
    final baseUrl = _baseUrlController.text.trim();
    final apiKey = _apiKeyController.text.trim();

    if (baseUrl.isEmpty || apiKey.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter Base URL and API Key first.'),
        ),
      );
      return;
    }

    setState(() => _isFetchingModels = true);
    try {
      await widget.aiService.refreshCachedModels();
      if (mounted) {
        setState(() {});
        if (widget.aiService.cachedModels.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No models found. Check your API key and base URL.')),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Found ${widget.aiService.cachedModels.length} models')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error fetching models: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isFetchingModels = false);
    }
  }

  Widget _buildSettingsCard({
    required IconData icon,
    required String title,
    String? subtitle,
    required List<Widget> children,
    required bool isDark,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 28),
      elevation: isDark ? 0 : 1.5,
      shadowColor: Colors.black.withOpacity(isDark ? 0.4 : 0.1),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: isDark
            ? BorderSide(color: Colors.white.withOpacity(0.04), width: 0.5)
            : BorderSide.none,
      ),
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Theme.of(context).primaryColor.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    icon,
                    color: Theme.of(context).primaryColor,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 3),
                        Text(
                          subtitle,
                          style: TextStyle(
                            fontSize: 12,
                            color: isDark
                                ? const Color(0xFF94A3B8)
                                : const Color(0xFF475569),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 22),
            ...children,
          ],
        ),
      ),
    );
  }

  InputDecoration _buildInputDecoration({
    required String labelText,
    required String hintText,
    Widget? prefixIcon,
    Widget? suffixIcon,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return InputDecoration(
      labelText: labelText,
      hintText: hintText,
      prefixIcon: prefixIcon,
      suffixIcon: suffixIcon,
      filled: true,
      fillColor: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
      labelStyle: TextStyle(
        color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
        fontSize: 13,
        fontWeight: FontWeight.w600,
      ),
      hintStyle: TextStyle(
        color: isDark ? const Color(0xFF475569) : const Color(0xFF94A3B8),
        fontSize: 13,
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(
          color: isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0),
          width: 1.2,
        ),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(
          color: isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0),
          width: 1.2,
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(
          color: Theme.of(context).colorScheme.primary,
          width: 1.8,
        ),
      ),
      floatingLabelBehavior: FloatingLabelBehavior.auto,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Settings',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
        children: [
          // 0. Account Card
          _buildSettingsCard(
            icon: Icons.person_outline,
            title: 'Account',
            subtitle: authService.email ?? 'Signed in',
            isDark: isDark,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 24,
                    backgroundColor: Theme.of(context).primaryColor.withOpacity(0.15),
                    child: Icon(Icons.person_rounded, size: 28, color: Theme.of(context).primaryColor),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          authService.email ?? 'User',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'User ID: ${authService.userId?.substring(0, 8) ?? "..."}...',
                          style: TextStyle(fontSize: 12, color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF475569)),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.logout_rounded, color: Colors.redAccent),
                    tooltip: 'Sign out',
                    onPressed: () async {
                      await authService.signOut();
                    },
                  ),
                ],
              ),
            ],
          ),

          // 1. Appearance Card
          _buildSettingsCard(
            icon: Icons.palette_outlined,
            title: 'Appearance',
            subtitle: 'Choose your preferred color theme',
            isDark: isDark,
            children: [
              ValueListenableBuilder<ThemeMode>(
                valueListenable: themeNotifier,
                builder: (context, currentMode, _) {
                  return SizedBox(
                    width: double.infinity,
                    child: SegmentedButton<ThemeMode>(
                      style: SegmentedButton.styleFrom(
                        selectedBackgroundColor: Theme.of(
                          context,
                        ).colorScheme.primary,
                        selectedForegroundColor: Colors.white,
                        backgroundColor: isDark
                            ? const Color(0xFF1E293B)
                            : Colors.white,
                        foregroundColor: isDark ? Colors.white : Colors.black87,
                        side: BorderSide(
                          color: isDark
                              ? const Color(0xFF334155)
                              : const Color(0xFFE2E8F0),
                        ),
                      ),
                      segments: [
                        ButtonSegment(
                          value: ThemeMode.system,
                          label: const Text(
                            'System',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                          icon: const Icon(Icons.brightness_auto, size: 16),
                        ),
                        ButtonSegment(
                          value: ThemeMode.light,
                          label: const Text(
                            'Light',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                          icon: const Icon(Icons.light_mode, size: 16),
                        ),
                        ButtonSegment(
                          value: ThemeMode.dark,
                          label: const Text(
                            'Dark',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                          icon: const Icon(Icons.dark_mode, size: 16),
                        ),
                      ],
                      selected: {currentMode},
                      onSelectionChanged: (Set<ThemeMode> newSelection) async {
                        final mode = newSelection.first;
                        themeNotifier.value = mode;
                        final prefs = await SharedPreferences.getInstance();
                        await prefs.setString('themeMode', mode.name);
                      },
                    ),
                  );
                },
              ),
            ],
          ),

          // 2. AI Voice & Speech Settings Card
          _buildSettingsCard(
            icon: Icons.record_voice_over_rounded,
            title: 'AI Voice & Speech Settings',
            subtitle: 'Configure speech recognition and text-to-speech voice output',
            isDark: isDark,
            children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Auto-read AI responses'),
                subtitle: const Text('Automatically speak AI messages aloud when received'),
                value: _autoReadTts,
                onChanged: (val) {
                  setState(() => _autoReadTts = val);
                  _saveVoiceSettings();
                },
              ),
              const Divider(height: 16),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Speech Speed Rate', style: TextStyle(fontWeight: FontWeight.w600)),
                      Text('${_ttsSpeechRate.toStringAsFixed(1)}x', style: const TextStyle(fontWeight: FontWeight.bold)),
                    ],
                  ),
                  Slider(
                    value: _ttsSpeechRate,
                    min: 0.2,
                    max: 1.5,
                    divisions: 13,
                    label: '${_ttsSpeechRate.toStringAsFixed(1)}x',
                    onChanged: (val) {
                      setState(() => _ttsSpeechRate = val);
                      _saveVoiceSettings();
                    },
                  ),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Voice Pitch', style: TextStyle(fontWeight: FontWeight.w600)),
                      Text('${_ttsPitch.toStringAsFixed(1)}x', style: const TextStyle(fontWeight: FontWeight.bold)),
                    ],
                  ),
                  Slider(
                    value: _ttsPitch,
                    min: 0.5,
                    max: 1.5,
                    divisions: 10,
                    label: '${_ttsPitch.toStringAsFixed(1)}x',
                    onChanged: (val) {
                      setState(() => _ttsPitch = val);
                      _saveVoiceSettings();
                    },
                  ),
                ],
              ),
            ],
          ),

          // 3. AI Engine Configuration Card (Multi-Key Management)
          _buildSettingsCard(
            icon: Icons.psychology_outlined,
            title: 'AI Engine Configuration',
            subtitle: 'Supports any OpenAI-compatible API endpoint',
            isDark: isDark,
            children: [
              // -- Key Selector Row --
              SizedBox(
                height: 40,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    ..._allKeys.map((key) {
                      final isActive = key.isActive;
                      return Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: Text(
                            key.name.isNotEmpty ? key.name : key.id.substring(0, 8),
                            style: TextStyle(fontSize: 12, color: isActive ? Colors.white : null),
                          ),
                          selected: isActive,
                          selectedColor: Theme.of(context).colorScheme.primary,
                          onSelected: (_) => _switchKey(key.id),
                        ),
                      );
                    }),
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: const Icon(Icons.add, size: 18),
                        selected: false,
                        onSelected: (_) => _showAddKeyDialog(),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // -- Active Key Editor --
              TextField(
                controller: _keyNameController,
                decoration: _buildInputDecoration(
                  labelText: 'Key Name',
                  hintText: 'My API Key',
                  prefixIcon: const Icon(Icons.label_outline, size: 18),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _apiKeyController,
                decoration: _buildInputDecoration(
                  labelText: 'API Key',
                  hintText: 'sk-...',
                  prefixIcon: const Icon(Icons.key_rounded, size: 18),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscureKey ? Icons.visibility_off : Icons.visibility,
                      size: 18,
                    ),
                    onPressed: () => setState(() => _obscureKey = !_obscureKey),
                  ),
                ),
                obscureText: _obscureKey,
                onChanged: (_) => _validateApiSettings(),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _baseUrlController,
                decoration: _buildInputDecoration(
                  labelText: 'API Base URL',
                  hintText: 'https://api.deepseek.com',
                  prefixIcon: const Icon(Icons.dns_rounded, size: 18),
                ),
                onChanged: (_) => _validateApiSettings(),
              ),
              if (_apiUrlError != null) ...[
                const SizedBox(height: 6),
                Row(
                  children: [
                    const Icon(Icons.info_outline, size: 14, color: Colors.orange),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        _apiUrlError!,
                        style: const TextStyle(fontSize: 11.5, color: Colors.orange),
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 10),
              // -- Provider Presets --
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  ActionChip(
                    label: const Text('Local Server', style: TextStyle(fontSize: 11)),
                    tooltip: 'For local Llama.cpp or LM Studio',
                    onPressed: () =>
                        _baseUrlController.text = 'http://192.168.1.X:8080/v1',
                  ),
                  ActionChip(
                    avatar: const Icon(Icons.cloud_circle_rounded, size: 16, color: Colors.blue),
                    label: const Text('Ollama Cloud', style: TextStyle(fontSize: 11)),
                    onPressed: () {
                      _baseUrlController.text = AiService.ollamaCloudBaseUrl;
                      _autoFetchModels();
                    },
                  ),
                  ActionChip(
                    avatar: const Icon(Icons.bolt_rounded, size: 16, color: Colors.orange),
                    label: const Text('Groq Free', style: TextStyle(fontSize: 11)),
                    onPressed: () {
                      _baseUrlController.text = AiService.groqBaseUrl;
                      _autoFetchModels();
                    },
                  ),
                  ActionChip(
                    avatar: const Icon(Icons.public_rounded, size: 16, color: Colors.purple),
                    label: const Text('OpenRouter Free', style: TextStyle(fontSize: 11)),
                    onPressed: () {
                      _baseUrlController.text = AiService.openRouterBaseUrl;
                      _autoFetchModels();
                    },
                  ),
                  ActionChip(
                    avatar: const Icon(Icons.auto_awesome_rounded, size: 16, color: Colors.teal),
                    label: const Text('Gemini Free', style: TextStyle(fontSize: 11)),
                    onPressed: () {
                      _baseUrlController.text = AiService.geminiBaseUrl;
                      _autoFetchModels();
                    },
                  ),
                  ActionChip(
                    avatar: const Icon(Icons.memory_rounded, size: 16, color: Colors.green),
                    label: const Text('NVIDIA NIM', style: TextStyle(fontSize: 11)),
                    onPressed: () {
                      _baseUrlController.text = AiService.nvidiaBaseUrl;
                      _autoFetchModels();
                    },
                  ),
                  ActionChip(
                    avatar: const Icon(Icons.hub_rounded, size: 16, color: Colors.indigo),
                    label: const Text('Together AI', style: TextStyle(fontSize: 11)),
                    onPressed: () {
                      _baseUrlController.text = AiService.togetherAiBaseUrl;
                      _autoFetchModels();
                    },
                  ),
                  ActionChip(
                    avatar: const Icon(Icons.waves_rounded, size: 16, color: Colors.amber),
                    label: const Text('Mistral AI', style: TextStyle(fontSize: 11)),
                    onPressed: () {
                      _baseUrlController.text = AiService.mistralAiBaseUrl;
                      _autoFetchModels();
                    },
                  ),
                  ActionChip(
                    label: const Text('DeepSeek', style: TextStyle(fontSize: 11)),
                    onPressed: () {
                      _baseUrlController.text = 'https://api.deepseek.com';
                      _autoFetchModels();
                    },
                  ),
                  ActionChip(
                    label: const Text('Custom', style: TextStyle(fontSize: 11)),
                    tooltip: 'Clear fields',
                    onPressed: () {
                      _baseUrlController.clear();
                      _apiKeyController.clear();
                      _modelController.clear();
                    },
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // -- Model field with Autocomplete and Refresh button --
              Row(
                children: [
                  Expanded(
                    child: Autocomplete<String>(
                      optionsBuilder: (textEditingValue) {
                        if (textEditingValue.text.isEmpty) {
                          return widget.aiService.cachedModels;
                        }
                        return widget.aiService.cachedModels.where((m) =>
                            m.toLowerCase().contains(textEditingValue.text.toLowerCase()));
                      },
                      fieldViewBuilder: (context, textController, focusNode, onSubmitted) {
                        return TextField(
                          controller: _modelController,
                          focusNode: focusNode,
                          decoration: _buildInputDecoration(
                            labelText: 'Model',
                            hintText: 'deepseek-chat',
                            prefixIcon: const Icon(Icons.smart_toy_rounded, size: 18),
                          ),
                          onChanged: (val) {
                            // Sync to Autocomplete's internal controller so it can build options
                            textController.text = val;
                          },
                        );
                      },
                      onSelected: (selection) {
                        _modelController.text = selection;
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    onPressed: _fetchModels,
                    icon: _isFetchingModels
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.refresh, size: 18, color: Colors.white),
                    label: Text(
                      _isFetchingModels ? '...' : 'Refresh',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.primary,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              // -- Action Buttons --
              Row(
                children: [
                  OutlinedButton.icon(
                    icon: const Icon(Icons.add, size: 16),
                    label: const Text('Add Key'),
                    onPressed: _showAddKeyDialog,
                  ),
                  const SizedBox(width: 8),
                  if (_allKeys.length > 1)
                    TextButton.icon(
                      icon: const Icon(Icons.delete_outline, size: 16, color: Colors.red),
                      label: const Text('Delete', style: TextStyle(color: Colors.red)),
                      onPressed: _deleteCurrentKey,
                    ),
                  const Spacer(),
                  if (authService.isLoggedIn)
                    TextButton.icon(
                      icon: const Icon(Icons.cloud_upload, size: 16),
                      label: const Text('Sync'),
                      onPressed: _syncKeysToCloud,
                    ),
                ],
              ),
            ],
          ),

          // 4. Cloudflare R2 Storage Card
          _buildSettingsCard(
            icon: Icons.cloud_outlined,
            title: 'Cloudflare R2 Storage',
            subtitle: 'Store heavy data (images, files) in the cloud',
            isDark: isDark,
            children: [
              TextField(
                controller: _r2AccountController,
                decoration: _buildInputDecoration(
                  labelText: 'Account ID',
                  hintText: 'Your Cloudflare Account ID',
                  prefixIcon: const Icon(Icons.badge_outlined, size: 18),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _r2BucketController,
                decoration: _buildInputDecoration(
                  labelText: 'Bucket Name',
                  hintText: 'my-bucket',
                  prefixIcon: const Icon(Icons.folder_outlined, size: 18),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _r2TokenController,
                decoration: _buildInputDecoration(
                  labelText: 'API Token',
                  hintText: 'R2 API Token',
                  prefixIcon: const Icon(Icons.vpn_key_outlined, size: 18),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscureR2Token ? Icons.visibility_off : Icons.visibility,
                      size: 18,
                    ),
                    onPressed: () => setState(() => _obscureR2Token = !_obscureR2Token),
                  ),
                ),
                obscureText: _obscureR2Token,
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  if (StorageService.isConfigured)
                    const Icon(Icons.check_circle, color: Colors.green, size: 18)
                  else
                    const Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 18),
                  const SizedBox(width: 8),
                  Text(
                    StorageService.isConfigured ? 'Configured' : 'Not configured',
                    style: TextStyle(
                      color: StorageService.isConfigured ? Colors.green : Colors.orange,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const Spacer(),
                  ElevatedButton(
                    onPressed: _saveR2Config,
                    child: const Text('Save'),
                  ),
                ],
              ),
            ],
          ),

          // 5. Parameters & Tuning Card
          _buildSettingsCard(
            icon: Icons.tune_outlined,
            title: 'Tuning & Boundaries',
            subtitle: 'Configure LLM agent parameters',
            isDark: isDark,
            children: [
              SwitchListTile(
                title: const Text('Disable Maximum Steps'),
                subtitle: const Text(
                  '⚠️ Can cause infinite loops.',
                  style: TextStyle(color: Colors.orange, fontSize: 12),
                ),
                value: _disableMaxSteps,
                onChanged: (bool value) {
                  setState(() {
                    _disableMaxSteps = value;
                  });
                  _autoSave();
                },
                contentPadding: EdgeInsets.zero,
              ),
              if (!_disableMaxSteps) ...[
                const SizedBox(height: 8),
                Text(
                  'Maximum Steps Per Task: ${_maxSteps.toInt()}',
                  style: const TextStyle(
                    fontWeight: FontWeight.w500,
                    fontSize: 13,
                  ),
                ),
                Slider(
                  value: _maxSteps,
                  min: 5,
                  max: 50,
                  divisions: 45,
                  label: _maxSteps.toInt().toString(),
                  onChanged: (value) {
                    setState(() {
                      _maxSteps = value;
                    });
                  },
                  onChangeEnd: (value) {
                    _autoSave();
                  },
                ),
              ],
              const SizedBox(height: 12),
              TextField(
                controller: _maxTokensController,
                keyboardType: TextInputType.number,
                decoration: _buildInputDecoration(
                  labelText: 'Context Limit (Max Tokens)',
                  hintText: '1024',
                  prefixIcon: const Icon(Icons.token_rounded, size: 18),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Temperature: ${_temperature.toStringAsFixed(2)}',
                style: const TextStyle(
                  fontWeight: FontWeight.w500,
                  fontSize: 13,
                ),
              ),
              Slider(
                value: _temperature,
                min: 0.0,
                max: 2.0,
                divisions: 20,
                label: _temperature.toStringAsFixed(2),
                onChanged: (value) {
                  setState(() {
                    _temperature = value;
                  });
                },
                onChangeEnd: (value) {
                  _autoSave();
                },
              ),
            ],
          ),

          // 6. Behavior & Extensions Card
          _buildSettingsCard(
            icon: Icons.extension_outlined,
            title: 'Behavior & Extensions',
            subtitle: 'Additional feature flags and overlay options',
            isDark: isDark,
            children: [
              SwitchListTile(
                title: const Text('Use Screen Compression'),
                subtitle: const Text(
                  'Removes duplicate elements to save tokens',
                ),
                value: _useScreenCompression,
                onChanged: (bool value) {
                  setState(() {
                    _useScreenCompression = value;
                  });
                  _autoSave();
                },
                contentPadding: EdgeInsets.zero,
              ),
              SwitchListTile(
                title: const Text('Send System Prompt'),
                subtitle: const Text('Turn off for custom LoRA fine-tunes'),
                value: _useSystemPrompt,
                onChanged: (bool value) {
                  setState(() {
                    _useSystemPrompt = value;
                  });
                  _autoSave();
                },
                contentPadding: EdgeInsets.zero,
              ),
              if (FeatureFlags.floatingOverlayEnabled)
                SwitchListTile(
                  title: const Text('Enable Floating Agent Icon'),
                  subtitle: const Text('Assign tasks without opening the app'),
                  value: _floatingIconEnabled,
                  onChanged: (val) async {
                    if (val) {
                      bool? isGranted =
                          await FlutterOverlayWindow.isPermissionGranted();
                      if (isGranted != true) {
                        bool? result =
                            await FlutterOverlayWindow.requestPermission();
                        if (result != true) {
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Permission to draw over other apps is required.',
                                ),
                              ),
                            );
                          }
                          return;
                        }
                      }
                      if (await FlutterOverlayWindow.isActive() == false) {
                        await FlutterOverlayWindow.showOverlay(
                          enableDrag: true,
                          overlayTitle: "AAA Private Agent",
                          overlayContent: "AAA Private Agent - Floating Assistant",
                          flag: OverlayFlag.focusPointer,
                          alignment: OverlayAlignment.centerRight,
                          visibility: NotificationVisibility.visibilitySecret,
                          positionGravity: PositionGravity.auto,
                          startPosition: const OverlayPosition(0, 200),
                          width: 56,
                          height: 56,
                        );
                      }
                    } else {
                      if (await FlutterOverlayWindow.isActive() == true) {
                        await FlutterOverlayWindow.closeOverlay();
                      }
                    }
                    setState(() => _floatingIconEnabled = val);
                    _autoSave();
                  },
                  contentPadding: EdgeInsets.zero,
                ),
            ],
          ),

          // 7. Telegram Remote Access Card
          _buildSettingsCard(
            icon: Icons.send_and_archive_outlined,
            title: 'Telegram Remote Access',
            subtitle: 'Control your agent remotely from anywhere',
            isDark: isDark,
            children: [
              TextField(
                controller: _telegramTokenController,
                decoration: _buildInputDecoration(
                  labelText: 'Telegram Bot Token',
                  hintText: '123456:ABC-DEF1234ghIkl-zyx57W2v1u123ew11',
                  prefixIcon: const Icon(Icons.send_rounded, size: 18),
                ),
              ),
              SwitchListTile(
                title: const Text('Enable Telegram Bot'),
                subtitle: const Text('Allows remote control via Telegram chat'),
                value: _telegramEnabled,
                onChanged: (val) {
                  setState(() => _telegramEnabled = val);
                  _autoSave();
                },
                contentPadding: EdgeInsets.zero,
              ),
            ],
          ),

          // 8. Accessibility Screen Control Card
          _buildSettingsCard(
            icon: Icons.visibility_outlined,
            title: 'Screen Control (Accessibility)',
            subtitle: 'Required to read screen and perform automated clicks',
            isDark: isDark,
            children: [_buildAccessibilityCard()],
          ),

          // 7. System Permissions Card
          _buildSettingsCard(
            icon: Icons.security_outlined,
            title: 'App Permissions',
            subtitle: 'Required for automation, microphone, and contacts',
            isDark: isDark,
            children: _buildPermissionTiles(),
          ),

          // 8. Task History Card
          _buildSettingsCard(
            icon: Icons.history_outlined,
            title: 'Execution logs',
            subtitle: 'View history of tasks and token analytics',
            isDark: isDark,
            children: [
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('View Task History'),
                subtitle: const Text(
                  'Access complete trace of execution steps',
                ),
                trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 16),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const TaskHistoryScreen(),
                    ),
                  );
                },
              ),
            ],
          ),

          // 9. About / Links Card removed
        ],
      ),
    );
  }

  List<Widget> _buildPermissionTiles() {
    final permissionMap = {
      'Microphone': Permission.microphone,
      'Contacts': Permission.contacts,
      'Phone': Permission.phone,
      'SMS': Permission.sms,
      'Notifications': Permission.notification,
    };

    final icons = {
      'Microphone': Icons.mic,
      'Contacts': Icons.contacts,
      'Phone': Icons.phone,
      'SMS': Icons.sms,
      'Notifications': Icons.notifications,
    };

    final list = permissionMap.entries.map((entry) {
      final status = _permissions[entry.key];
      final isGranted = status?.isGranted ?? false;

      return ListTile(
        leading: Icon(icons[entry.key]),
        title: Text(entry.key),
        trailing: isGranted
            ? Icon(
                Icons.check_circle,
                color: Theme.of(context).colorScheme.primary,
              )
            : TextButton(
                onPressed: () => _requestPermission(entry.key, entry.value),
                child: const Text('Grant'),
              ),
        subtitle: Text(
          isGranted
              ? 'Granted'
              : (status?.isDenied ?? true
                    ? 'Not granted'
                    : 'Denied permanently'),
          style: TextStyle(
            color: isGranted
                ? Theme.of(context).colorScheme.primary
                : Colors.orange,
            fontSize: 12,
          ),
        ),
      );
    }).toList();

    if (FeatureFlags.floatingOverlayEnabled) {
      list.add(
        ListTile(
          leading: const Icon(Icons.layers),
          title: const Text('Display Over Other Apps (Floating Bubble)'),
          trailing: _isOverlayPermissionGranted
              ? Icon(
                  Icons.check_circle,
                  color: Theme.of(context).colorScheme.primary,
                )
              : TextButton(
                  onPressed: () async {
                    await FlutterOverlayWindow.requestPermission();
                    final granted =
                        await FlutterOverlayWindow.isPermissionGranted();
                    setState(() {
                      _isOverlayPermissionGranted = granted;
                    });
                  },
                  child: const Text('Grant'),
                ),
          subtitle: Text(
            _isOverlayPermissionGranted ? 'Granted' : 'Not granted',
            style: TextStyle(
              color: _isOverlayPermissionGranted
                  ? Theme.of(context).colorScheme.primary
                  : Colors.orange,
              fontSize: 12,
            ),
          ),
        ),
      );
    }

    return list;
  }

  Widget _buildShizukuCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  widget.shizukuService.isAvailable
                      ? Icons.link
                      : Icons.link_off,
                  color: widget.shizukuService.isAvailable
                      ? Colors.green
                      : Colors.grey,
                ),
                const SizedBox(width: 8),
                Text(
                  widget.shizukuService.isAvailable
                      ? 'Shizuku is running'
                      : 'Shizuku not detected',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: widget.shizukuService.isAvailable
                        ? Colors.green
                        : Colors.grey,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (!widget.shizukuService.isAvailable) ...[
              const Text(
                '1. Install Shizuku from Play Store\n'
                '2. Open Shizuku and start it via Wireless Debugging\n'
                '3. Come back here and tap "Check Again"',
                style: TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: () async {
                  await widget.shizukuService.checkAvailability();
                  if (mounted) setState(() {});
                },
                child: const Text('Check Again'),
              ),
            ] else if (!widget.shizukuService.hasPermission) ...[
              OutlinedButton(
                onPressed: () async {
                  await widget.shizukuService.requestPermission();
                  if (mounted) setState(() {});
                },
                child: const Text('Grant Shizuku Permission'),
              ),
            ] else ...[
              Row(
                children: [
                  const Icon(Icons.check_circle, color: Colors.green, size: 16),
                  const SizedBox(width: 4),
                  Text(
                    'Permission granted — ADB commands available',
                    style: TextStyle(color: Colors.green[700], fontSize: 13),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildAccessibilityCard() {
    return FutureBuilder<bool>(
      future: widget.screenAutomationService.isServiceRunning(),
      builder: (context, snapshot) {
        final isRunning = snapshot.data ?? false;

        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      isRunning ? Icons.visibility : Icons.visibility_off,
                      color: isRunning ? Colors.green : Colors.grey,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      isRunning
                          ? 'Screen Control is active'
                          : 'Screen Control is disabled',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: isRunning ? Colors.green : Colors.grey,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (!isRunning) ...[
                  const Text(
                    'Tap below to open Accessibility Settings, then find "PrivateAgent Screen Control" and enable it.',
                    style: TextStyle(fontSize: 13),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: () async {
                      await widget.screenAutomationService
                          .openAccessibilitySettings();
                    },
                    icon: const Icon(Icons.settings),
                    label: const Text('Open Accessibility Settings'),
                  ),
                ] else ...[
                  Text(
                    'Can read screen, tap, scroll, and type in other apps',
                    style: TextStyle(color: Colors.green[700], fontSize: 13),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}
