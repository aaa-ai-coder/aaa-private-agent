import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:flutter_tts/flutter_tts.dart';

class VoiceService {
  final stt.SpeechToText _speech = stt.SpeechToText();
  final FlutterTts _tts = FlutterTts();
  bool _isInitialized = false;
  bool _isListening = false;

  bool get isListening => _isListening;

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
      await _tts.setAwaitSpeakCompletion(true);
    } catch (_) {}
  }

  /// Start listening for speech. Supports multilingual recognition.
  Future<void> startListening({
    required Function(String) onResult,
    required Function() onDone,
  }) async {
    if (!_isInitialized) await init();

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

  /// Speak text aloud
  Future<void> speak(String text) async {
    if (text.isEmpty) return;
    try {
      await init();
      await _tts.stop();
      await _tts.speak(text);
    } catch (e) {
      print('TTS speak error: $e');
    }
  }

  /// Stop speaking
  Future<void> stopSpeaking() async {
    await _tts.stop();
  }

  void dispose() {
    _speech.stop();
    _tts.stop();
  }
}
