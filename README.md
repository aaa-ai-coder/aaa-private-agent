# Nova AI

Nova AI is a brand-new, unified AI assistant for Android built from two projects merged into one:

- **PrivateLM** (`cross-platform-llm-client`) — local on-device LLM inference (llama.cpp GGUF + LiteRT-LM), cloud AI, chat/task/model management, image generation, document extraction, background services.
- **AAA Private Agent** — the previous app's power features: automatic cloud key backup to Supabase, Free AI (keyless), voice input + read-aloud.

A single app that runs real AI **on your phone** with zero internet, and drops back to any cloud provider when you want more power.

---

## What It Does

- **Local Inference on Android** — Download and run GGUF models (llama.cpp, GPU via Vulkan) or LiteRT-LM models directly on your phone. No internet required after download.
- **Cloud API Fallback** — Switch between OpenAI, Anthropic, Google Gemini, Kimi (Moonshot AI), OpenRouter, DeepSeek, NVIDIA NIM, custom OpenAI-compatible endpoints, or **Free AI** (keyless, zero setup).
- **Multimodal Chat** — Send text and images; vision works with local (Qwen2-VL) and cloud models.
- **Voice** — Speech-to-text input button plus text-to-speech read-aloud on every assistant reply.
- **Persistent Sessions** — All chats, tasks, and settings stored locally via Hive.
- **Background Services** — Image generation notifications, boot persistence, and background task handling.
- **Smart Auto-Configuration** — First launch detects device RAM and recommends context size / token limits.
- **Task Management** — Structured AI-assisted workflows alongside free-form chat.
- **Automatic Cloud Key Backup** — Point at your own Supabase project; every API key and provider/model setting syncs automatically and can be restored on any device.
- **Document Extraction** — Read PDFs and documents in chat.

## Stack

- Flutter 3.x (Dart >=3.3.0), GetX, Hive, Dio + `package:http`
- `llama_flutter_android` (llama.cpp) · `flutter_litert_lm` (LiteRT) · `sd_flutter_android` (Stable Diffusion)
- Firebase Core / Messaging / Crashlytics, `flutter_background_service`, `flutter_local_notifications`

## Build

```bash
flutter pub get
flutter build apk --release
```

Release APKs are produced automatically by GitHub Actions on every push to `main` (see `.github/workflows/build-apk.yml`). The workflow checks out the repo **with submodules** (the Stable Diffusion native engine), generates a release keystore, and publishes a `Nova-AI.apk` release.

### Submodules

The Stable Diffusion native engine is a git submodule:

```bash
git submodule update --init --recursive --depth 1
```

## Notes

- API keys never leave your device unless you configure cloud key backup, and even then they go only to the Supabase project you specify.
- Free AI requires no key at all.
