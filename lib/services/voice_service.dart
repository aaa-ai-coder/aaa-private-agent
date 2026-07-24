import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:flutter_tts/flutter_tts.dart';

class VoiceService {
  final stt.SpeechToText _speech = stt.SpeechToText();
  final FlutterTts _tts = FlutterTts();
  bool _isInitialized = false;
  bool _isListening = false;
  bool _isSpeaking = false;

  bool get isListening => _isListening;
  bool get isSpeaking => _isSpeaking;

  Future<void> init() async {
    if (_isInitialized) return;

    try {
      _isInitialized = await _speech.initialize(
        onError: (error) {
          _isListening = false;
        },
      );
    } catch (_) {}

    // Configure TTS
    try {
      await _tts.setLanguage('en-US');
      await _tts.setSpeechRate(0.5);
      await _tts.setVolume(1.0);
      await _tts.setPitch(1.0);

      _tts.setStartHandler(() {
        _isSpeaking = true;
      });

      _tts.setCompletionHandler(() {
        _isSpeaking = false;
      });

      _tts.setErrorHandler((msg) {
        _isSpeaking = false;
      });
    } catch (_) {}
  }

  /// Start listening for speech. Supports multilingual recognition.
  Future<void> startListening({
    required Function(String) onResult,
    required Function() onDone,
  }) async {
    if (!_isInitialized) await init();

    if (_isSpeaking) {
      await stopSpeaking();
    }

    _isListening = true;

    try {
      await _speech.listen(
        onResult: (SpeechRecognitionResult result) {
          if (result.finalResult) {
            _isListening = false;
            onResult(result.recognizedWords);
            onDone();
          }
        },
        localeId: 'en_US',
        listenOptions: stt.SpeechListenOptions(
          listenMode: stt.ListenMode.confirmation,
          partialResults: false,
        ),
      );
    } catch (e) {
      _isListening = false;
    }
  }

  /// Stop listening
  Future<void> stopListening() async {
    _isListening = false;
    try {
      await _speech.stop();
    } catch (_) {}
  }

  /// Update speech parameters dynamically
  Future<void> setSpeechRate(double rate) async {
    try {
      await _tts.setSpeechRate(rate);
    } catch (_) {}
  }

  Future<void> setPitch(double pitch) async {
    try {
      await _tts.setPitch(pitch);
    } catch (_) {}
  }

  /// Speak text aloud with cleaned markdown for clear voice synthesis
  Future<void> speak(String text) async {
    if (text.trim().isEmpty) return;
    try {
      await init();
      await _tts.stop();

      // Clean markdown tags for natural speech
      final cleanText = text
          .replaceAll(RegExp(r'```[\s\S]*?```'), ' Code block omitted. ')
          .replaceAll(RegExp(r'`([^`]+)`'), r'$1')
          .replaceAll(RegExp(r'[*#_~`]'), '')
          .replaceAll(RegExp(r'\[([^\]]+)\]\([^\)]+\)'), r'$1')
          .trim();

      if (cleanText.isEmpty) return;

      _isSpeaking = true;
      await _tts.speak(cleanText);
    } catch (e) {
      _isSpeaking = false;
      print('TTS speak error: $e');
    }
  }

  /// Stop speaking
  Future<void> stopSpeaking() async {
    _isSpeaking = false;
    try {
      await _tts.stop();
    } catch (_) {}
  }

  void dispose() {
    _speech.stop();
    _tts.stop();
  }
}
