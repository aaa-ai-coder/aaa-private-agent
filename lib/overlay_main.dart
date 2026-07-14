import 'dart:async';
import 'dart:developer';
import 'package:flutter/material.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:android_intent_plus/android_intent.dart';
import 'services/ai_service.dart';
import 'services/task_executor.dart';
import 'services/screen_automation_service.dart';
import 'services/app_launcher_service.dart';
import 'services/shizuku_service.dart';
import 'models/chat_message.dart';

class OverlayApp extends StatefulWidget {
  const OverlayApp({super.key});

  @override
  State<OverlayApp> createState() => _OverlayAppState();
}

class _OverlayAppState extends State<OverlayApp> {
  bool _isExpanded = false;
  final TextEditingController _taskController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  bool _isSent = false;
  bool _isListening = false;
  final stt.SpeechToText _speech = stt.SpeechToText();
  final List<ChatMessage> _messages = [];

  late final AiService _aiService;
  late final ScreenAutomationService _screenService;
  late final AppLauncherService _appLauncher;
  late final ShizukuService _shizukuService;
  late final Future<void> _servicesReady;
  StreamSubscription<dynamic>? _overlaySubscription;
  TaskExecutor? _executor;
  OverlayPosition? _headerDragPosition;

  @override
  void initState() {
    super.initState();
    _speech.initialize();

    _aiService = AiService();
    _screenService = ScreenAutomationService();
    _appLauncher = AppLauncherService();
    _shizukuService = ShizukuService();
    _servicesReady = _initializeServices();
    _overlaySubscription = FlutterOverlayWindow.overlayListener.listen(
      _handleMainAppEvent,
    );

    // Welcome message
    _messages.add(
      ChatMessage(
        role: 'assistant',
        content:
            'Hi! I am your Private Agent. Ask me to perform any task on your screen.',
      ),
    );
  }

