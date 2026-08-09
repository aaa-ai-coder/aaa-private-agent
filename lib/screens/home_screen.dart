import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/chat_message.dart';
import '../models/agent_action.dart';
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
import '../services/custom_commands_service.dart';
import '../services/notification_service.dart';
import '../services/storage_service.dart';
import '../services/scheduler_service.dart';
import '../services/memory_service.dart';
import '../services/offline_assistant_service.dart';
import '../services/bundled_llm_service.dart';
import '../widgets/home_header.dart';
import '../widgets/typing_indicator.dart';
import '../widgets/agent_orb.dart';
import 'settings_screen.dart';
import 'task_history_screen.dart';
import 'accounts_screen.dart';
import 'control_panel_screen.dart';
import 'about_screen.dart';
import 'discover_screen.dart';
import 'permissions_screen.dart';
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
  final Map<int, GlobalKey> _messageKeys = {};
  List<CustomCommand> _customCommands = [];
  int? _searchHighlightIndex;
  bool _isLoading = false;
  bool _stopRequested = false;
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
    unawaited(_initServicesSafe());
    _startOverlayHistorySync();
    unawaited(_loadCustomCommandsSafe());
    // Register as the handler for overlay bubble tasks
    onOverlayTask = _onOverlayTask;
  }

  /// Initializes services without ever crashing or blocking first render.
  Future<void> _initServicesSafe() async {
    try {
      await _initServices();
    } catch (e) {
      developer.log('Service init failed: $e', name: 'PrivateAgent');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _loadCustomCommandsSafe() async {
    try {
      await _loadCustomCommands();
    } catch (e) {
      developer.log('Custom commands load failed: $e', name: 'PrivateAgent');
    }
  }

  Future<void> _initServices() async {
    await _aiService.init();
    await _notificationService.requestPermission();
    await _voiceService.init();
    await _telegramService.init();
    await _actionHandler.shizuku.checkAvailability();
    await SchedulerService.instance.initialize();

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
      _stopRequested = false;
    });
    _updateOverlayState();
    _textController.clear();
    _scrollToBottom();
    await _safeSaveSession();

    final trimmed = text.trim();

    // On-device AI memory: remember facts about the user without any API call.
    final remembered = await MemoryService.tryRemember(trimmed);
    if (remembered != null) {
      setState(() {
        _isLoading = false;
        _messages.add(ChatMessage(role: 'assistant', content: remembered));
      });
      _scrollToBottom();
      await _safeSaveSession();
      await _speakIfEnabled(remembered);
      return;
    }

    // Offline Assistant mode: full on-device AI, no API key or network needed.
    final prefs = await SharedPreferences.getInstance();
    final useOffline = prefs.getBool('use_offline_ai') ?? false;
    if (useOffline) {
      setState(() {
        _isLoading = false;
      });
      await _handleOfflineMessage(trimmed);
      return;
    }

    // Automatic offline fallback: when the network is unreachable, answer
    // locally (bundled on-device LLM if ready, otherwise the intent assistant)
    // so the assistant never goes silent just because the phone lost signal.
    final bundledEnabled = prefs.getBool('use_bundled_llm') ?? true;
    if (bundledEnabled && !await _isProbablyOnline()) {
      setState(() {
        _isLoading = false;
      });
      await _handleOfflineMessage(trimmed);
      return;
    }

    await _streamAssistantResponse(trimmed, isAgent: _mode == 'agent');
  }

  /// Offline AI mode: prefers the built-in on-device LLM (bundled in the APK),
  /// then a user-configured local model (e.g. Ollama at localhost), and finally
  /// falls back to the instant intent-based assistant when no model is ready.
  Future<void> _handleOfflineMessage(String text) async {
    if (!mounted) return;

    final prefs = await SharedPreferences.getInstance();

    // 1) Built-in on-device AI: real LLM shipped inside the app itself.
    final bundledEnabled = prefs.getBool('use_bundled_llm') ?? true;
    if (bundledEnabled) {
      if (await BundledLlmService.instance.isExtracted()) {
        final bundledReply = await BundledLlmService.instance.complete(
          text,
          history: _recentHistory(),
        );
        if (bundledReply != null) {
          final bundledAction = _aiService.parseAction(bundledReply);
          if (bundledAction != null) {
            await _executeOfflineAction(bundledAction, text);
          } else {
            if (!mounted) return;
            setState(() {
              _messages.add(
                ChatMessage(role: 'assistant', content: bundledReply),
              );
            });
            _scrollToBottom();
            await _safeSaveSession();
            await _speakIfEnabled(bundledReply);
          }
          _updateOverlayState();
          return;
        }
      } else {
        // First offline use: prepare the bundled model in the background so
        // the next message is answered by the real on-device LLM.
        unawaited(_prepareBundledModel());
      }
    }

    // 2) User-configured local model (e.g. Ollama running on the phone).
    final localBase = prefs.getString('offline_llm_base_url') ??
        'http://127.0.0.1:11434/v1';
    final localModel =
        prefs.getString('offline_llm_model') ?? 'llama3.2';

    String? localReply;
    try {
      localReply = await _aiService.sendToLocalEndpoint(
        text,
        baseUrl: localBase,
        model: localModel,
      );
    } catch (e) {
      developer.log('Local model unavailable: $e', name: 'PrivateAgent');
    }

    if (localReply != null && localReply.trim().isNotEmpty) {
      final reply = localReply;
      final localAction = _aiService.parseAction(reply);
      if (localAction != null) {
        await _executeOfflineAction(localAction, text);
      } else {
        if (!mounted) return;
        setState(() {
          _messages.add(
            ChatMessage(role: 'assistant', content: reply),
          );
        });
        _scrollToBottom();
        await _safeSaveSession();
        await _speakIfEnabled(reply);
      }
      _updateOverlayState();
      return;
    }

    // 3) Instant intent-based assistant (no model at all).
    final result = OfflineAssistantService.handle(text);
    if (result.action != null) {
      await _executeOfflineAction(result.action!, text);
    } else {
      if (!mounted) return;
      setState(() {
        _messages.add(ChatMessage(role: 'assistant', content: result.reply));
      });
      _scrollToBottom();
      await _safeSaveSession();
      await _speakIfEnabled(result.reply);
    }
    _updateOverlayState();
  }

  /// Builds a short alternating [user, assistant] history from the chat for
  /// the bundled on-device LLM, capped to the last few turns. The current
  /// (just-sent) message is passed separately, so it is excluded here.
  List<String> _recentHistory() {
    final stack = <String>[];
    for (var i = _messages.length - 2; i >= 0 && stack.length < 8; i--) {
      final m = _messages[i];
      if ((!m.isUser && m.role != 'assistant') || m.content.trim().isEmpty) {
        continue;
      }
      stack.add(m.content.trim());
    }
    return stack.reversed.toList();
  }

  /// Kicks off the one-time extraction of the bundled model. Any failure is
  /// logged and ignored so chat never blocks on it.
  Future<void> _prepareBundledModel() async {
    try {
      await BundledLlmService.instance.extract();
    } catch (e) {
      developer.log('Bundled model extraction failed: $e', name: 'PrivateAgent');
    }
  }

  bool? _onlineCache;
  DateTime _onlineCacheAt = DateTime.fromMillisecondsSinceEpoch(0);

  /// Cheap cached connectivity probe used to auto-route to the on-device AI.
  /// Re-checks at most every 20 seconds to avoid per-message overhead.
  Future<bool> _isProbablyOnline() async {
    final now = DateTime.now();
    if (_onlineCache != null &&
        now.difference(_onlineCacheAt).inSeconds < 20) {
      return _onlineCache!;
    }
    final result = await _probeNetwork();
    _onlineCache = result;
    _onlineCacheAt = now;
    return result;
  }

  Future<bool> _probeNetwork() async {
    final probe = _aiService.baseUrl.isNotEmpty
        ? _aiService.baseUrl
        : 'https://www.gstatic.com/generate_204';
    final uri = Uri.tryParse(probe);
    if (uri == null) return true;
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 4);
    try {
      final request = await client
          .getUrl(uri)
          .timeout(const Duration(seconds: 4));
      final response = await request
          .close()
          .timeout(const Duration(seconds: 4));
      return response.statusCode >= 200 && response.statusCode < 500;
    } catch (_) {
      return false;
    } finally {
      client.close(force: true);
    }
  }

  Future<void> _executeOfflineAction(
    AgentAction action,
    String text,
  ) async {
    await _showTaskProgressOverlay('Starting: $text');
    final actionResult = await _actionHandler.execute(
      action,
      aiService: _aiService,
      onProgress: (msg) {
        if (mounted) {
          setState(() {
            _messages.add(ChatMessage(role: 'assistant', content: '⏳ $msg'));
          });
          _scrollToBottom();
        }
      },
    );
    if (!mounted) return;
    setState(() {
      _messages.add(
        ChatMessage(
          role: 'assistant',
          content: actionResult.success
              ? (action.response.isNotEmpty
                  ? action.response
                  : (actionResult.details ?? 'Done.'))
              : '⚠️ ${actionResult.details ?? 'Action could not be completed.'}',
          actionResult: actionResult,
        ),
      );
    });
    _scrollToBottom();
    _sendOverlayEvent(
      'OVERLAY_TASK_FINISHED',
      actionResult.success
          ? (actionResult.details ?? 'Task complete.')
          : 'Task failed: ${actionResult.details ?? 'Unknown error'}',
    );
    await _safeSaveSession();
  }

  /// Speaks [text] when auto-read TTS is enabled (or voice mode is active).
  Future<void> _speakIfEnabled(String text) async {
    if (text.isEmpty || !mounted) return;
    final prefs = await SharedPreferences.getInstance();
    final autoRead = prefs.getBool('auto_read_tts') ?? true;
    if (autoRead || _continuousVoiceMode) {
      final detectedLang = LanguageConfig.detectFromText(text);
      if (detectedLang.code != _voiceService.currentLanguage.code) {
        await _voiceService.setLanguage(detectedLang);
        await prefs.setString('voice_language', detectedLang.code);
      }
      _voiceService.speak(text);
    }
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
      _stopRequested = false;
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
        if (_stopRequested) break;
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

      // User pressed Stop: keep whatever partial text arrived and do not
      // attempt action execution or voice output.
      if (_stopRequested) return;

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
      _messageKeys.clear();
      _searchHighlightIndex = null;
    });
  }

  Future<void> _loadCustomCommands() async {
    final commands = await CustomCommandsService.load();
    if (!mounted) return;
    setState(() => _customCommands = commands);
  }

  /// Editor for user-defined quick command chips (add / remove).
  Future<void> _openQuickActionsEditor() async {
    final labelCtrl = TextEditingController();
    final commandCtrl = TextEditingController();
    IconData selectedIcon = Icons.star_rounded;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            final icons = kCommandIcons;
            return Padding(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 12,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
              ),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF241B21) : Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: isDark
                        ? const Color(0xFFFF6B4A).withValues(alpha: 0.25)
                        : const Color(0xFFF0E3D3),
                  ),
                ),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Custom Quick Commands',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Pin your own frequent requests as home-screen chips.',
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark
                              ? const Color(0xFFA8938C)
                              : const Color(0xFF8C7A6E),
                        ),
                      ),
                      const SizedBox(height: 12),
                      // Existing custom commands
                      if (_customCommands.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Text(
                            'No custom commands yet — add one below.',
                            style: TextStyle(
                              fontSize: 12.5,
                              color: isDark
                                  ? const Color(0xFFA8938C)
                                  : const Color(0xFF8C7A6E),
                            ),
                          ),
                        )
                      else
                        ...List.generate(_customCommands.length, (index) {
                          final c = _customCommands[index];
                          return ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            leading: Icon(
                              commandIcon(c.iconCode),
                              size: 20,
                              color: const Color(0xFFFF8A5C),
                            ),
                            title: Text(
                              c.label,
                              style: const TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            subtitle: Text(
                              c.command,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11.5,
                                color: isDark
                                    ? const Color(0xFFA8938C)
                                    : const Color(0xFF8C7A6E),
                              ),
                            ),
                            trailing: IconButton(
                              icon: const Icon(Icons.delete_outline_rounded,
                                  size: 20, color: Color(0xFFFF4D5E)),
                              onPressed: () async {
                                await CustomCommandsService.removeAt(index);
                                final updated =
                                    await CustomCommandsService.load();
                                setSheetState(() => _customCommands = updated);
                              },
                            ),
                          );
                        }),
                      const Divider(height: 20),
                      const Text(
                        'Add new command',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: labelCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Label (short, e.g. "Work email")',
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: commandCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Command (what the AI should do)',
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Pick an icon',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: isDark
                              ? const Color(0xFFA8938C)
                              : const Color(0xFF8C7A6E),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: icons.map((icon) {
                          final selected = icon == selectedIcon;
                          return InkWell(
                            borderRadius: BorderRadius.circular(12),
                            onTap: () => setSheetState(
                                () => selectedIcon = icon),
                            child: Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: selected
                                    ? const Color(0xFFFF6B4A)
                                        .withValues(alpha: 0.18)
                                    : (isDark
                                          ? const Color(0xFF2E2228)
                                          : const Color(0xFFF7EDE0)),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: selected
                                      ? const Color(0xFFFF6B4A)
                                      : Colors.transparent,
                                  width: 1.4,
                                ),
                              ),
                              child: Icon(
                                icon,
                                size: 20,
                                color: selected
                                    ? const Color(0xFFFF6B4A)
                                    : (isDark
                                          ? const Color(0xFFA8938C)
                                          : const Color(0xFF8C7A6E)),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 14),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: () async {
                            final label = labelCtrl.text.trim();
                            final command = commandCtrl.text.trim();
                            if (label.isEmpty || command.isEmpty) return;
                            final ok = await CustomCommandsService.add(
                              CustomCommand(
                                label: label,
                                command: command,
                                iconCode: selectedIcon.codePoint,
                              ),
                            );
                            if (!ok) {
                              ScaffoldMessenger.of(ctx).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                      'Maximum 12 custom commands reached.'),
                                ),
                              );
                              return;
                            }
                            final updated =
                                await CustomCommandsService.load();
                            setSheetState(() {
                              _customCommands = updated;
                              labelCtrl.clear();
                              commandCtrl.clear();
                            });
                          },
                          icon: const Icon(Icons.add_rounded, size: 18),
                          label: const Text('Add command'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );

    final updated = await CustomCommandsService.load();
    if (mounted) setState(() => _customCommands = updated);
  }

  /// Clears the current view without opening a new session.
  Future<void> _clearConversation() async {
    setState(() {
      _messages.clear();
      _aiService.clearHistory();
      _messageKeys.clear();
      _searchHighlightIndex = null;
    });
    _sendOverlayHistorySnapshot();
    await _safeSaveSession();
  }

  /// Asks the AI to condense the current conversation into a short summary
  /// bubble (added as a normal turn so it stays in the transcript).
  Future<void> _summarizeChat() async {
    if (_messages.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No conversation to summarize yet.')),
      );
      return;
    }
    await _sendMessage(
      'Summarize our conversation so far in a few concise bullet points '
      '(under 120 words). Highlight the main decisions and any actions taken.',
    );
  }

  /// Streams an AI helper turn (rewrite/translate) WITHOUT adding a user
  /// bubble — the result appears directly as a new assistant message.
  Future<void> _aiAssistMessage(String prompt) async {
    if (_isLoading) return;
    final assistantMessage = ChatMessage(role: 'assistant', content: '');
    setState(() {
      _messages.add(assistantMessage);
      _isLoading = true;
      _stopRequested = false;
    });
    final assistantIndex = _messages.length - 1;
    try {
      final stream = _aiService
          .sendMessageStream(prompt, isAgentMode: false)
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
        if (_stopRequested) break;
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
    } catch (e) {
      if (mounted) {
        setState(() {
          if (_messages.length > assistantIndex) {
            _messages.removeAt(assistantIndex);
          }
          _messages.add(
            ChatMessage(
              role: 'assistant',
              content:
                  'Error: ${e.toString().replaceFirst('Exception: ', '')}',
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
      }
    }
  }

  Future<void> _rewriteMessage(int index) async {
    if (index < 0 || index >= _messages.length) return;
    final content = _messages[index].content;
    await _aiAssistMessage(
      'Rewrite the following text to be clearer, more polished and more '
      'professional. Keep the meaning and the same language. Only output the '
      'rewritten text.\n\n$content',
    );
  }

  Future<void> _translateMessage(int index) async {
    if (index < 0 || index >= _messages.length) return;
    const languages = [
      'English', 'Bangla', 'Hindi', 'Spanish', 'French', 'Arabic',
      'German', 'Japanese', 'Chinese', 'Russian', 'Portuguese',
    ];
    final target = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        return Container(
          margin: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF241B21) : Colors.white,
            borderRadius: BorderRadius.circular(20),
          ),
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  child: Text(
                    'Translate to',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                ...languages.map(
                  (lang) => ListTile(
                    dense: true,
                    leading: const Icon(Icons.translate_rounded, size: 20),
                    title: Text(lang),
                    onTap: () => Navigator.pop(ctx, lang),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
    if (target == null) return;
    final content = _messages[index].content;
    await _aiAssistMessage(
      'Translate the following text into $target. Only output the '
      'translation, nothing else.\n\n$content',
    );
  }

  /// Search the current conversation; tapping a result jumps to and
  /// highlights the matching message.
  /// Pushes the Discover capabilities hub; tapping a card sends its command.
  Future<void> _openDiscover() async {
    final command = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const DiscoverScreen()),
    );
    if (command != null && command.trim().isNotEmpty && mounted) {
      _sendMessage(command.trim());
    }
  }

  Future<void> _openSearch() async {
    if (_messages.isEmpty) return;
    final controller = TextEditingController();
    String query = '';
    final target = await showDialog<int>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setState) {
            final matches = query.isEmpty
                ? <int>[]
                : [
                    for (var i = 0; i < _messages.length; i++)
                      if (_messages[i].content
                          .toLowerCase()
                          .contains(query.toLowerCase()))
                        i,
                  ];
            return AlertDialog(
              title: const Text('Search conversation'),
              content: SizedBox(
                width: 340,
                height: 360,
                child: Column(
                  children: [
                    TextField(
                      controller: controller,
                      autofocus: true,
                      onChanged: (v) => setState(() => query = v),
                      decoration: const InputDecoration(
                        hintText: 'Search messages...',
                        prefixIcon: Icon(Icons.search_rounded),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: matches.isEmpty
                          ? Center(
                              child: Text(
                                query.isEmpty
                                    ? 'Type to search'
                                    : 'No matches found',
                                style: TextStyle(
                                  color: Theme.of(ctx)
                                      .colorScheme
                                      .onSurface
                                      .withValues(alpha: 0.5),
                                ),
                              ),
                            )
                          : ListView.builder(
                              itemCount: matches.length,
                              itemBuilder: (context, i) {
                                final mi = matches[i];
                                final msg = _messages[mi];
                                final preview = msg.content.replaceAll(
                                  RegExp(r'\s+'),
                                  ' ',
                                );
                                return ListTile(
                                  dense: true,
                                  leading: Icon(
                                    msg.isUser
                                        ? Icons.person_rounded
                                        : Icons.smart_toy_rounded,
                                    size: 18,
                                  ),
                                  title: Text(
                                    preview.length > 60
                                        ? '${preview.substring(0, 60)}...'
                                        : preview,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  subtitle: Text(
                                    msg.isUser ? 'You' : 'Agent',
                                    style: const TextStyle(fontSize: 11),
                                  ),
                                  onTap: () => Navigator.pop(ctx, mi),
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Close'),
                ),
              ],
            );
          },
        );
      },
    );
    if (target == null) return;

    setState(() => _searchHighlightIndex = target);
    final entryIndex = _messageEntries.indexWhere(
      (e) => e is int && e == target,
    );
    if (entryIndex >= 0 && _scrollController.hasClients) {
      _scrollController.animateTo(
        (entryIndex * 64.0).clamp(
          0.0,
          _scrollController.position.maxScrollExtent,
        ),
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeOut,
      );
    }
    // Clear the highlight after a short moment.
    Future<void>.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _searchHighlightIndex = null);
    });
  }

  String _dayLabel(DateTime dt) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final thatDay = DateTime(dt.year, dt.month, dt.day);
    final diff = today.difference(thatDay).inDays;
    if (diff == 0) return 'Today';
    if (diff == 1) return 'Yesterday';
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${months[dt.month - 1]} ${dt.day}';
  }

  /// Flat list used by the chat ListView: greeting header, day-separator
  /// labels (String), or the index of a message in [_messages] (int).
  List<Object> get _messageEntries {
    final entries = <Object>[
      HomeHeader(
        providerLabel: _aiService.activeKey?.name ?? _providerLabel,
        model: _aiService.model,
        isDark: Theme.of(context).brightness == Brightness.dark,
        isOnline: true,
      ),
    ];
    String? lastDay;
    for (var i = 0; i < _messages.length; i++) {
      final day = _dayLabel(_messages[i].timestamp);
      if (day != lastDay) {
        lastDay = day;
        entries.add(day);
      }
      entries.add(i);
    }
    return entries;
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

  /// Share sheet: export the conversation as Markdown or structured JSON.
  Future<void> _showExportSheet() async {
    if (_messages.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No chat history to export.')),
      );
      return;
    }
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        return Container(
          margin: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF241B21) : Colors.white,
            borderRadius: BorderRadius.circular(20),
          ),
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  child: Text(
                    'Export conversation',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                ListTile(
                  dense: true,
                  leading: const Icon(Icons.description_rounded, size: 20),
                  title: const Text('Markdown (.md)'),
                  subtitle: Text(
                    'Readable transcript for docs or sharing',
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark
                        ? const Color(0xFFA8938C)
                          : const Color(0xFF8C7A6E),
                    ),
                  ),
                  onTap: () => Navigator.pop(ctx, 'md'),
                ),
                ListTile(
                  dense: true,
                  leading: const Icon(Icons.data_object_rounded, size: 20),
                  title: const Text('JSON'),
                  subtitle: Text(
                    'Full structured data, re-importable',
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark
                        ? const Color(0xFFA8938C)
                          : const Color(0xFF8C7A6E),
                    ),
                  ),
                  onTap: () => Navigator.pop(ctx, 'json'),
                ),
              ],
            ),
          ),
        );
      },
    );
    if (choice == 'md') return _exportChatSession();
    if (choice != 'json') return;

    final payload = jsonEncode({
      'app': 'AAA Private Agent',
      'exported_at': DateTime.now().toIso8601String(),
      'messages': _messages.map((m) => m.toJson()).toList(),
    });
    await SharePlus.instance.share(
      ShareParams(text: payload, subject: 'AAA Private Agent Chat Export (JSON)'),
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
      backgroundColor: isDark ? const Color(0xFF171015) : const Color(0xFFFFFFFF),
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const AgentOrb(size: 26, glow: false),
            const SizedBox(width: 8),
            Flexible(
              child: RichText(
                text: TextSpan(
                  style: TextStyle(
                    fontSize: 20,
                    color: isDark ? Colors.white : const Color(0xFF2E1F1A),
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
            ),
          ],
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
              color: _continuousVoiceMode ? const Color(0xFFFFB86B) : null,
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
                    backgroundColor: const Color(0xFF2FBF8F),
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
            icon: const Icon(Icons.search_rounded),
            tooltip: 'Search conversation',
            onPressed: _messages.isEmpty ? null : _openSearch,
          ),
          IconButton(
            icon: const Icon(Icons.psychology_rounded),
            tooltip: 'Quick AI Model Switcher',
            onPressed: () => ModelPickerSheet.show(context, _aiService, () {
              setState(() {});
            }),
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
        onSummarize: _summarizeChat,
        onClearChat: _clearConversation,
        onControlPanel: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => ControlPanelScreen(
                actionHandler: _actionHandler,
              ),
            ),
          );
          await _actionHandler.shizuku.checkAvailability();
          if (mounted) setState(() {});
        },
        onDiscover: () => _openDiscover(),
        onAbout: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const AboutScreen()),
        ),
        onExportChat: _showExportSheet,
        onPermissions: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => PermissionsScreen(
              shizukuService: _actionHandler.shizuku,
              screenAutomationService: _actionHandler.screenAutomation,
            ),
          ),
        ),
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
                        onExplore: _openDiscover,
                      )
                    : ListView.builder(
                        controller: _scrollController,
                        physics: const BouncingScrollPhysics(),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
                        itemCount: _messageEntries.length,
                        itemBuilder: (context, index) {
                          final entry = _messageEntries[index];
                          if (entry is String) {
                            return _DayChip(
                              label: entry,
                              isDark: isDark,
                            );
                          }
                          final i = entry as int;
                          final key =
                              _messageKeys.putIfAbsent(i, () => GlobalKey());
                          return KeyedSubtree(
                            key: key,
                            child: MessageBubble(
                              message: _messages[i],
                              modelLabel: _messages[i].isUser
                                  ? null
                                  : _aiService.model,
                              highlight: _searchHighlightIndex == i,
                              onSpeakTap: () {
                                if (_voiceService.isSpeaking) {
                                  _voiceService.stopSpeaking();
                                } else {
                                  _voiceService.speak(_messages[i].content);
                                }
                              },
                              onDeleteTap: () => _deleteMessage(i),
                              onRegenerateTap: _messages[i].isUser
                                  ? null
                                  : () => _regenerateResponse(i),
                              onRewriteTap: () => _rewriteMessage(i),
                              onTranslateTap: () => _translateMessage(i),
                            ),
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
                      TypingIndicator(
                        color: Theme.of(context).colorScheme.secondary,
                        dotSize: 5,
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
                              _stopRequested = true;
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
                  customCommands: _customCommands,
                  onEditCustom: _openQuickActionsEditor,
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

/// Centered day separator chip shown between messages from different days.
class _DayChip extends StatelessWidget {
  final String label;
  final bool isDark;

  const _DayChip({required this.label, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
          decoration: BoxDecoration(
            color: isDark
                ? const Color(0xFF241B21)
                : const Color(0xFFF7EDE0),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isDark
                  ? const Color(0xFFFF6B4A).withValues(alpha: 0.25)
                  : const Color(0xFFF0E3D3),
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.6,
              color: isDark
                  ? const Color(0xFFFFC9A8)
                  : const Color(0xFFC2503A),
            ),
          ),
        ),
      ),
    );
  }
}
