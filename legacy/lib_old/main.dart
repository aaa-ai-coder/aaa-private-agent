import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'dart:developer';
import 'config/feature_flags.dart';
import 'config/supabase_config.dart';
import 'theme/app_theme.dart';
import 'services/app_lock_service.dart';
import 'services/auth_service.dart';
import 'services/cloudflare_service.dart';
import 'services/firebase_service.dart';
import 'services/retention_service.dart';
import 'services/storage_service.dart';
import 'screens/home_screen.dart';
import 'screens/onboarding_screen.dart';
import 'screens/login_screen.dart';
import 'screens/app_lock_screen.dart';
import 'overlay_main.dart';

@pragma("vm:entry-point")
void overlayMain() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.overlay(),
      home: const OverlayApp(),
    ),
  );
}

final ValueNotifier<ThemeMode> themeNotifier = ValueNotifier(ThemeMode.system);

void Function(String task)? onOverlayTask;

final AuthService authService = AuthService();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    // Register the FCM background handler BEFORE Firebase.initializeApp()
    FirebaseMessaging.onBackgroundMessage(firebaseBackgroundHandler);
    await Firebase.initializeApp();

    FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterFatalError;
    PlatformDispatcher.instance.onError = (error, stack) {
      FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
      return true;
    };

    // Initialize Firebase services (FCM, Firestore, Storage)
    await FirebaseService.init();
  } catch (e) {
    log('Firebase initialization warning: $e');
  }

  try {
    await SupabaseConfig.init();
  } catch (e) {
    log('Supabase initialization warning: $e');
  }

  // Load storage credentials and wake the Supabase project via the
  // Cloudflare keep-alive worker (fire-and-forget).
  try {
    await StorageService.init();
    unawaited(CloudflareService.pingKeepalive());
  } catch (e) {
    log('Storage/keepalive initialization warning: $e');
  }

  // Automated data lifecycle: prune chat history older than the retention
  // window and ask the Worker to drop expired R2 snapshots (fire-and-forget).
  unawaited(RetentionService.runAutomatedCleanup());

  if (FeatureFlags.floatingOverlayEnabled) {
    FlutterOverlayWindow.overlayListener.listen((event) {
      log("Main app received from overlay: $event");
      if (event is String && event.trim().isNotEmpty) {
        if (onOverlayTask != null) {
          onOverlayTask!(event.trim());
        } else {
          log("Warning: overlay task received but no handler registered yet");
        }
      }
    });
  }

  final prefs = await SharedPreferences.getInstance();
  final themeStr = prefs.getString('themeMode');
  switch (themeStr) {
    case 'dark':
      themeNotifier.value = ThemeMode.dark;
    case 'light':
      themeNotifier.value = ThemeMode.light;
    default:
      themeNotifier.value = ThemeMode.system;
  }
  FeatureFlags.floatingIconEnabled =
      prefs.getBool('floating_icon_enabled') ?? true;

  runApp(const PrivateAgentApp());
}

class PrivateAgentApp extends StatefulWidget {
  const PrivateAgentApp({super.key});

  @override
  State<PrivateAgentApp> createState() => _PrivateAgentAppState();
}

class _PrivateAgentAppState extends State<PrivateAgentApp>
    with WidgetsBindingObserver {
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    authService.addListener(_checkAuth);
    _checkAuth();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    authService.removeListener(_checkAuth);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Auto-lock the app whenever it is backgrounded and the PIN lock is on.
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      unawaited(_lockIfEnabled());
    }
  }

  Future<void> _lockIfEnabled() async {
    if (await AppLockService.isEnabled()) {
      AppLockService.lock();
    }
  }

  void _checkAuth() {
    if (mounted) setState(() => _initialized = true);
  }

  Future<({bool lockEnabled, bool onboarding})> _homeGate() async {
    final prefs = await SharedPreferences.getInstance();
    return (
      lockEnabled: await AppLockService.isEnabled(),
      onboarding: prefs.getBool('onboarding_completed') ?? false,
    );
  }

  Widget _spinner() => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeNotifier,
      builder: (context, ThemeMode currentMode, child) {
        return MaterialApp(
          title: 'AAA Private Agent',
          debugShowCheckedModeBanner: false,
          themeMode: currentMode,
          theme: AppTheme.light(),
          darkTheme: AppTheme.dark(),
          home: _buildGatedHome(),
        );
      },
    );
  }

  Widget _buildGatedHome() {
    if (!_initialized) return _spinner();
    if (!authService.isLoggedIn) {
      return LoginScreen(authService: authService);
    }
    return ValueListenableBuilder<bool>(
      valueListenable: AppLockService.lockedNotifier,
      builder: (context, locked, child) {
        return FutureBuilder<({bool lockEnabled, bool onboarding})>(
          future: _homeGate(),
          builder: (context, snapshot) {
            if (!snapshot.hasData) return _spinner();
            final gate = snapshot.data!;
            if (gate.lockEnabled && locked) {
              return const AppLockScreen();
            }
            return gate.onboarding
                ? const HomeScreen()
                : const OnboardingScreen();
          },
        );
      },
    );
  }
}