  @override
  void dispose() {
    _overlaySubscription?.cancel();
    _taskController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _handleMainAppEvent(dynamic event) {
    if (event is! String || !event.startsWith('OVERLAY_')) return;

    final separator = event.indexOf('|');
    final type = separator == -1 ? event : event.substring(0, separator);
    final message = separator == -1 ? '' : event.substring(separator + 1);

    if (type == 'OVERLAY_TASK_STARTED' || type == 'OVERLAY_PROGRESS') {
      unawaited(_expandForTaskProgress());
    }

    if (message.isEmpty || !mounted) return;
    setState(() {
      _isSent = type != 'OVERLAY_TASK_FINISHED';
      _messages.add(ChatMessage(role: 'assistant', content: message));
      _scrollToBottom();
    });
  }

  Future<void> _expandForTaskProgress() async {
    if (_isExpanded) return;
    await FlutterOverlayWindow.resizeOverlay(300, 360, false);
    if (!mounted) return;
    setState(() {
      _isExpanded = true;
      _scrollToBottom();
    });
  }

  Future<void> _initializeServices() async {
    // 1. Send registration broadcast first so native MethodChannels are active
    final intent = const AndroidIntent(
      action: 'com.orailnoor.privateagent.REGISTER_BACKGROUND_CHANNELS',
      package: 'com.orailnoor.privateagent',
    );
    try {
      await intent.sendBroadcast();
    } catch (e) {
      log("Broadcast error: $e");
    }

    // 2. Wait a brief moment for registration
    await Future.delayed(const Duration(milliseconds: 150));

    // 3. Initialize AI Service settings
    await _aiService.init();

    // 4. Safely query Shizuku without locking startup
    try {
      await _shizukuService.checkAvailability();
    } catch (e) {
      log("Shizuku check error: $e");
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _toggleListening() async {
    if (_isListening) {
      await _speech.stop();
      setState(() => _isListening = false);
      return;
    }

    setState(() => _isListening = true);
    await _speech.listen(
      onResult: (SpeechRecognitionResult result) {
        if (result.finalResult) {
          setState(() {
            _isListening = false;
            _taskController.text = result.recognizedWords;
          });
          _sendTask(result.recognizedWords);
        }
      },
      listenOptions: stt.SpeechListenOptions(
        listenMode: stt.ListenMode.confirmation,
        partialResults: false,
      ),
    );
  }

  Future<void> _sendTask(String task) async {
    if (task.trim().isEmpty || _isSent) return;

    final userTask = task.trim();
    setState(() {
      _isSent = true;
      _messages.add(ChatMessage(role: 'user', content: userTask));
      _scrollToBottom();
    });

    _taskController.clear(); // Clear immediately for responsive UX feedback

    await _servicesReady;
    if (!await _screenService.waitUntilReady()) {
      if (mounted) {
        setState(() {
          _isSent = false;
          _messages.add(
            ChatMessage(
              role: 'assistant',
              content:
                  'The background accessibility bridge did not respond. '
                  'Close and reopen the floating overlay, then try again.',
            ),
          );
          _scrollToBottom();
        });
      }
      return;
    }

    // This is only a best-effort mirror for the main app's logs. The overlay
    // plugin may leave the reply pending when the main engine is not attached,
    // so it must never block execution in the background engine.
    unawaited(
      FlutterOverlayWindow.shareData(
        userTask,
      ).timeout(const Duration(seconds: 2)).catchError((Object e) {
        log("Error sharing task with main app: $e");
      }),
    );

    try {
      // Execute the task directly in the overlay isolate!
      _executor = TaskExecutor(
        aiService: _aiService,
        screenService: _screenService,
        appLauncher: _appLauncher,
        shizukuService: _shizukuService,
        onProgress: (msg) {
          log("Overlay Task Progress: $msg");
          try {
            FlutterOverlayWindow.shareData("PROGRESS: $msg");
          } catch (_) {}
          if (mounted) {
            setState(() {
              _messages.add(ChatMessage(role: 'assistant', content: msg));
              _scrollToBottom();
            });
          }
        },
      );

      _executor!
          .executeTask(userTask)
          .then((res) {
            log("Overlay Task Finished");
            if (mounted) {
              setState(() {
                _isSent = false;
                _messages.add(ChatMessage(role: 'assistant', content: res));
                _scrollToBottom();
              });
            }
          })
          .catchError((e) {
            log("Overlay Task Error: $e");
            if (mounted) {
              setState(() {
                _isSent = false;
                _messages.add(
                  ChatMessage(role: 'assistant', content: "Error: $e"),
                );
                _scrollToBottom();
              });
            }
          });
    } catch (e) {
      log("Overlay Task Execution Exception: $e");
      if (mounted) {
        setState(() {
          _isSent = false;
          _messages.add(
            ChatMessage(role: 'assistant', content: "Execution Exception: $e"),
          );
          _scrollToBottom();
        });
      }
    }
  }

  OverlayPosition? _savedBubblePosition;

  Future<void> _beginHeaderDrag(DragStartDetails _) async {
    _headerDragPosition = await FlutterOverlayWindow.getOverlayPosition();
  }

  void _updateHeaderDrag(DragUpdateDetails details) {
    final current = _headerDragPosition;
    if (current == null) return;
    final next = OverlayPosition(
      current.x + details.delta.dx,
      current.y + details.delta.dy,
    );
    _headerDragPosition = next;
    unawaited(FlutterOverlayWindow.moveOverlay(next));
  }

  Future<void> _toggleExpanded() async {
    if (!_isExpanded) {
      // Save current bubble position before expanding
      _savedBubblePosition = await FlutterOverlayWindow.getOverlayPosition();
      // Move to a safe position so the expanded panel stays on-screen
      await FlutterOverlayWindow.moveOverlay(
        OverlayPosition(10, _savedBubblePosition?.y ?? 300),
      );
      await FlutterOverlayWindow.resizeOverlay(300, 360, false);
      setState(() {
        _isExpanded = true;
        _scrollToBottom();
      });
    } else {
      await FlutterOverlayWindow.resizeOverlay(56, 56, true);
      // Restore the original bubble position
      if (_savedBubblePosition != null) {
        await FlutterOverlayWindow.moveOverlay(_savedBubblePosition!);
      }
      setState(() => _isExpanded = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Center(child: _buildContent()),
    );
  }

  Widget _buildContent() {
    if (!_isExpanded) {
      return GestureDetector(
        onTap: _toggleExpanded,
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.12),
                blurRadius: 5,
                spreadRadius: 1,
                offset: const Offset(0, 2),
              ),
            ],
            border: Border.all(color: Colors.black.withOpacity(0.08), width: 1),
          ),
          padding: const EdgeInsets.all(5),
          child: Center(
            child: ClipOval(
              child: Image.asset(
                'assets/app-logo.png',
                width: 30,
                height: 30,
                fit: BoxFit.contain,
              ),
            ),
          ),
        ),
      );
    }

