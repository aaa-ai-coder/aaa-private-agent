import 'dart:developer';
import 'package:flutter/material.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:android_intent_plus/android_intent.dart';
import 'package:android_intent_plus/flag.dart';
import 'services/ai_service.dart';
import 'services/action_handler.dart';
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
  bool _isSent = false;
  bool _isListening = false;
  final stt.SpeechToText _speech = stt.SpeechToText();
  
  late final AiService _aiService;
  late final ScreenAutomationService _screenService;
  late final AppLauncherService _appLauncher;
  late final ShizukuService _shizukuService;
  TaskExecutor? _executor;

  @override
  void initState() {
    super.initState();
    _speech.initialize();
    
    _aiService = AiService();
    _screenService = ScreenAutomationService();
    _appLauncher = AppLauncherService();
    _shizukuService = ShizukuService();
    _initializeServices();
  }

  Future<void> _initializeServices() async {
    await _aiService.init();
    await _shizukuService.checkAvailability();
    
    // Register the MethodChannel on the background engine for Accessibility!
    final intent = const AndroidIntent(
      action: 'com.orailnoor.privateagent.REGISTER_BACKGROUND_CHANNELS',
    );
    try {
      await intent.sendBroadcast();
    } catch (e) {
      log("Broadcast error: $e");
    }
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

    setState(() => _isSent = true);

    // Share data back to main app for logs
    await FlutterOverlayWindow.shareData(task.trim());

    // Execute the task directly in the overlay isolate!
    _executor = TaskExecutor(
      aiService: _aiService,
      screenService: _screenService,
      appLauncher: _appLauncher,
      shizukuService: _shizukuService,
      onProgress: (msg) {
        log("Overlay Task Progress: $msg");
        FlutterOverlayWindow.shareData("PROGRESS: $msg");
      },
    );
    
    // Run it asynchronously without awaiting so the bubble collapses immediately
    _executor!.executeTask(task.trim()).then((_) {
      log("Overlay Task Finished");
    }).catchError((e) {
      log("Overlay Task Error: $e");
    });

    // Collapse back to bubble after a brief moment
    await Future.delayed(const Duration(milliseconds: 500));
    if (mounted) {
      setState(() {
        _isSent = false;
        _isExpanded = false;
        _taskController.clear();
      });
      await FlutterOverlayWindow.resizeOverlay(56, 56, true);
      if (_savedBubblePosition != null) {
        await FlutterOverlayWindow.moveOverlay(_savedBubblePosition!);
      }
    }
  }

  OverlayPosition? _savedBubblePosition;

  Future<void> _toggleExpanded() async {
    if (!_isExpanded) {
      // Save current bubble position before expanding
      _savedBubblePosition = await FlutterOverlayWindow.getOverlayPosition();
      // Move to a safe position so the expanded panel stays on-screen
      await FlutterOverlayWindow.moveOverlay(
        OverlayPosition(10, _savedBubblePosition?.y ?? 300),
      );
      await FlutterOverlayWindow.resizeOverlay(300, 44, false);
      setState(() => _isExpanded = true);
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
    if (!_isExpanded) {
      return GestureDetector(
        onTap: _toggleExpanded,
        child: Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            color: const Color(0xFFEEEEEE),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.black26, width: 1),
          ),
          padding: const EdgeInsets.all(8),
          child: ClipOval(
            child: Image.asset(
              'assets/app-logo.png',
              fit: BoxFit.contain,
            ),
          ),
        ),
      );
    }

    // Expanded view
    return Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        decoration: BoxDecoration(
          color: const Color(0xFFF8F8FA),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.black12, width: 1),
        ),
        child: Row(
          children: [
            GestureDetector(
              onTap: _toggleExpanded,
              child: Container(
                width: 28,
                height: 28,
                decoration: const BoxDecoration(
                  color: Color(0xFFE0E0E0),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.close, color: Color(0xFF555555), size: 14),
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: TextField(
                controller: _taskController,
                style: const TextStyle(fontSize: 12, color: Colors.black87),
                decoration: InputDecoration(
                  hintText: 'Ask anything...',
                  hintStyle: TextStyle(fontSize: 12, color: Colors.grey[400]),
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(vertical: 6),
                ),
                onSubmitted: (val) => _sendTask(val),
              ),
            ),
            const SizedBox(width: 2),
            if (!_isSent)
              GestureDetector(
                onTap: _toggleListening,
                child: Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: _isListening ? Colors.red[50] : const Color(0xFFE8E8E8),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    _isListening ? Icons.mic : Icons.mic_none,
                    color: _isListening ? Colors.red : const Color(0xFF555555),
                    size: 14,
                  ),
                ),
              ),
            const SizedBox(width: 2),
            _isSent
                ? const SizedBox(
                    width: 28,
                    height: 28,
                    child: Padding(
                      padding: EdgeInsets.all(5),
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.indigo),
                    ),
                  )
                : GestureDetector(
                    onTap: () => _sendTask(_taskController.text),
                    child: Container(
                      width: 28,
                      height: 28,
                      decoration: const BoxDecoration(
                        color: Colors.indigo,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.arrow_upward, color: Colors.white, size: 14),
                    ),
                  ),
          ],
        ),
      ),
    );
  }
}
