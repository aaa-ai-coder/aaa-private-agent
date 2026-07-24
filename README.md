# AAA Private Agent

AI-powered Android agent app with floating overlay, voice control, and full device automation.

## Features
- Floating overlay chat bubble for hands-free AI control
- Voice-to-text (STT) and text-to-voice (TTS)
- Full device automation (click, type, scroll, open apps, SMS, calls)
- Google Sign-In with permanent device SHA persistence
- Email + Password + Passkey authentication
- Firebase Auth + Crashlytics + Analytics
- Supabase backend for user data collection
- Cloudflare R2 for heavy data storage (screenshots, files)
- Multi-provider AI (Groq, NVIDIA, Ollama Cloud, DeepSeek, local)
- Multi-turn conversation with streaming
- Task history and analytics
- Dark/Light theme with Material 3

## Setup

### 1. Firebase
Place `google-services.json` in `android/app/` (gitignored). Get it from Firebase Console.

### 2. Supabase
Update credentials in `lib/config/supabase_config.dart`.

### 3. Cloudflare R2
Configure R2 settings in Settings → Storage.

### 4. Build
```bash
flutter pub get
flutter build apk --release
```

## Auto-Build (GitHub Actions)
Push a tag `v*` or trigger `build-apk.yml` to build and upload APK artifacts.
