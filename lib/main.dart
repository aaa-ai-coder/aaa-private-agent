import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'dart:developer';
import 'screens/home_screen.dart';
import 'screens/onboarding_screen.dart';
import 'overlay_main.dart';

@pragma("vm:entry-point")
void overlayMain() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    const MaterialApp(debugShowCheckedModeBanner: false, home: OverlayApp()),
  );
}

final ValueNotifier<ThemeMode> themeNotifier = ValueNotifier(ThemeMode.system);

void Function(String task)? onOverlayTask;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

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

  final prefs = await SharedPreferences.getInstance();
  final themeStr = prefs.getString('themeMode');
  if (themeStr == 'dark') {
    themeNotifier.value = ThemeMode.dark;
  } else {
    themeNotifier.value = ThemeMode.light;
  }

  final onboardingCompleted = prefs.getBool('onboarding_completed') ?? false;

  runApp(PrivateAgentApp(onboardingCompleted: onboardingCompleted));
}

class PrivateAgentApp extends StatelessWidget {
  final bool onboardingCompleted;
  const PrivateAgentApp({super.key, required this.onboardingCompleted});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeNotifier,
      builder: (context, ThemeMode currentMode, child) {
        return MaterialApp(
          title: 'PrivateAgent',
          debugShowCheckedModeBanner: false,
          themeMode: currentMode,
          theme: ThemeData(
            brightness: Brightness.light,
            primaryColor: Colors.black,
            scaffoldBackgroundColor: const Color(0xFFFFFFFF),
            colorScheme: const ColorScheme.light(
              primary: Colors.black,
              secondary: Colors.black,
              surface: Color(0xFFFFFFFF),
              error: Colors.redAccent,
            ),
            useMaterial3: true,
            appBarTheme: const AppBarTheme(
              centerTitle: true,
              elevation: 0,
              scrolledUnderElevation: 0,
              backgroundColor: Color(0xFFFFFFFF),
              foregroundColor: Colors.black,
              iconTheme: IconThemeData(color: Colors.black),
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
                borderRadius: BorderRadius.circular(16),
                side: const BorderSide(color: Color(0xFFE2E2E8), width: 1.5),
              ),
            ),
          ),
          darkTheme: ThemeData(
            colorScheme: ColorScheme.fromSeed(
              seedColor: Colors.indigo,
              brightness: Brightness.dark,
            ),
            useMaterial3: true,
            appBarTheme: const AppBarTheme(
              centerTitle: true,
              elevation: 0,
              scrolledUnderElevation: 0,
              systemOverlayStyle: SystemUiOverlayStyle(
                statusBarColor: Colors.transparent,
                statusBarIconBrightness: Brightness.light,
                statusBarBrightness: Brightness.dark,
              ),
            ),
            cardTheme: CardThemeData(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(color: Colors.white.withValues(alpha: 0.05)),
              ),
              color: const Color(
                0xFF1E1E24,
              ), // Slightly lighter than pure black for depth
            ),
            scaffoldBackgroundColor: const Color(0xFF121212),
          ),
          home: onboardingCompleted ? const HomeScreen() : const OnboardingScreen(),
        );
      },
    );
  }
}