    // Full Chat Interface Panel
    return Container(
      width: 300,
      height: 360,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFEAEAEA), width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.15),
            blurRadius: 12,
            spreadRadius: 2,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          // Header Bar
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onPanStart: (details) => unawaited(_beginHeaderDrag(details)),
            onPanUpdate: _updateHeaderDrag,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: const BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: Color(0xFFF2F2F2), width: 1),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Image.asset(
                        'assets/app-logo.png',
                        width: 18,
                        height: 18,
                        fit: BoxFit.contain,
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        'Private Agent',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Colors.black87,
                        ),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 8),
                        child: Icon(
                          Icons.drag_indicator,
                          color: Colors.black45,
                          size: 18,
                        ),
                      ),
                      GestureDetector(
                        onTap: _toggleExpanded,
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: const BoxDecoration(
                            color: Color(0xFFF2F2F5),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.remove,
                            color: Colors.black54,
                            size: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          // Message Log List
          Expanded(
            child: Container(
              color: const Color(0xFFFAF9FB),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: ListView.builder(
                controller: _scrollController,
                itemCount: _messages.length,
                itemBuilder: (context, index) {
                  final msg = _messages[index];
                  final isUser = msg.isUser;
                  return Align(
                    alignment: isUser
                        ? Alignment.centerRight
                        : Alignment.centerLeft,
                    child: Container(
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      constraints: const BoxConstraints(maxWidth: 220),
                      decoration: BoxDecoration(
                        color: isUser ? Colors.black : Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: isUser
                            ? null
                            : Border.all(
                                color: const Color(0xFFEBEBEB),
                                width: 1,
                              ),
                        boxShadow: isUser
                            ? null
                            : [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.02),
                                  blurRadius: 3,
                                  offset: const Offset(0, 1),
                                ),
                              ],
                      ),
                      child: Text(
                        msg.content,
                        style: TextStyle(
                          fontSize: 11.5,
                          color: isUser ? Colors.white : Colors.black87,
                          height: 1.3,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),

          // Input Controller Area
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: const BoxDecoration(
              color: Colors.white,
              border: Border(
                top: BorderSide(color: Color(0xFFF2F2F2), width: 1),
              ),
              borderRadius: BorderRadius.vertical(bottom: Radius.circular(24)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF6F6F8),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _taskController,
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.black87,
                            ),
                            decoration: const InputDecoration(
                              hintText: 'Ask anything...',
                              hintStyle: TextStyle(
                                fontSize: 11.5,
                                color: Colors.grey,
                              ),
                              border: InputBorder.none,
                              isDense: true,
                              contentPadding: EdgeInsets.symmetric(vertical: 6),
                            ),
                            onSubmitted: (val) => _sendTask(val),
                          ),
                        ),
                        if (!_isSent)
                          GestureDetector(
                            onTap: _toggleListening,
                            child: Icon(
                              _isListening ? Icons.mic : Icons.mic_none,
                              color: _isListening ? Colors.red : Colors.black54,
                              size: 16,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                _isSent
                    ? const SizedBox(
                        width: 28,
                        height: 28,
                        child: Padding(
                          padding: EdgeInsets.all(6),
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.black,
                          ),
                        ),
                      )
                    : GestureDetector(
                        onTap: () => _sendTask(_taskController.text),
                        child: Container(
                          width: 28,
                          height: 28,
                          decoration: const BoxDecoration(
                            color: Colors.black,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.arrow_upward,
                            color: Colors.white,
                            size: 14,
                          ),
                        ),
                      ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
