import 'package:flutter/material.dart';
import '../models/chat_message.dart';
import '../models/agent_action.dart';
import '../services/ai_service.dart';
import '../services/action_handler.dart';
import '../services/voice_service.dart';
import '../widgets/message_bubble.dart';
import '../services/telegram_service.dart';
import 'settings_screen.dart';
import '../main.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final AiService _aiService = AiService();
  final ActionHandler _actionHandler = ActionHandler();
  final VoiceService _voiceService = VoiceService();
  late final TelegramService _telegramService;

  final List<ChatMessage> _messages = [];
  bool _isLoading = false;
  bool _isListening = false;

  @override
  void initState() {
    super.initState();
    _telegramService = TelegramService(_actionHandler, _aiService);
    _initServices();
    // Register as the handler for overlay bubble tasks
    onOverlayTask = (task) => _sendMessage(task);
  }

  Future<void> _initServices() async {
    await _aiService.init();
    await _voiceService.init();
    await _telegramService.init();

    // Check Shizuku availability
    await _actionHandler.shizuku.checkAvailability();

    if (mounted) {
      // Check accessibility service
      final accessibilityEnabled =
          await _actionHandler.screenAutomation.isServiceRunning();
          
      if (!accessibilityEnabled) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          showDialog(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Accessibility Required'),
              content: const Text('To perform multi-step tasks like opening and navigating apps, PrivateAgent needs Accessibility permission to see the screen and click buttons.'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                TextButton(
                  onPressed: () {
                    Navigator.pop(context);
                    _actionHandler.screenAutomation.openAccessibilitySettings();
                  },
                  child: const Text('Enable Now'),
                ),
              ],
            ),
          );
        });
      }

      setState(() {
        _messages.add(ChatMessage(
          role: 'assistant',
          content:
              'Hi! I\'m PrivateAgent. I can help you control your phone.\n\n'
              '${accessibilityEnabled ? '✅ Screen Control is ACTIVE — I can read and control other apps!' : '⚠️ Screen Control is OFF — Enable it for multi-step tasks.'}\n\n'
              'Try saying:\n'
              '• "Open YouTube"\n'
              '• "Call Mom"\n'
              '• "Set volume to 50%"\n'
              '• "What\'s on my screen?"\n\n'
              'Type or tap the mic to get started!',
        ));
      });
    }
  }

  Future<void> _sendMessage(String text) async {
    if (text.trim().isEmpty) return;

    final userMessage = ChatMessage(role: 'user', content: text.trim());
    setState(() {
      _messages.add(userMessage);
      _isLoading = true;
    });
    _textController.clear();
    _scrollToBottom();

    try {
      // ---------------------------------------------------------
      // DEMO VIDEO OVERRIDE: Bypass AI entirely for this exact phrase
      // ---------------------------------------------------------
      final lowerText = text.trim().toLowerCase();
      
      if (lowerText.contains('set up a meeting') && lowerText.contains('orailnoor')) {
        // Mock the AI action
        final mockAction = AgentAction(
          action: 'macro_meet',
          params: {},
          response: 'Setting up a Google Meet with Orailnoor.',
        );

        final result = await _actionHandler.execute(
          mockAction,
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

        setState(() {
          _messages.add(ChatMessage(
            role: 'assistant',
            content: result.success
                ? mockAction.response
                : '⚠️ ${result.details}',
            actionResult: result,
          ));
        });
        _voiceService.speak(mockAction.response);
        return;
      }
      
      if (lowerText.contains('open') && lowerText.contains('privatelm')) {
        final mockAction = AgentAction(
          action: 'macro_privatelm',
          params: {'package_name': 'com.orailnoor.privatelm'},
          response: 'Opening PrivateLM and asking...',
        );

        final result = await _actionHandler.execute(
          mockAction,
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

        setState(() {
          _messages.add(ChatMessage(
            role: 'assistant',
            content: result.success ? mockAction.response : '⚠️ ${result.details}',
            actionResult: result,
          ));
        });
        _voiceService.speak(mockAction.response);
        return;
      }
      // ---------------------------------------------------------

      // Get AI response
      final response = await _aiService.sendMessage(text.trim());

      // Check if it's an action
      final action = _aiService.parseAction(response);

      if (action != null) {
        // Execute the action (pass aiService for multi-step tasks)
        final result = await _actionHandler.execute(
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

        setState(() {
          _messages.add(ChatMessage(
            role: 'assistant',
            content: result.success
                ? (action.response.isNotEmpty ? action.response : (result.details ?? 'Done.'))
                : (action.response.isNotEmpty ? '${action.response}\n\n⚠️ ${result.details}' : '⚠️ ${result.details}'),
            actionResult: result,
          ));
        });

        // Speak the response
        _voiceService.speak(action.response.isNotEmpty
            ? action.response
            : result.details ?? 'Done.');
      } else {
        // Plain text response
        setState(() {
          _messages.add(ChatMessage(role: 'assistant', content: response));
        });
        _voiceService.speak(response);
      }
    } catch (e) {
      setState(() {
        _messages.add(ChatMessage(
          role: 'assistant',
          content: 'Error: ${e.toString().replaceFirst('Exception: ', '')}',
        ));
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        _scrollToBottom();
      }
    }
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

  @override
  void dispose() {
    _textController.dispose();
    _scrollController.dispose();
    _voiceService.dispose();
    _telegramService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('PrivateAgent'),
        actions: [
          // New Chat
          IconButton(
            icon: const Icon(Icons.add_comment),
            tooltip: 'New Chat',
            onPressed: () {
              setState(() {
                _messages.clear();
                _aiService.clearHistory();
                _messages.add(ChatMessage(
                  role: 'assistant',
                  content: '🧹 Context erased. Starting a new chat!',
                ));
              });
              _scrollToBottom();
            },
          ),
          // Settings
          IconButton(
            icon: const Icon(Icons.settings),
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
              // Refresh Shizuku status after settings
              await _actionHandler.shizuku.checkAvailability();
              if (mounted) setState(() {});
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // API key warning
          if (!_aiService.isConfigured)
            MaterialBanner(
              content: const Text(
                'API not configured. Go to Settings to add your server URL and API key.',
              ),
              leading: const Icon(Icons.warning, color: Colors.orange),
              actions: [
                TextButton(
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
                    if (mounted) setState(() {});
                  },
                  child: const Text('SETTINGS'),
                ),
              ],
            ),

          // Messages
          Expanded(
            child: _messages.isEmpty
                ? const Center(
                    child: Text(
                      'Start a conversation...',
                      style: TextStyle(color: Colors.grey),
                    ),
                  )
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: _messages.length,
                    itemBuilder: (context, index) {
                      return MessageBubble(message: _messages[index]);
                    },
                  ),
          ),

          // Loading indicator with Stop button
          if (_isLoading)
            Padding(
              padding: const EdgeInsets.all(8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 8),
                  const Text('Thinking...', style: TextStyle(color: Colors.grey)),
                  const SizedBox(width: 12),
                  TextButton.icon(
                    onPressed: () {
                      _actionHandler.cancelTask();
                    },
                    icon: const Icon(Icons.stop_circle, size: 18, color: Colors.red),
                    label: const Text('Stop', style: TextStyle(color: Colors.red)),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      minimumSize: Size.zero,
                    ),
                  ),
                ],
              ),
            ),

          // Input bar
          Container(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 8,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            child: SafeArea(
              child: Row(
                children: [
                  // Mic button
                  IconButton(
                    icon: Icon(
                      _isListening ? Icons.mic : Icons.mic_none,
                      color: _isListening
                          ? Colors.red
                          : Theme.of(context).colorScheme.primary,
                    ),
                    onPressed: _isLoading ? null : _toggleVoice,
                  ),
                  // Text input
                  Expanded(
                    child: TextField(
                      controller: _textController,
                      decoration: InputDecoration(
                        hintText: _isListening
                            ? 'Listening...'
                            : 'Type a command...',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                        filled: true,
                        fillColor: Theme.of(context)
                            .colorScheme
                            .surfaceContainerHighest,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                      ),
                      textInputAction: TextInputAction.send,
                      onSubmitted:
                          _isLoading ? null : (text) => _sendMessage(text),
                    ),
                  ),
                  const SizedBox(width: 4),
                  // Send button
                  IconButton(
                    icon: const Icon(Icons.send),
                    color: Theme.of(context).colorScheme.primary,
                    onPressed: _isLoading
                        ? null
                        : () => _sendMessage(_textController.text),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
