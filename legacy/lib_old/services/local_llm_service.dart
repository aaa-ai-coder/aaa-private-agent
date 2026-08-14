import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:llamadart/llamadart.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/ai_service.dart';
import '../services/memory_service.dart';

/// Thrown when the user cancels an in-app model download. The partial file is
/// removed by the service before this reaches the caller.
class LocalModelCancelException implements Exception {
  const LocalModelCancelException();

  @override
  String toString() => 'Download cancelled';
}

/// A downloadable GGUF model option offered by the in-app model picker. The
/// exact byte size is used for a post-download sanity check, while [minBytes]
/// guards against truncated files on download paths that serve different
/// quantisation variants.
class LocalModelOption {
  final String key;
  final String name;
  final String fileName;
  final String url;
  final int bytes;
  final int minBytes;
  final String sizeLabel;

  const LocalModelOption({
    required this.key,
    required this.name,
    required this.fileName,
    required this.url,
    required this.bytes,
    required this.minBytes,
    required this.sizeLabel,
  });
}

/// Runs a real on-device LLM (Qwen 2.5 0.5B GGUF) on the phone via llama.cpp
/// through llamadart. Unlike a bundled model the GGUF is downloaded once
/// inside the app (Hugging Face) and cached in app storage, so the APK stays
/// small. The weights are loaded lazily per chat turn and unloaded again after
/// an idle period, so no phone RAM is wasted while not chatting.
class LocalLlmService {
  LocalLlmService._();

  static final LocalLlmService instance = LocalLlmService._();

  /// SharedPreferences key enabling the on-device AI.
  static const String prefEnabled = 'use_bundled_llm';

  /// SharedPreferences key for the currently selected model option.
  static const String prefModelKey = 'llm_model_key';

  /// Qwen 2.5 0.5B GGUF options, downloaded on demand. Sizes verified from the
  /// Hugging Face repository (q6_K = 650,379,104 bytes).
  static const List<LocalModelOption> models = [
    LocalModelOption(
      key: 'qwen2.5-0.5b-q6_k',
      name: 'Qwen 2.5 0.5B (q6_K)',
      fileName: 'qwen2.5-0.5b-instruct-q6_k.gguf',
      url:
          'https://huggingface.co/Qwen/Qwen2.5-0.5B-Instruct-GGUF/resolve/main/qwen2.5-0.5b-instruct-q6_k.gguf',
      bytes: 650379104,
      minBytes: 640000000,
      sizeLabel: '~620 MB',
    ),
    LocalModelOption(
      key: 'qwen2.5-0.5b-q4_k_m',
      name: 'Qwen 2.5 0.5B (q4_K_M)',
      fileName: 'qwen2.5-0.5b-instruct-q4_k_m.gguf',
      url:
          'https://huggingface.co/Qwen/Qwen2.5-0.5B-Instruct-GGUF/resolve/main/qwen2.5-0.5b-instruct-q4_k_m.gguf',
      bytes: 491673344,
      minBytes: 450000000,
      sizeLabel: '~470 MB',
    ),
  ];

  LlamaEngine? _engine;
  Timer? _idleTimer;
  bool _busy = false;

  static Future<bool> isEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(prefEnabled) ?? true;
  }

  Future<LocalModelOption> selectedModel() async {
    final prefs = await SharedPreferences.getInstance();
    final key = prefs.getString(prefModelKey);
    for (final m in models) {
      if (m.key == key) return m;
    }
    return models.first;
  }

  Future<void> setSelectedModel(LocalModelOption model) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(prefModelKey, model.key);
  }

  Future<Directory> _modelsDir() async {
    final support = await getApplicationSupportDirectory();
    final dir = Directory('${support.path}/llm_models');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  /// Returns the path of the (valid) downloaded file for [model], or null when
  /// it is missing or does not pass the size sanity check.
  Future<String?> modelFilePath({LocalModelOption? model}) async {
    final m = model ?? await selectedModel();
    final file = File('${(await _modelsDir()).path}/${m.fileName}');
    if (!await file.exists()) return null;
    final len = await file.length();
    if (len < m.minBytes) return null;
    return file.path;
  }

  Future<bool> isDownloaded({LocalModelOption? model}) async =>
      (await modelFilePath(model: model)) != null;

  /// Bytes on disk of the currently selected model, or null if not downloaded.
  Future<int?> downloadedBytes() async {
    final m = await selectedModel();
    final file = File('${(await _modelsDir()).path}/${m.fileName}');
    if (!await file.exists()) return null;
    final len = await file.length();
    return len >= m.minBytes ? len : null;
  }

  /// Downloads [model] from Hugging Face into app storage, reporting 0.0..1.0
  /// progress. [shouldCancel] is polled per chunk; returning true aborts the
  /// download and removes the partial file. Throws [LocalModelCancelException]
  /// on cancellation and [StateError]/[HttpException] on failure.
  Future<void> download(
    LocalModelOption model, {
    void Function(double progress)? onProgress,
    bool Function()? shouldCancel,
  }) async {
    if (await isDownloaded(model: model)) return;

    final dir = await _modelsDir();
    final partFile = File('${dir.path}/${model.fileName}.part');
    if (await partFile.exists()) {
      await partFile.delete();
    }

    final client = http.Client();
    try {
      final req = http.Request('GET', Uri.parse(model.url));
      req.headers['User-Agent'] = 'AAA-Private-Agent';
      final res = await client.send(req).timeout(const Duration(seconds: 30));
      if (res.statusCode != 200) {
        throw HttpException(
          'Server returned HTTP ${res.statusCode} (${res.reasonPhrase})',
        );
      }
      final total = res.contentLength ?? 0;
      final sink = partFile.openWrite();
      var bytes = 0;
      try {
        await for (final chunk in res.stream.timeout(
          const Duration(seconds: 90),
        )) {
          if (shouldCancel?.call() ?? false) {
            throw const LocalModelCancelException();
          }
          sink.add(chunk);
          bytes += chunk.length;
          if (total > 0) {
            onProgress?.call(bytes / total);
          }
        }
      } finally {
        await sink.flush();
        await sink.close();
      }

      final len = await partFile.length();
      if (len < model.minBytes) {
        throw StateError(
          'Downloaded file is too small (${len} bytes, expected at least '
          '${model.minBytes}) — the download may have been interrupted.',
        );
      }
      if (bytes >= 4) {
        final raf = await partFile.open();
        final magic = await raf.read(4);
        await raf.close();
        if (utf8.decode(magic, allowMalformed: true) != 'GGUF') {
          throw StateError('Downloaded file is not a valid GGUF model.');
        }
      }

      final finalFile = File('${dir.path}/${model.fileName}');
      if (await finalFile.exists()) {
        await finalFile.delete();
      }
      await partFile.rename(finalFile.path);
    } finally {
      client.close();
    }
  }

  /// Removes the downloaded model file (and any partial download) for
  /// [model], freeing its storage.
  Future<void> removeModel({LocalModelOption? model}) async {
    final m = model ?? await selectedModel();
    await unloadNow();
    final dir = await _modelsDir();
    final file = File('${dir.path}/${m.fileName}');
    if (await file.exists()) {
      await file.delete();
    }
    final part = File('${dir.path}/${m.fileName}.part');
    if (await part.exists()) {
      await part.delete();
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
      throw StateError('On-device model is not downloaded yet');
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

  /// Runs a single chat turn through the on-device LLM. [history] is an
  /// alternating [user, assistant] list used as short conversation context.
  /// Returns null when the model is unavailable (not downloaded, or a native
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
