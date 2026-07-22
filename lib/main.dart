import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:developer';
import 'config/feature_flags.dart';
import 'config/supabase_config.dart';
import 'services/auth_service.dart';
import 'screens/home_screen.dart';
import 'screens/onboarding_screen.dart';
import 'screens/login_screen.dart';
import 'overlay_main.dart';

@pragma("vm:entry-point")
void overlayMain() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        canvasColor: Colors.transparent,
        scaffoldBackgroundColor: Colors.transparent,
        cardColor: Colors.white,
        dialogBackgroundColor: Colors.transparent,
        primaryColor: const Color(0xFF4F46E5),
        useMaterial3: true,
        colorScheme: const ColorScheme.light(
          background: Colors.transparent,
          primary: Color(0xFF4F46E5),
          surface: Colors.white,
          onSurface: Color(0xFF1E293B),
          onPrimary: Colors.white,
        ),
      ),
      builder: (context, child) {
        return Container(color: Colors.transparent, child: child);
      },
      home: const OverlayApp(),
    ),
  );
}

final ValueNotifier<ThemeMode> themeNotifier = ValueNotifier(ThemeMode.system);

void Function(String task)? onOverlayTask;

final AuthService authService = AuthService();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await SupabaseConfig.init();

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
  if (themeStr == 'dark') {
    themeNotifier.value = ThemeMode.dark;
  } else {
    themeNotifier.value = ThemeMode.light;
  }

  runApp(const PrivateAgentApp());
}

class PrivateAgentApp extends StatefulWidget {
  const PrivateAgentApp({super.key});

  @override
  State<PrivateAgentApp> createState() => _PrivateAgentAppState();
}

class _PrivateAgentAppState extends State<PrivateAgentApp> {
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    authService.addListener(_checkAuth);
    _checkAuth();
  }

  @override
  void dispose() {
    authService.removeListener(_checkAuth);
    super.dispose();
  }

  void _checkAuth() {
    if (mounted) setState(() => _initialized = true);
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeNotifier,
      builder: (context, ThemeMode currentMode, child) {
        return MaterialApp(
          title: 'AAA Private Agent',
          debugShowCheckedModeBanner: false,
          themeMode: currentMode,
          theme: ThemeData(
            brightness: Brightness.light,
            primaryColor: const Color(0xFF6366F1), // Indigo/Violet
            scaffoldBackgroundColor: const Color(0xFFF1F5F9), // Slate 100
            colorScheme: const ColorScheme.light(
              primary: Color(0xFF6366F1),
              secondary: Color(0xFF00D2FF), // Cyan glow
              surface: Color(0xFFFFFFFF),
              onSurface: Color(0xFF0F172A),
              surfaceContainerHighest: Color(0xFFE2E8F0),
              error: Colors.redAccent,
            ),
            useMaterial3: true,
            appBarTheme: const AppBarTheme(
              centerTitle: true,
              elevation: 0,
              scrolledUnderElevation: 0,
              backgroundColor: Colors.transparent,
              foregroundColor: Color(0xFF0F172A),
              iconTheme: IconThemeData(color: Color(0xFF0F172A)),
              systemOverlayStyle: SystemUiOverlayStyle(
                statusBarColor: Colors.transparent,
                statusBarIconBrightness: Brightness.dark,
                statusBarBrightness: Brightness.light,
              ),
            ),
            cardTheme: CardThemeData(
              elevation: 0,
              color: const Color(0xFFFFFFFF),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
                side: const BorderSide(
                  color: Color(0xFFCBD5E1),
                  width: 1.2,
                ),
              ),
            ),
          ),
          darkTheme: ThemeData(
            brightness: Brightness.dark,
            primaryColor: const Color(0xFF818CF8), // Soft Violet/Indigo
            scaffoldBackgroundColor: const Color(0xFF0A0E1A), // Obsidian midnight
            colorScheme: const ColorScheme.dark(
              primary: Color(0xFF818CF8),
              secondary: Color(0xFF00E5FF), // Cyber Cyan
              surface: Color(0xFF131B2E), // Glass dark card
              onSurface: Color(0xFFF8FAFC),
              surfaceContainerHighest: Color(0xFF1E293B),
              error: Colors.redAccent,
            ),
            useMaterial3: true,
            appBarTheme: const AppBarTheme(
              centerTitle: true,
              elevation: 0,
              scrolledUnderElevation: 0,
              backgroundColor: Colors.transparent,
              foregroundColor: Color(0xFFF8FAFC),
              iconTheme: IconThemeData(color: Color(0xFFF8FAFC)),
              systemOverlayStyle: SystemUiOverlayStyle(
                statusBarColor: Colors.transparent,
                statusBarIconBrightness: Brightness.light,
                statusBarBrightness: Brightness.dark,
              ),
            ),
            cardTheme: CardThemeData(
              elevation: 0,
              color: const Color(0xFF131B2E),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
                side: BorderSide(
                  color: const Color(0xFF00E5FF).withOpacity(0.2),
                  width: 1.2,
                ),
              ),
            ),
          ),
          home: _buildHome(),
        );
      },
    );
  }

  Widget _buildHome() {
    if (!_initialized) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    if (!authService.isLoggedIn) {
      return LoginScreen(authService: authService);
    }
    return FutureBuilder<bool>(
      future: SharedPreferences.getInstance().then(
        (prefs) => prefs.getBool('onboarding_completed') ?? false,
      ),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        return snapshot.data!
            ? const HomeScreen()
            : const OnboardingScreen();
      },
    );
  }
}
