import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../main.dart';
import '../services/ai_service.dart';
import '../services/shizuku_service.dart';
import '../services/screen_automation_service.dart';
import '../services/telegram_service.dart';
import 'task_history_screen.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';

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

  final Map<String, PermissionStatus> _permissions = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _apiKeyController = TextEditingController(text: widget.aiService.apiKey);
    _baseUrlController = TextEditingController(text: widget.aiService.baseUrl);
    _modelController = TextEditingController(text: widget.aiService.model);
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
    _checkPermissions();
    _checkOverlayStatus();
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
    _apiKeyController.dispose();
    _baseUrlController.dispose();
    _modelController.dispose();
    _telegramTokenController.dispose();
    _maxTokensController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkPermissions();
      _checkOverlayStatus();
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
    final overlayGranted = await FlutterOverlayWindow.isPermissionGranted();
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

  Future<void> _saveApiSettings() async {
    await widget.aiService.saveSettings(
      apiKey: _apiKeyController.text.trim(),
      baseUrl: _baseUrlController.text.trim(),
      model: _modelController.text.trim(),
    );

    await widget.telegramService.saveSettings(
      botToken: _telegramTokenController.text.trim(),
      isEnabled: _telegramEnabled,
    );

    await widget.aiService.saveMaxSteps(_maxSteps.toInt());
    await widget.aiService.saveDisableMaxSteps(_disableMaxSteps);
    await widget.aiService.saveAdvancedSettings(
      temperature: _temperature,
      maxTokens: int.tryParse(_maxTokensController.text) ?? 1024,
      useScreenCompression: _useScreenCompression,
      useSystemPrompt: _useSystemPrompt,
    );

    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Settings saved!')));
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

    // Show loading
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    final models = await widget.aiService.fetchAvailableModels(baseUrl, apiKey);

    // Hide loading
    if (mounted) Navigator.pop(context);

    if (models.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No models found or error fetching models.'),
          ),
        );
      }
      return;
    }

    if (mounted) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Select a Model'),
          content: SizedBox(
            width: double.maxFinite,
            height: 300,
            child: ListView.builder(
              itemCount: models.length,
              itemBuilder: (context, index) {
                return ListTile(
                  title: Text(models[index]),
                  onTap: () {
                    setState(() {
                      _modelController.text = models[index];
                    });
                    Navigator.pop(context);
                  },
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
          ],
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Appearance Settings
          Text(
            'Appearance',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          ValueListenableBuilder<ThemeMode>(
            valueListenable: themeNotifier,
            builder: (context, currentMode, _) {
              return SegmentedButton<ThemeMode>(
                style: SegmentedButton.styleFrom(
                  selectedBackgroundColor: isDark ? Colors.white : Colors.black,
                  selectedForegroundColor: isDark ? Colors.black : Colors.white,
                  backgroundColor: isDark ? const Color(0xFF1E1E26) : Colors.white,
                  foregroundColor: isDark ? Colors.white : Colors.black87,
                  side: BorderSide(
                    color: isDark ? Colors.white.withOpacity(0.12) : const Color(0xFFE2E2E8),
                  ),
                ),
                segments: [
                  ButtonSegment(
                    value: ThemeMode.system,
                    label: Text(
                      'System',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                        color: currentMode == ThemeMode.system
                            ? (isDark ? Colors.black : Colors.white)
                            : (isDark ? Colors.grey[300] : Colors.black87),
                      ),
                    ),
                    icon: Icon(
                      Icons.brightness_auto,
                      size: 16,
                      color: currentMode == ThemeMode.system
                          ? (isDark ? Colors.black : Colors.white)
                          : (isDark ? Colors.grey[400] : Colors.black54),
                    ),
                  ),
                  ButtonSegment(
                    value: ThemeMode.light,
                    label: Text(
                      'Light',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                        color: currentMode == ThemeMode.light
                            ? (isDark ? Colors.black : Colors.white)
                            : (isDark ? Colors.grey[300] : Colors.black87),
                      ),
                    ),
                    icon: Icon(
                      Icons.light_mode,
                      size: 16,
                      color: currentMode == ThemeMode.light
                          ? (isDark ? Colors.black : Colors.white)
                          : (isDark ? Colors.grey[400] : Colors.black54),
                    ),
                  ),
                  ButtonSegment(
                    value: ThemeMode.dark,
                    label: Text(
                      'Dark',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                        color: currentMode == ThemeMode.dark
                            ? (isDark ? Colors.black : Colors.white)
                            : (isDark ? Colors.grey[300] : Colors.black87),
                      ),
                    ),
                    icon: Icon(
                      Icons.dark_mode,
                      size: 16,
                      color: currentMode == ThemeMode.dark
                          ? (isDark ? Colors.black : Colors.white)
                          : (isDark ? Colors.grey[400] : Colors.black54),
                    ),
                  ),
                ],
                selected: {currentMode},
                onSelectionChanged: (Set<ThemeMode> newSelection) async {
                  final mode = newSelection.first;
                  themeNotifier.value = mode;
                  final prefs = await SharedPreferences.getInstance();
                  await prefs.setString('themeMode', mode.name);
                },
              );
            },
          ),
          const SizedBox(height: 24),

          // API Settings
          Text(
            'AI Configuration',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          const Text(
            'PrivateAgent supports ANY OpenAI-compatible API. You can use local models (like Llama/Qwen via LM Studio), DeepSeek, Ollama Cloud, Groq, or OpenRouter.',
            style: TextStyle(fontSize: 13, color: Colors.grey),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _apiKeyController,
            decoration: InputDecoration(
              labelText: 'API Key',
              hintText: 'sk-...',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              filled: true,
              fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
              suffixIcon: IconButton(
                icon: Icon(
                  _obscureKey ? Icons.visibility_off : Icons.visibility,
                ),
                onPressed: () => setState(() => _obscureKey = !_obscureKey),
              ),
            ),
            obscureText: _obscureKey,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _baseUrlController,
            decoration: InputDecoration(
              labelText: 'API Base URL',
              hintText: 'https://api.deepseek.com',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              filled: true,
              fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
            ),
          ),
          Wrap(
            spacing: 8,
            children: [
              ActionChip(
                label: const Text(
                  'Local Server',
                  style: TextStyle(fontSize: 12),
                ),
                tooltip: 'For local Llama.cpp or LM Studio',
                onPressed: () =>
                    _baseUrlController.text = 'http://192.168.1.X:8080/v1',
              ),
              ActionChip(
                label: const Text(
                  'Ollama Cloud',
                  style: TextStyle(fontSize: 12),
                ),
                onPressed: () {
                  _baseUrlController.text = 'https://ollama.com/v1';
                  _modelController.text = 'gemma3:4b';
                },
              ),
              ActionChip(
                label: const Text('DeepSeek', style: TextStyle(fontSize: 12)),
                onPressed: () =>
                    _baseUrlController.text = 'https://api.deepseek.com',
              ),
              ActionChip(
                label: const Text('Groq', style: TextStyle(fontSize: 12)),
                onPressed: () =>
                    _baseUrlController.text = 'https://api.groq.com/openai/v1',
              ),
              ActionChip(
                label: const Text('Custom', style: TextStyle(fontSize: 12)),
                tooltip: 'Clear fields to enter custom API details',
                onPressed: () {
                  _baseUrlController.clear();
                  _apiKeyController.clear();
                  _modelController.clear();
                },
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _modelController,
                  decoration: InputDecoration(
                    labelText: 'Model',
                    hintText: 'deepseek-chat',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    filled: true,
                    fillColor: Theme.of(
                      context,
                    ).colorScheme.surfaceContainerHighest,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                onPressed: _fetchModels,
                icon: Icon(
                  Icons.cloud_download,
                  size: 18,
                  color: isDark ? Colors.black : Colors.white,
                ),
                label: Text(
                  'Fetch',
                  style: TextStyle(
                    color: isDark ? Colors.black : Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: isDark ? Colors.white : Colors.black,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          SwitchListTile(
            title: const Text('Disable Maximum Steps'),
            subtitle: const Text(
              '⚠️ Warning: Can cause infinite loops.',
              style: TextStyle(color: Colors.orange),
            ),
            value: _disableMaxSteps,
            onChanged: (bool value) {
              setState(() {
                _disableMaxSteps = value;
              });
            },
          ),
          if (!_disableMaxSteps) ...[
            Text(
              'Maximum Steps Per Task: ${_maxSteps.toInt()}',
              style: const TextStyle(fontWeight: FontWeight.w500),
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
            ),
          ],

          const Divider(height: 32),
          Text(
            'Advanced Model Settings',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          SwitchListTile(
            title: const Text('Use Screen Compression'),
            subtitle: const Text('Removes unnecessary elements to save tokens'),
            value: _useScreenCompression,
            onChanged: (bool value) {
              setState(() {
                _useScreenCompression = value;
              });
            },
            contentPadding: EdgeInsets.zero,
          ),
          SwitchListTile(
            title: const Text('Send System Prompt'),
            subtitle: const Text(
              'Turn OFF for custom LoRA models trained without it',
            ),
            value: _useSystemPrompt,
            onChanged: (bool value) {
              setState(() {
                _useSystemPrompt = value;
              });
            },
            contentPadding: EdgeInsets.zero,
          ),
          TextField(
            controller: _maxTokensController,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: 'Context Limit (Max Tokens)',
              hintText: '1024',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              filled: true,
              fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Temperature: ${_temperature.toStringAsFixed(2)}',
            style: const TextStyle(fontWeight: FontWeight.w500),
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
          ),

          ListTile(
            title: const Text('Task History'),
            subtitle: const Text('View past tasks and their outcomes'),
            trailing: const Icon(Icons.arrow_forward_ios, size: 16),
            leading: const Icon(Icons.history),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const TaskHistoryScreen(),
                ),
              );
            },
          ),
          const Divider(height: 32),

          // Floating Assistant Settings
          Text(
            'Floating Assistant (Experimental)',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          SwitchListTile(
            title: const Text('Enable Floating Agent Icon'),
            subtitle: const Text('Assign tasks without opening the app'),
            value: _floatingIconEnabled,
            onChanged: (val) async {
              if (val) {
                bool? isGranted =
                    await FlutterOverlayWindow.isPermissionGranted();
                if (isGranted != true) {
                  bool? result = await FlutterOverlayWindow.requestPermission();
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
                    overlayTitle: "PrivateAgent",
                    overlayContent: "Floating Assistant",
                    flag: OverlayFlag.focusPointer,
                    alignment: OverlayAlignment.centerRight,
                    visibility: NotificationVisibility.visibilitySecret,
                    positionGravity: PositionGravity.auto,
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
            },
            contentPadding: EdgeInsets.zero,
          ),

          const Divider(height: 32),

          // Telegram Settings
          Text(
            'Telegram Remote Access (Optional)',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _telegramTokenController,
            decoration: InputDecoration(
              labelText: 'Telegram Bot Token',
              hintText: '123456:ABC-DEF1234ghIkl-zyx57W2v1u123ew11',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              filled: true,
              fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
            ),
          ),
          SwitchListTile(
            title: const Text('Enable Telegram Bot'),
            subtitle: const Text('Allows remote control via Telegram chat'),
            value: _telegramEnabled,
            onChanged: (val) {
              setState(() => _telegramEnabled = val);
            },
            contentPadding: EdgeInsets.zero,
          ),
          const SizedBox(height: 12),
          ElevatedButton.icon(
            onPressed: _saveApiSettings,
            icon: Icon(
              Icons.save,
              color: isDark ? Colors.black : Colors.white,
            ),
            label: Text(
              'Save Settings',
              style: TextStyle(
                color: isDark ? Colors.black : Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: isDark ? Colors.white : Colors.black,
              minimumSize: const Size(double.infinity, 48),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),

          const Divider(height: 32),

          // Permissions
          Text(
            'Permissions',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          Card(
            color: isDark ? const Color(0xFF1E1E26) : const Color(0xFFF9F9FB),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Column(
                children: _buildPermissionTiles(),
              ),
            ),
          ),

          const Divider(height: 32),

          // Accessibility Service
          Text(
            'Screen Control (Accessibility)',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            'Required for reading screen content and performing taps, scrolls, and typing in other apps.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          _buildAccessibilityCard(),

          const Divider(height: 32),

          // Shizuku (Hidden per user request)
          if (false) ...[
            Text(
              'Shizuku (Optional)',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'Shizuku allows extra features like toggling WiFi, force-stopping apps, and running ADB commands without root.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            _buildShizukuCard(),
            const Divider(height: 32),
          ],

          // About / Links
          Text(
            'About',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Project Repository'),
            subtitle: const Text('View the official source code on GitHub'),
            onTap: () {
              launchUrl(
                Uri.parse('https://github.com/orailnoor/private-agent'),
                mode: LaunchMode.externalApplication,
              );
            },
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Orailnoor on YouTube'),
            subtitle: const Text('Subscribe for project updates and tutorials'),
            onTap: () {
              launchUrl(
                Uri.parse('https://www.youtube.com/orailnoor'),
                mode: LaunchMode.externalApplication,
              );
            },
          ),

          const SizedBox(height: 32),
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
            ? const Icon(Icons.check_circle, color: Colors.green)
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
            color: isGranted ? Colors.green : Colors.orange,
            fontSize: 12,
          ),
        ),
      );
    }).toList();

    // Add Overlay Permission tile
    list.add(
      ListTile(
        leading: const Icon(Icons.layers),
        title: const Text('Display Over Other Apps (Floating Bubble)'),
        trailing: _isOverlayPermissionGranted
            ? const Icon(Icons.check_circle, color: Colors.green)
            : TextButton(
                onPressed: () async {
                  await FlutterOverlayWindow.requestPermission();
                  final granted = await FlutterOverlayWindow.isPermissionGranted();
                  setState(() {
                    _isOverlayPermissionGranted = granted;
                  });
                },
                child: const Text('Grant'),
              ),
        subtitle: Text(
          _isOverlayPermissionGranted ? 'Granted' : 'Not granted',
          style: TextStyle(
            color: _isOverlayPermissionGranted ? Colors.green : Colors.orange,
            fontSize: 12,
          ),
        ),
      ),
    );

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
