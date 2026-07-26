import 'dart:developer' as developer;
import 'package:permission_handler/permission_handler.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:flutter_tts/flutter_tts.dart';
import '../models/language_config.dart';

class VoiceService {
  final stt.SpeechToText _speech = stt.SpeechToText();
  final FlutterTts _tts = FlutterTts();

  // Separate initialization flags for STT and TTS
  bool _sttInitialized = false;
  bool _ttsInitialized = false;
  bool _isListening = false;
  bool _isSpeaking = false;
  Function()? _onSpeakCompletion;
  LanguageConfig _currentLanguage = LanguageConfig.supportedLanguages.first;

  LanguageConfig get currentLanguage => _currentLanguage;

  Future<void> setLanguage(LanguageConfig lang) async {
    _currentLanguage = lang;
    if (_ttsInitialized) {
      await _applyLanguageToTts(lang);
    }
  }

  Future<void> _applyLanguageToTts(LanguageConfig lang) async {
    final localesToTry = [
      lang.locale, // e.g. "bn-BD"
      lang.sttLocale, // e.g. "bn_BD"
      lang.code, // e.g. "bn"
      '${lang.code}-IN', // e.g. "bn-IN"
    ];

    bool setOk = false;
    for (final loc in localesToTry) {
      try {
        final available = await _tts.isLanguageAvailable(loc);
        if (available == true) {
          await _tts.setLanguage(loc);
          developer.log('TTS set language to: $loc', name: 'VoiceService');
          setOk = true;
          break;
        }
      } catch (_) {}
    }

    if (!setOk) {
      try {
        await _tts.setLanguage(lang.locale);
      } catch (_) {}
    }

    // Try finding specific voice matching language
    try {
      final voices = await _tts.getVoices;
      if (voices is List) {
        for (final v in voices) {
          if (v is Map) {
            final locStr = (v['locale'] ?? '').toString().toLowerCase();
            final nameStr = (v['name'] ?? '').toString().toLowerCase();
            if (locStr.contains(lang.code) || nameStr.contains(lang.code)) {
              await _tts.setVoice({"name": v['name'], "locale": v['locale']});
              developer.log('TTS set voice to: ${v['name']}', name: 'VoiceService');
              break;
            }
          }
        }
      }
    } catch (e) {
      developer.log('TTS setVoice error: $e', name: 'VoiceService');
    }
  }

  bool get isListening => _isListening;
  bool get isSpeaking => _isSpeaking;

  Future<void> init() async {
    await _initStt();
    await _initTts();
  }

  // ─── Speech-to-Text Initialization ───────────────────────────────

  Future<void> _initStt() async {
    if (_sttInitialized) return;
    try {
      final status = await Permission.microphone.request();
      if (status.isGranted) {
        _sttInitialized = await _speech.initialize(
          onError: (error) {
            _isListening = false;
            developer.log('STT error: $error', name: 'VoiceService');
          },
          onStatus: (status) {
            developer.log('STT status: $status', name: 'VoiceService');
          },
        );
        if (_sttInitialized) {
          developer.log('STT initialized successfully', name: 'VoiceService');
        }
      }
    } catch (e) {
      developer.log('STT init error: $e', name: 'VoiceService');
    }
  }

  // ─── Text-to-Speech Initialization (separate from STT) ──────────

  Future<void> _initTts() async {
    if (_ttsInitialized) return;
    try {
      // Do NOT use awaitSpeakCompletion(true) — it conflicts with the
      // completion handler approach. We rely on setCompletionHandler instead.
      await _tts.setLanguage(_currentLanguage.locale);
      await _tts.setSpeechRate(0.5);
      await _tts.setVolume(1.0);
      await _tts.setPitch(1.0);

      // Try setting Google TTS engine on Android if available; fall back to
      // the system default if Google TTS is not installed.
      try {
        final engines = await _tts.getEngines;
        if (engines is List) {
          if (engines.contains('com.google.android.tts')) {
            await _tts.setEngine('com.google.android.tts');
            developer.log('TTS: using Google TTS engine', name: 'VoiceService');
          } else if (engines.isNotEmpty) {
            // Use first available engine
            final first = engines.isNotEmpty ? engines[0].toString() : null;
            if (first != null && first.isNotEmpty) {
              await _tts.setEngine(first);
              developer.log('TTS: using engine: $first', name: 'VoiceService');
            }
          }
        }
      } catch (e) {
        developer.log('TTS engine selection: $e', name: 'VoiceService');
      }

      // Completion handler — fires when utterance finishes
      _tts.setCompletionHandler(() {
        developer.log('TTS: speech completed', name: 'VoiceService');
        _isSpeaking = false;
        if (_onSpeakCompletion != null) {
          final cb = _onSpeakCompletion;
          _onSpeakCompletion = null;
          cb!();
        }
      });

      _tts.setStartHandler(() {
        _isSpeaking = true;
        developer.log('TTS: speech started', name: 'VoiceService');
      });

      _tts.setErrorHandler((msg) {
        developer.log('TTS error: $msg', name: 'VoiceService');
        _isSpeaking = false;
        if (_onSpeakCompletion != null) {
          final cb = _onSpeakCompletion;
          _onSpeakCompletion = null;
          cb!();
        }
      });

      // Set a cancel handler in case the utterance is interrupted
      _tts.setCancelHandler(() {
        _isSpeaking = false;
        if (_onSpeakCompletion != null) {
          final cb = _onSpeakCompletion;
          _onSpeakCompletion = null;
          cb!();
        }
      });

      _ttsInitialized = true;
      developer.log('TTS initialized successfully', name: 'VoiceService');
    } catch (e) {
      developer.log('TTS init error: $e', name: 'VoiceService');
    }
  }

