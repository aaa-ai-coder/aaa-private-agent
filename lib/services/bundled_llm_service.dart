import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart' show rootBundle;
import 'package:llamadart/llamadart.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/ai_service.dart';
import '../services/memory_service.dart';

/// Runs a real on-device LLM (Qwen 2.5 0.5B, GGUF q6_K, ~620 MB) that is
/// bundled inside the APK itself. The model file is extracted once from Flutter
/// assets to app storage on first use, then loaded lazily through llama.cpp via
/// llamadart. It consumes no RAM until a chat turn starts and unloads itself
/// again after an idle period, so the phone memory is not wasted.
class BundledLlmService {
  BundledLlmService._();

  static final BundledLlmService instance = BundledLlmService._();

  /// Flutter asset path of the bundled GGUF, matching the file downloaded by
  /// the CI workflow into `assets/models/`.
  static const String assetModelPath =
      'assets/models/qwen2.5-0.5b-instruct-q6_k.gguf';

  static const String modelFileName = 'qwen2.5-0.5b-instruct-q6_k.gguf';

  /// Exact byte size of the q6_K GGUF, used to validate the extracted file.
  static const int expectedModelBytes = 650379104;

  /// SharedPreferences key enabling the built-in on-device AI.
  static const String prefEnabled = 'use_bundled_llm';

  static const String _modelName = 'Qwen 2.5 0.5B (q6_K)';

  LlamaEngine? _engine;
  Timer? _idleTimer;
  bool _busy = false;

  String get modelName => _modelName;

  static Future<bool> isEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(prefEnabled) ?? true;
  }

  Future<Directory> _modelsDir() async {
    final support = await getApplicationSupportDirectory();
    final dir = Directory('${support.path}/models');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  Future<String?> modelFilePath() async {
    final file = File('${(await _modelsDir()).path}/$modelFileName');
    if (!await file.exists()) return null;
    if (await file.length() != expectedModelBytes) return null;
    return file.path;
  }

  Future<bool> isExtracted() async => (await modelFilePath()) != null;

  /// Extracts the bundled GGUF from the APK assets into app storage.
  /// Called once; [onProgress] reports 0.0..1.0 while writing the file.
  Future<void> extract({void Function(double progress)? onProgress}) async {
    if (await isExtracted()) return;
    final data = await rootBundle.load(assetModelPath);
    if (data.lengthInBytes != expectedModelBytes) {
      throw StateError(
        'Bundled model size mismatch: ${data.lengthInBytes} bytes',
      );
    }
    final file = File('${(await _modelsDir()).path}/$modelFileName');
    final sink = file.openWrite();
    const chunkSize = 4 * 1024 * 1024;
    final total = data.lengthInBytes;
    var offset = 0;
    try {
      while (offset < total) {
        final n = (total - offset < chunkSize) ? total - offset : chunkSize;
        sink.add(data.buffer.asUint8List(offset, n));
        offset += n;
        onProgress?.call(offset / total);
        if (n >= chunkSize) {
          await sink.flush();
        }
      }
    } finally {
      await sink.close();
    }
    if (await file.length() != expectedModelBytes) {
      throw StateError('Model extraction failed: size check did not match');
    }
  }

  /// Removes the extracted model file from app storage, freeing ~620 MB.
  Future<void> removeModel() async {
    await unloadNow();
    final file = File('${(await _modelsDir()).path}/$modelFileName');
    if (await file.exists()) {
      await file.delete();
    }
  }

  Future<LlamaEngine> _ensureEngine() async {
    if (_engine == null) {
      _engine = LlamaEngine(LlamaBackend());
    }
    return _engine!;
  }

  Future<void> _loadIfNeeded() async {
    final engine = await _ensureEngine();
    if (engine.isReady) return;
    final path = await modelFilePath();
    if (path == null) {
      throw StateError('Bundled model is not extracted yet');
    }
    final cpus = Platform.numberOfProcessors;
    await engine.loadModel(
      path,
      modelParams: ModelParams(
        contextSize: 2048,
        gpuLayers: 0,
        numberOfThreads: cpus > 4 ? 4 : (cpus > 0 ? cpus : 2),
        useMmap: true,
        useMlock: false,
      ),
    );
  }

  /// Runs a single chat turn through the bundled on-device LLM. [history] is an
  /// alternating [user, assistant] list used as short conversation context.
  /// Returns null when the model is unavailable (not extracted, or a native
  /// error occurred), so callers can fall back to the intent assistant.
  Future<String?> complete(
    String userText, {
    List<String>? history,
    int maxTokens = 512,
  }) async {
    if (_busy) return null;
    _busy = true;
    try {
      return await _completeLocked(
        userText,
        history: history,
        maxTokens: maxTokens,
      );
    } finally {
      _busy = false;
    }
  }

  Future<String?> _completeLocked(
    String userText, {
    List<String>? history,
    int maxTokens = 512,
  }) async {
    try {
      await _loadIfNeeded();
      final engine = _engine;
      if (engine == null) return null;

      final messages = <LlamaChatMessage>[];
      final system = AiService.instance.chatSystemPrompt +
          await MemoryService.memoryBlock();
      messages.add(
        LlamaChatMessage.fromText(
          role: LlamaChatRole.system,
          text: system,
        ),
      );
      final hist = history ?? const <String>[];
      for (var i = 0; i + 1 < hist.length; i += 2) {
        messages.add(
          LlamaChatMessage.fromText(
            role: LlamaChatRole.user,
            text: hist[i],
          ),
        );
        messages.add(
          LlamaChatMessage.fromText(
            role: LlamaChatRole.assistant,
            text: hist[i + 1],
          ),
        );
      }
      messages.add(
        LlamaChatMessage.fromText(
          role: LlamaChatRole.user,
          text: userText,
        ),
      );

      final buffer = StringBuffer();
      await for (final chunk in engine.create(
        messages,
        params: GenerationParams(
          maxTokens: maxTokens,
          temp: 0.7,
          topK: 40,
          topP: 0.9,
          penalty: 1.1,
          stopSequences: const ['<|im_end|>'],
        ),
      )) {
        final text = chunk.choices.first.delta.content;
        if (text != null) {
          buffer.write(text);
        }
      }

      final reply = buffer.toString().trim();
      _scheduleIdleUnload();
      if (reply.isEmpty) return null;
      return reply;
    } catch (e) {
      await unloadNow();
      return null;
    }
  }

  void _scheduleIdleUnload() {
    _idleTimer?.cancel();
    _idleTimer = Timer(const Duration(minutes: 10), () {
      unawaited(unloadModelOnly());
    });
  }

  /// Unloads the model weights (frees RAM) while keeping the engine object
  /// warm, so the next turn can reload quickly via mmap.
  Future<void> unloadModelOnly() async {
    _idleTimer?.cancel();
    _idleTimer = null;
    try {
      await _engine?.unloadModel();
    } catch (_) {}
  }

  /// Fully releases the native engine.
  Future<void> unloadNow() async {
    _idleTimer?.cancel();
    _idleTimer = null;
    try {
      await _engine?.dispose();
    } catch (_) {}
    _engine = null;
  }
}
