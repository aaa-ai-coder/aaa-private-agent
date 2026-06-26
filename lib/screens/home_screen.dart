import 'package:flutter/material.dart';
import '../models/chat_message.dart';
import '../services/ai_service.dart';
import '../services/action_handler.dart';
import '../services/voice_service.dart';
import '../widgets/message_bubble.dart';
import '../services/telegram_service.dart';
import 'settings_screen.dart';

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

      setState(() {
        _messages.add(ChatMessage(
          role: 'assistant',
          content:
              'Hi! I\'m PrivateAgent. I can help you control your phone.\n\n'
              '${accessibilityEnabled ? '✅ Screen Control is ACTIVE — I can read and control other apps!' : '⚠️ Screen Control is OFF — Go to Settings to enable it for multi-step tasks.'}\n\n'
              'Try saying:\n'
              '• "Open YouTube"\n'
              '• "Call Mom"\n'
              '• "Set volume to 50%"\n'
              '• "What\'s on my screen?"\n'
              '• "Open Instagram and search techjarves"\n\n'
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
            content: action.response.isNotEmpty
                ? action.response
                : result.details ?? 'Done.',
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
      setState(() => _isLoading = false);
      _scrollToBottom();
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
          // Screen control test button
          IconButton(
            icon: const Icon(Icons.visibility),
            tooltip: 'Test screen reading',
            onPressed: () async {
              final isRunning = await _actionHandler.screenAutomation
                  .isServiceRunning();
              if (!isRunning) {
                setState(() {
                  _messages.add(ChatMessage(
                    role: 'assistant',
                    content:
                        '❌ Screen Control is not enabled!\n\n'
                        'To enable it:\n'
                        '1. Go to Settings (⚙️ icon)\n'
                        '2. Find "Screen Control (Accessibility)"\n'
                        '3. Tap "Open Accessibility Settings"\n'
                        '4. Find "PrivateAgent Screen Control"\n'
                        '5. Toggle it ON',
                  ));
                });
                _scrollToBottom();
                return;
              }
              setState(() {
                _messages.add(ChatMessage(
                  role: 'assistant',
                  content: '🔍 Reading screen...',
                ));
              });
              _scrollToBottom();
              final description = await _actionHandler.screenAutomation
                  .getScreenDescription();
              setState(() {
                _messages.add(ChatMessage(
                  role: 'assistant',
                  content: '📱 Screen Content:\n\n$description',
                ));
              });
              _scrollToBottom();
            },
          ),
          // Shizuku status indicator
          if (_actionHandler.shizuku.isAvailable)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Icon(
                Icons.link,
                size: 18,
                color: _actionHandler.shizuku.hasPermission
                    ? Colors.green
                    : Colors.orange,
              ),
            ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Clear chat',
            onPressed: () {
              setState(() {
                _messages.clear();
                _aiService.clearHistory();
              });
            },
          ),
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
                'API key not set. Go to Settings to add your DeepSeek API key.',
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

          // Loading indicator
          if (_isLoading)
            const Padding(
              padding: EdgeInsets.all(8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  SizedBox(width: 8),
                  Text('Thinking...', style: TextStyle(color: Colors.grey)),
                ],
              ),
            ),

          // Input bar
          Container(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              border: Border(
                top: BorderSide(
                  color: Theme.of(context).dividerColor,
                  width: 0.5,
                ),
              ),
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