  // ─── Speech Recognition ─────────────────────────────────────────

  /// Start listening for speech. Supports multilingual recognition.
  Future<void> startListening({
    required Function(String) onResult,
    required Function() onDone,
  }) async {
    if (!_sttInitialized) await _initStt();
    if (!_sttInitialized) {
      onDone();
      return;
    }

    // Stop any ongoing TTS before listening
    if (_isSpeaking) {
      await stopSpeaking();
    }

    _isListening = true;

    try {
      await _speech.listen(
        onResult: (SpeechRecognitionResult result) {
          if (result.finalResult) {
            _isListening = false;
            final recognized = result.recognizedWords;
            if (recognized.trim().isNotEmpty) {
              developer.log('STT recognized: $recognized', name: 'VoiceService');
              onResult(recognized);
            }
            onDone();
          }
        },
        localeId: _currentLanguage.sttLocale,
        listenOptions: stt.SpeechListenOptions(
          listenMode: stt.ListenMode.confirmation,
          partialResults: false,
          cancelOnError: true,
        ),
      );
    } catch (e) {
      developer.log('STT listen error: $e', name: 'VoiceService');
      _isListening = false;
      onDone();
    }
  }

  /// Stop listening
  Future<void> stopListening() async {
    _isListening = false;
    try {
      await _speech.stop();
    } catch (e) {
      developer.log('STT stop error: $e', name: 'VoiceService');
    }
  }

  // ─── Speech Synthesis ───────────────────────────────────────────

  /// Update speech parameters dynamically
  Future<void> setSpeechRate(double rate) async {
    try {
      await _tts.setSpeechRate(rate);
    } catch (e) {
      developer.log('TTS setRate error: $e', name: 'VoiceService');
    }
  }

  Future<void> setPitch(double pitch) async {
    try {
      await _tts.setPitch(pitch);
    } catch (e) {
      developer.log('TTS setPitch error: $e', name: 'VoiceService');
    }
  }

  /// Speak text aloud with cleaned markdown for clear voice synthesis.
  /// Initializes TTS lazily on first call, then reuses the initialized engine.
  Future<void> speak(String text, {Function()? onComplete}) async {
    if (text.trim().isEmpty) {
      onComplete?.call();
      return;
    }

    // Initialize TTS once if not already done
    if (!_ttsInitialized) {
      await _initTts();
    }
    if (!_ttsInitialized) {
      developer.log('TTS not available, cannot speak', name: 'VoiceService');
      onComplete?.call();
      return;
    }

    // Stop any current utterance
    try {
      await _tts.stop();
    } catch (_) {}

    _onSpeakCompletion = onComplete;

    // Clean markdown tags for natural speech
    final cleanText = text
        .replaceAll(RegExp(r'```[\s\S]*?```'), ' Code block omitted. ')
        .replaceAll(RegExp(r'`([^`]+)`'), r'$1')
        .replaceAll(RegExp(r'[*#_~`]'), '')
        .replaceAll(RegExp(r'\[([^\]]+)\]\([^\)]+\)'), r'$1')
        .trim();

    if (cleanText.isEmpty) {
      onComplete?.call();
      _onSpeakCompletion = null;
      return;
    }

    try {
      _isSpeaking = true;
      final result = await _tts.speak(cleanText);
      if (result != 1) {
        // flutter_tts returns 1 on success, 0 on failure
        developer.log('TTS speak returned: $result', name: 'VoiceService');
        // If speak returned 0 (failure), fire completion immediately
        if (result == 0) {
          _isSpeaking = false;
          if (_onSpeakCompletion != null) {
            final cb = _onSpeakCompletion;
            _onSpeakCompletion = null;
            cb!();
          }
        }
      }
    } catch (e) {
      developer.log('TTS speak error: $e', name: 'VoiceService');
      _isSpeaking = false;
      if (_onSpeakCompletion != null) {
        final cb = _onSpeakCompletion;
        _onSpeakCompletion = null;
        cb!();
      }
    }
  }

  /// Stop speaking
  Future<void> stopSpeaking() async {
    _isSpeaking = false;
    _onSpeakCompletion = null;
    try {
      await _tts.stop();
    } catch (e) {
      developer.log('TTS stop error: $e', name: 'VoiceService');
    }
  }

  void dispose() {
    _speech.stop();
    _tts.stop();
  }
}
