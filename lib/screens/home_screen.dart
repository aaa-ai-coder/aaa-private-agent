import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/chat_message.dart';
import '../models/language_config.dart';
import '../services/ai_service.dart';
import '../services/action_handler.dart';
import '../services/backup_service.dart';
import '../services/voice_service.dart';
import '../services/database_service.dart';
import '../widgets/message_bubble.dart';
import '../widgets/quick_actions.dart';
import '../widgets/home_drawer.dart';
import '../widgets/home_background_glows.dart';
import '../widgets/home_mode_selector.dart';
import '../widgets/agent_status_bar.dart';
import '../widgets/home_empty_state.dart';
import '../widgets/home_input_bar.dart';
import '../widgets/model_picker_sheet.dart';
import '../widgets/api_warning_banner.dart';
import '../services/telegram_service.dart';
import '../services/chat_history_service.dart';
import '../services/notification_service.dart';
import '../services/storage_service.dart';
import 'settings_screen.dart';
import 'task_history_screen.dart';
import 'accounts_screen.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:share_plus/share_plus.dart';
import '../main.dart';
import '../config/feature_flags.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final AiService _aiService = AiService.instance;
  final ActionHandler _actionHandler = ActionHandler();
  final VoiceService _voiceService = VoiceService();
  final NotificationService _notificationService = NotificationService();
  late final TelegramService _telegramService;

  final List<ChatMessage> _messages = [];
  bool _isLoading = false;
  bool _isListening = false;
  bool _continuousVoiceMode = false;

  // Custom switch state: 'chat' or 'agent'
  String _mode = 'chat';

  // Chat Session state tracking
  String _sessionId = 'local_${DateTime.now().millisecondsSinceEpoch}';
  String _sessionTitle = '';

  AppLifecycleState _appLifecycleState = AppLifecycleState.resumed;
  Timer? _overlayHistoryTimer;

  /// Human-friendly label for the active AI backend, falling back to the
  /// endpoint host so switching providers (e.g. Puter) shows correctly even
  /// before any custom key is saved.
  String get _providerLabel {
    final url = _aiService.baseUrl;
    if (url.contains('api.puter.com')) return 'Puter.js AI';
    if (url.contains('pollinations.ai')) return 'Free Keyless AI';
    if (url.isNotEmpty) {
      final host = Uri.tryParse(url)?.host ?? '';
      if (host.isNotEmpty) return host;
    }
    return 'AI Provider';
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _telegramService = TelegramService(_actionHandler, _aiService);
    _initServices();
    _startOverlayHistorySync();
    // Register as the handler for overlay bubble tasks
    onOverlayTask = _onOverlayTask;
  }

  Future<void> _initServices() async {
    await _aiService.init();
    await _notificationService.requestPermission();
    await _voiceService.init();
    await _telegramService.init();
    await _actionHandler.shizuku.checkAvailability();

    // Seed default preferences that may not have been set yet
    final prefs = await SharedPreferences.getInstance();
    if (!prefs.containsKey('auto_read_tts')) {
      await prefs.setBool('auto_read_tts', true);
    }

    // Load saved voice language
    final langCode = prefs.getString('voice_language') ?? 'en';
    final savedLang = LanguageConfig.findByCode(langCode);
    await _voiceService.setLanguage(savedLang);

    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _saveSession() async {
    if (_messages.isEmpty) return;
    final userId = authService.userId;
    if (userId == null) return;

    if (_sessionTitle.isEmpty) {
      final firstUserMsg = _messages.firstWhere(
        (m) => m.isUser,
        orElse: () => ChatMessage(role: 'user', content: 'New Chat'),
      );
      _sessionTitle = firstUserMsg.content.length > 28
          ? '${firstUserMsg.content.substring(0, 25)}...'
          : firstUserMsg.content;
    }

    if (_sessionId.startsWith('local_')) {
      final newId = await DatabaseService.createSession(
        userId, _sessionTitle,
      );
      _sessionId = newId;
    } else {
      await DatabaseService.updateSessionTitle(_sessionId, _sessionTitle);
    }

    final lastMsg = _messages.last;
    await DatabaseService.saveMessage(
      sessionId: _sessionId,
      userId: userId,
      role: lastMsg.role,
      content: lastMsg.content,
      actionResult: lastMsg.actionResult?.toJson(),
    );

    final session = ChatSession(
      id: _sessionId,
      title: _sessionTitle,
      timestamp: DateTime.now(),
      messages: _messages.map((m) => m.toJson()).toList(),
    );
    await ChatHistoryService.saveSession(session);

    // Fire-and-forget: mirror to Firebase when auto-backup is enabled.
    await BackupService.maybeAutoBackup(userId);
  }

  /// Wraps [_saveSession] so a Supabase sync failure can never block the chat
  /// or leave the UI stuck in a loading state.
  Future<void> _safeSaveSession() async {
    try {
      await _saveSession();
    } catch (e) {
      developer.log('Failed to save session: $e', name: 'PrivateAgent');
    }
  }

  Future<void> _sendMessage(String text) async {
    if (!mounted) return;
    if (text.trim().isEmpty) return;

    final userMessage = ChatMessage(role: 'user', content: text.trim());
    setState(() {
      _messages.add(userMessage);
      _isLoading = true;
    });
    _updateOverlayState();
    _textController.clear();
    _scrollToBottom();
    await _safeSaveSession();

    await _streamAssistantResponse(text.trim(), isAgent: _mode == 'agent');
  }

  /// Deletes a message and rebuilds the in-memory AI history so subsequent
  /// turns don't reference removed content.
  Future<void> _deleteMessage(int index) async {
    if (_isLoading) return;
    if (index < 0 || index >= _messages.length) return;
    setState(() {
      _messages.removeAt(index);
    });
    _rebuildAiHistory();
    _sendOverlayHistorySnapshot();
    await _safeSaveSession();
  }

  /// Regenerates the assistant answer for the given bubble by trimming the
  /// conversation back to its preceding user message and re-streaming a new
  /// response. Progress + action-result bubbles in between are discarded.
  Future<void> _regenerateResponse(int index) async {
    if (_isLoading) return;
    if (index < 0 || index >= _messages.length) return;
    if (_messages[index].isUser) return;

    int ui = index - 1;
    while (ui >= 0 && _messages[ui].isUser) {
      ui--;
    }
    if (ui < 0) return;
    final userContent = _messages[ui].content;

    setState(() {
      _messages.removeRange(ui + 1, _messages.length);
      _isLoading = true;
    });
    _rebuildAiHistory();
    _sendOverlayHistorySnapshot();
    await _safeSaveSession();
    await _streamAssistantResponse(userContent, isAgent: _mode == 'agent');
  }

  /// Replays the current visible conversation into the AI service history so
  /// the next request stays coherent after edits.
  void _rebuildAiHistory() {
    _aiService.clearHistory();
    for (final m in _messages) {
      _aiService.addHistoryMessage(m.role, m.content);
    }
  }

  /// Streams an assistant response for [text] and appends it to the chat,
  /// handling action parsing, voice output and error reporting.
  Future<void> _streamAssistantResponse(String text, {required bool isAgent}) async {
    if (!mounted) return;

    // Add empty placeholder assistant message for streaming
    final assistantMessage = ChatMessage(role: 'assistant', content: '');
    setState(() {
      _messages.add(assistantMessage);
    });
    final assistantIndex = _messages.length - 1;

    try {
      final stream = _aiService
          .sendMessageStream(text, isAgentMode: isAgent)
          .timeout(
            const Duration(seconds: 90),
            onTimeout: (sink) {
              sink.addError(
                TimeoutException(
                  'The model did not return visible text within 90 seconds.',
                ),
              );
              sink.close();
            },
          );
      String accumulated = '';

      await for (final chunk in stream) {
        accumulated += chunk;
        if (mounted) {
          setState(() {
            _messages[assistantIndex] = ChatMessage(
              role: 'assistant',
              content: accumulated,
            );
          });
          _scrollToBottom();
        }
      }
      await _safeSaveSession();

      // Check if it's an action
      final action = _aiService.parseAction(accumulated);

      if (action != null) {
        // If it's an action, we remove the raw JSON message from display
        setState(() {
          _messages.removeAt(assistantIndex);
        });

        await _showTaskProgressOverlay('Starting: ${text.trim()}');

        // Execute the action (pass aiService for multi-step tasks)
        final result = await _actionHandler.execute(
          action,
          aiService: _aiService,
          onProgress: (msg) {
            developer.log('Task progress: $msg', name: 'PrivateAgent');
            _sendOverlayEvent('OVERLAY_PROGRESS', msg);
            if (mounted) {
              setState(() {
                _messages.add(
                  ChatMessage(role: 'assistant', content: '⏳ $msg'),
                );
              });
              _scrollToBottom();
            }
          },
        );

        setState(() {
          _messages.add(
            ChatMessage(
              role: 'assistant',
              content: result.success
                  ? (action.response.isNotEmpty
                        ? action.response
                        : (result.details ?? 'Done.'))
                  : (action.response.isNotEmpty
                        ? '${action.response}\n\n⚠️ ${result.details}'
                        : '⚠️ ${result.details}'),
              actionResult: result,
            ),
          );
        });
        _sendOverlayEvent(
          'OVERLAY_TASK_FINISHED',
          result.success
              ? (result.details ?? 'Task complete.')
              : 'Task failed: ${result.details ?? 'Unknown error'}',
        );
        if (action.action != 'execute_task') {
          await _notificationService.showTaskCompleteNotification(
            result.success ? 'Task Completed' : 'Task Failed',
            result.details ??
                (result.success
                    ? 'Agent finished its goal.'
                    : 'Agent could not complete the task.'),
          );
        }
        await _safeSaveSession();
      } else {
        // Plain text response, speak if auto-read or continuous voice mode is enabled
        final prefs = await SharedPreferences.getInstance();
        final autoRead = prefs.getBool('auto_read_tts') ?? true;
        if (autoRead || _continuousVoiceMode) {
          // Detect AI response language and switch TTS
          final detectedLang = LanguageConfig.detectFromText(accumulated);
          if (detectedLang.code != _voiceService.currentLanguage.code) {
            await _voiceService.setLanguage(detectedLang);
            await prefs.setString('voice_language', detectedLang.code);
          }
          _voiceService.speak(
            accumulated,
            onComplete: () {
              if (_continuousVoiceMode && mounted && !_isLoading) {
                _toggleVoice();
              }
            },
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          if (_messages.isNotEmpty && _messages.length > assistantIndex) {
            _messages.removeAt(assistantIndex);
          }
          _messages.add(
            ChatMessage(
              role: 'assistant',
              content: 'Error: ${e.toString().replaceFirst('Exception: ', '')}',
            ),
          );
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        _scrollToBottom();
        _updateOverlayState();
      }
    }
  }

  Future<void> _showTaskProgressOverlay(String message) async {
    if (!FeatureFlags.floatingOverlayEnabled) return;
    if (!FeatureFlags.floatingIconEnabled) return;
    if (!await FlutterOverlayWindow.isPermissionGranted()) return;

    // Never cover PrivateAgent itself. The lifecycle observer will create the
    // overlay after an automated action moves this app to the background.
    if (_appLifecycleState != AppLifecycleState.paused) return;

    if (!await FlutterOverlayWindow.isActive()) {
      await FlutterOverlayWindow.showOverlay(
        enableDrag: true,
        overlayTitle: 'AAA Private Agent',
        overlayContent: 'Performing task...',
        flag: OverlayFlag.focusPointer,
        alignment: OverlayAlignment.centerRight,
        visibility: NotificationVisibility.visibilitySecret,
        positionGravity: PositionGravity.auto,
        startPosition: const OverlayPosition(0, 200),
        width: 56,
        height: 56,
      );
      await Future<void>.delayed(const Duration(milliseconds: 300));
    }

    // Keep the overlay minimized during automation. The user can still tap the
    // bubble to open the full conversation whenever they choose.
    _sendOverlayEvent('OVERLAY_TASK_STARTED', message);
  }

  void _sendOverlayEvent(String type, String message) {
    if (!FeatureFlags.floatingOverlayEnabled) return;
    final safeMessage = message.replaceAll('|', ' ');
    unawaited(
      FlutterOverlayWindow.shareData(
        '$type|$safeMessage',
      ).timeout(const Duration(seconds: 2)).catchError((Object _) {}),
    );
  }

  Future<void> _sendOverlayHistorySnapshot() async {
    if (!FeatureFlags.floatingOverlayEnabled) return;
    final history = base64Encode(
      utf8.encode(
        jsonEncode(_messages.map((message) => message.toJson()).toList()),
      ),
    );
    try {
      await FlutterOverlayWindow.shareData(
        'OVERLAY_HISTORY|$history',
      ).timeout(const Duration(seconds: 2));
    } catch (_) {}
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _toggleVoice() async {
    if (_isListening) {
      await _voiceService.stopListening();
      setState(() => _isListening = false);
      return;
    }

    setState(() => _isListening = true);

    await _voiceService.startListening(
      onResult: (text) {
        _sendMessage(text);
      },
      onDone: () {
        if (mounted) {
          setState(() => _isListening = false);
        }
      },
    );
  }

  void _startNewChat() {
    setState(() {
      _sessionId = 'local_${DateTime.now().millisecondsSinceEpoch}';
      _sessionTitle = '';
      _messages.clear();
      _aiService.clearHistory();
    });
  }

  Future<void> _exportChatSession() async {
    if (_messages.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No chat history to export.')),
      );
      return;
    }

    final buffer = StringBuffer();
    buffer.writeln('# AAA Private Agent - Chat Export');
    buffer.writeln('Date: ${DateTime.now().toLocal().toString().split('.')[0]}\n');

    for (final m in _messages) {
      final sender = m.isUser ? 'User' : 'AAA Agent';
      buffer.writeln('### $sender');
      buffer.writeln('${m.content}\n');
    }

    final exportedText = buffer.toString();
    await SharePlus.instance.share(
      ShareParams(text: exportedText, subject: 'AAA Private Agent Chat Export'),
    );
  }

  Future<void> _loadSessionMessages(String sessionId, String title) async {
    try {
      final messages = await DatabaseService.getMessages(sessionId);
      if (!mounted) return;
      setState(() {
        _sessionId = sessionId;
        _sessionTitle = title;
        _messages.clear();
        _aiService.clearHistory();
        for (final m in messages) {
          final msg = ChatMessage(
            role: m['role'] as String,
            content: m['content'] as String,
            timestamp: DateTime.parse(m['created_at'] as String),
            actionResult: m['action_result'] != null
                ? AgentActionResult.fromJson(
                    Map<String, dynamic>.from(m['action_result'] as Map),
                  )
                : null,
          );
          _messages.add(msg);
          if (msg.actionResult == null) {
            _aiService.addHistoryMessage(msg.role, msg.content);
          }
        }
      });
      _scrollToBottom();
    } catch (e) {
      developer.log('Failed to load session messages: $e');
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _overlayHistoryTimer?.cancel();
    // Never leave a dangling handler that could call setState on a disposed state.
    if (onOverlayTask != null && identical(onOverlayTask, _onOverlayTask)) {
      onOverlayTask = null;
    }
    _textController.dispose();
    _scrollController.dispose();
    _voiceService.dispose();
    _telegramService.dispose();
    super.dispose();
  }

  void _onOverlayTask(String task) {
    _sendMessage(task);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    setState(() {
      _appLifecycleState = state;
    });
    if (state == AppLifecycleState.resumed) {
      _startOverlayHistorySync();
      unawaited(_handleAppForegrounded());
    } else {
      _overlayHistoryTimer?.cancel();
      _updateOverlayState();
    }
  }

  void _startOverlayHistorySync() {
    _overlayHistoryTimer?.cancel();
    if (!FeatureFlags.floatingOverlayEnabled) return;
    unawaited(_importOverlayChatHistory());
    _overlayHistoryTimer = Timer.periodic(const Duration(milliseconds: 500), (
      _,
    ) {
      if (_appLifecycleState == AppLifecycleState.resumed) {
        unawaited(_importOverlayChatHistory());
      }
    });
  }

  Future<void> _handleAppForegrounded() async {
    await _updateOverlayState();
    await _importOverlayChatHistory();
  }

  Future<void> _importOverlayChatHistory() async {
    if (!FeatureFlags.floatingOverlayEnabled) return;
    if (_importingOverlayHistory) return;
    _importingOverlayHistory = true;
    try {
      final handoff = await ChatHistoryService.consumeOverlayMessages();
      if (!mounted || handoff.isEmpty) return;

      final imported = handoff.map(ChatMessage.fromJson).toList();
      for (final message in imported) {
        if (message.actionResult == null) {
          _aiService.addHistoryMessage(message.role, message.content);
        }
      }
      setState(() {
        _messages.addAll(imported);
      });
      _scrollToBottom();
      await _safeSaveSession();
    } finally {
      _importingOverlayHistory = false;
    }
  }

  int _overlayUpdateGeneration = 0;
  bool _importingOverlayHistory = false;

  Future<void> _updateOverlayState() async {
    if (!FeatureFlags.floatingOverlayEnabled) return;
    if (!FeatureFlags.floatingIconEnabled) return;
    final generation = ++_overlayUpdateGeneration;
    final isBackground = _appLifecycleState == AppLifecycleState.paused;
    final shouldBeActive = isBackground;

    bool granted = await FlutterOverlayWindow.isPermissionGranted();
    if (!granted || generation != _overlayUpdateGeneration) return;

    bool active = await FlutterOverlayWindow.isActive();
    if (generation != _overlayUpdateGeneration) return;
    if (shouldBeActive && !active) {
      await Future.delayed(const Duration(milliseconds: 200));
      if (generation != _overlayUpdateGeneration) return;
      if (_appLifecycleState != AppLifecycleState.paused) return;
      if (await FlutterOverlayWindow.isActive()) return;
      await FlutterOverlayWindow.showOverlay(
        enableDrag: true,
        overlayTitle: "AAA Private Agent",
                overlayContent: _isLoading
                    ? "AAA Private Agent - Performing task..."
                    : "AAA Private Agent - Floating Assistant",
        flag: OverlayFlag.focusPointer,
        alignment: OverlayAlignment.centerRight,
        visibility: NotificationVisibility.visibilitySecret,
        positionGravity: PositionGravity.auto,
        startPosition: const OverlayPosition(0, 200),
        width: 56,
        height: 56,
      );
      if (_isLoading && _appLifecycleState == AppLifecycleState.paused) {
        await Future<void>.delayed(const Duration(milliseconds: 250));
        await _sendOverlayHistorySnapshot();
        await Future<void>.delayed(const Duration(milliseconds: 250));
        if (_isLoading && _appLifecycleState == AppLifecycleState.paused) {
          await _sendOverlayHistorySnapshot();
        }
      }
    } else if (shouldBeActive && active && _isLoading) {
      await _sendOverlayHistorySnapshot();
    } else if (!shouldBeActive && active) {
      try {
        await FlutterOverlayWindow.shareData(
          'OVERLAY_RESET|',
        ).timeout(const Duration(milliseconds: 150));
      } catch (_) {}
      await Future<void>.delayed(const Duration(milliseconds: 50));
      if (generation != _overlayUpdateGeneration) return;
      if (_appLifecycleState == AppLifecycleState.paused) return;
      await FlutterOverlayWindow.closeOverlay();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0C0A15) : const Color(0xFFFFFFFF),
      appBar: AppBar(
        title: RichText(
          text: TextSpan(
            style: TextStyle(
              fontSize: 20,
              color: isDark ? Colors.white : const Color(0xFF1E293B),
            ),
            children: [
              TextSpan(
                text: 'AAA ',
                style: TextStyle(
                  fontWeight: FontWeight.w300,
                  color: Theme.of(context).colorScheme.primary,
                  letterSpacing: -0.5,
                ),
              ),
              TextSpan(
                text: 'Private',
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  color: Theme.of(context).colorScheme.primary,
                  letterSpacing: -0.5,
                ),
              ),
              TextSpan(
                text: 'Agent',
                style: TextStyle(
                  fontWeight: FontWeight.w400,
                  letterSpacing: -0.5,
                ),
              ),
            ],
          ),
        ),
        backgroundColor: Colors.transparent,
        scrolledUnderElevation: 0,
        leading: Builder(
          builder: (context) => IconButton(
            icon: const Icon(Icons.menu_rounded),
            tooltip: 'Menu',
            onPressed: () => Scaffold.of(context).openDrawer(),
          ),
        ),
        actions: [
          IconButton(
            icon: Icon(
              _continuousVoiceMode
                  ? Icons.record_voice_over_rounded
                  : Icons.voice_over_off_rounded,
              color: _continuousVoiceMode ? Colors.tealAccent : null,
            ),
            tooltip: _continuousVoiceMode
                ? 'Hands-Free Voice Mode Active'
                : 'Turn on Hands-Free Voice Mode',
            onPressed: () {
              HapticFeedback.selectionClick();
              setState(() {
                _continuousVoiceMode = !_continuousVoiceMode;
              });
              if (_continuousVoiceMode) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Hands-Free Voice Mode ON: AI will speak and listen continuously!'),
                    backgroundColor: Colors.teal,
                  ),
                );
                if (!_isListening && !_voiceService.isSpeaking) {
                  _toggleVoice();
                }
              } else {
                _voiceService.stopSpeaking();
                _voiceService.stopListening();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Hands-Free Voice Mode OFF'),
                  ),
                );
              }
            },
          ),
          IconButton(
            icon: const Icon(Icons.share_rounded),
            tooltip: 'Export & Share Chat',
            onPressed: _messages.isEmpty ? null : _exportChatSession,
          ),
          IconButton(
            icon: const Icon(Icons.psychology_rounded),
            tooltip: 'Quick AI Model Switcher',
            onPressed: () => ModelPickerSheet.show(context, _aiService, () {
              setState(() {});
            }),
          ),
          IconButton(
            icon: const Icon(Icons.add_comment_outlined),
            tooltip: 'New chat',
            onPressed: _isLoading ? null : _startNewChat,
          ),
          // Settings Action
          IconButton(
            icon: const Icon(Icons.settings_rounded),
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => SettingsScreen(
                    aiService: _aiService,
                    shizukuService: _actionHandler.shizuku,
                    screenAutomationService: _actionHandler.screenAutomation,
                    telegramService: _telegramService,
                  ),
                ),
              );
              await _actionHandler.shizuku.checkAvailability();
              if (mounted) setState(() {});
            },
          ),
        ],
      ),
      drawer: HomeDrawer(
        isDark: isDark,
        currentSessionId: _sessionId,
        onNewChat: _startNewChat,
        onLoadSession: _loadSessionMessages,
        onTaskHistory: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const TaskHistoryScreen()),
        ),
        onSettings: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => SettingsScreen(
                aiService: _aiService,
                shizukuService: _actionHandler.shizuku,
                screenAutomationService: _actionHandler.screenAutomation,
                telegramService: _telegramService,
              ),
            ),
          );
          await _actionHandler.shizuku.checkAvailability();
          if (mounted) setState(() {});
        },
      ),
      body: Stack(
        children: [
          // Background mesh glows
          HomeBackgroundGlows(isDark: isDark),

          Positioned.fill(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 100, sigmaY: 100),
              child: Container(color: Colors.transparent),
            ),
          ),

          Column(
            children: [
              // Pill selector switcher
              HomeModeSelector(
                currentMode: _mode,
                onModeChanged: (mode) {
                  HapticFeedback.lightImpact();
                  setState(() => _mode = mode);
                },
                isDark: isDark,
              ),

              // Agent dashboard status strip
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: AgentStatusBar(
                  providerName: _aiService.activeKey?.name ?? _providerLabel,
                  model: _aiService.model,
                  r2Configured: StorageService.isConfigured,
                  cloudSynced: authService.isLoggedIn,
                  isDark: isDark,
                  onOpenHealth: () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => AccountsScreen(
                          aiService: _aiService,
                          telegramService: _telegramService,
                        ),
                      ),
                    );
                    if (mounted) setState(() {});
                  },
                ),
              ),

              // API key warning banner
              if (!_aiService.isConfigured)
                ApiWarningBanner(
                  isDark: isDark,
                  onConfigure: () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => SettingsScreen(
                          aiService: _aiService,
                          shizukuService: _actionHandler.shizuku,
                          screenAutomationService: _actionHandler.screenAutomation,
                          telegramService: _telegramService,
                        ),
                      ),
                    );
                    if (mounted) setState(() {});
                  },
                ),

              // Chat content area
              Expanded(
                child: _messages.isEmpty
                    ? HomeEmptyState(
                        mode: _mode,
                        isDark: isDark,
                        onSend: _sendMessage,
                      )
                    : ListView.builder(
                        controller: _scrollController,
                        physics: const BouncingScrollPhysics(),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        itemCount: _messages.length,
                        itemBuilder: (context, index) {
                          return MessageBubble(
                            message: _messages[index],
                            onSpeakTap: () {
                              if (_voiceService.isSpeaking) {
                                _voiceService.stopSpeaking();
                              } else {
                                _voiceService.speak(_messages[index].content);
                              }
                            },
                            onDeleteTap: () => _deleteMessage(index),
                            onRegenerateTap: _messages[index].isUser
                                ? null
                                : () => _regenerateResponse(index),
                          );
                        },
                      ),
              ),

              // Think loading indicator
              if (_isLoading)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            Theme.of(context).colorScheme.secondary,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      ShaderMask(
                        shaderCallback: (bounds) => LinearGradient(
                          colors: [
                            Theme.of(context).colorScheme.primary,
                            Theme.of(context).colorScheme.secondary,
                          ],
                        ).createShader(bounds),
                        child: Text(
                          'Thinking...',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.redAccent.withValues(alpha: 0.3)),
                        ),
                        child: TextButton.icon(
                          onPressed: () {
                            _actionHandler.cancelTask();
                            setState(() {
                              _isLoading = false;
                            });
                          },
                          icon: const Icon(Icons.stop_circle_rounded, size: 16, color: Colors.redAccent),
                          label: const Text(
                            'Stop',
                            style: TextStyle(
                              color: Colors.redAccent,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

              // Quick Actions bar (shown when no messages)
              if (_messages.isEmpty)
                QuickActions(
                  onSend: _sendMessage,
                  isDark: isDark,
                ),

              // Custom Input bar
              HomeInputBar(
                controller: _textController,
                isListening: _isListening,
                isLoading: _isLoading,
                isDark: isDark,
                onMicTap: _toggleVoice,
                onSend: _sendMessage,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
