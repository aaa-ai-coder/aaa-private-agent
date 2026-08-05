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
- Multi-provider AI (Groq, NVIDIA, Ollama Cloud, DeepSeek, Puter.js, local)
- Multi-turn conversation with streaming
- Task history and analytics
- Automated data retention: auto-deletes chat history older than the
  configured window from the device, Supabase and the Firebase mirror
- API keys saved permanently to Supabase (synced on every add/update/delete)
- Automated backup cleanup: the Cloudflare Worker drops R2 DB snapshots
  older than 30 days on its daily schedule
- Dark/Light theme with Material 3
- Nebula design language: unified light/dark theme across the whole app
- PIN App Lock: salted SHA-256 PIN, auto-locks when the app is backgrounded
- Fingerprint / face unlock shortcut (Android BiometricPrompt) for the app lock
- Home dashboard status bar: live AI provider + R2 + cloud-sync indicators with
  one-tap access to Accounts & Cloud Health
- Accounts & Cloud Health screen: live status for AI, Supabase, Firebase, FCM,
  keep-alive Worker, R2 and Telegram with one-tap R2/Telegram configuration
- Keyless free AI by default (Pollinations) with anonymous `X-User-ID` to beat
  rate limits, plus ARI failover to your own keys when configured
- Puter.js AI gateway (guest mode works with no key): free access to GPT-4o,
  Claude, Gemini and Llama models via `api.puter.com` with a dedicated
  streaming adapter; add a Puter token in Settings for higher limits
- Long-press any chat message: copy, speak aloud, regenerate the AI response or
  delete the message (history stays coherent after edits)
- Phone Control Panel: one-tap grid for WiFi, Bluetooth, mobile data, airplane
  mode, hotspot, DND, auto-rotate, volume/brightness, media, ringer, wake, lock,
  screenshot, home, recent apps, clear notifications and WiFi scan - the same
  action pipeline the AI agent uses
- Expanded phone automation: wake screen, go home, recent apps, airplane mode,
  hotspot, Do Not Disturb, auto-rotate, clear notifications, saved WiFi
  password retrieval and arbitrary ADB shell commands (Shizuku/root)
- Autonomous WiFi: `connect_best_wifi` scans in-range networks, matches them
  against the phone's saved networks and connects to the best one — no password
  needed from the user; `connect_saved_wifi` connects a specific saved network
  by SSID via its stored config

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
