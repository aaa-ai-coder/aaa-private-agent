import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'dart:developer';
import 'screens/home_screen.dart';
import 'overlay_main.dart';

// Overlay entry point — must be in main.dart for flutter_overlay_window to find it
@pragma("vm:entry-point")
void overlayMain() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: OverlayApp(),
    ),
  );
}

final ValueNotifier<ThemeMode> themeNotifier = ValueNotifier(ThemeMode.system);

/// Global callback for overlay tasks — HomeScreen registers its handler here
void Function(String task)? onOverlayTask;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Set up overlay listener ASAP so we never miss tasks from the bubble
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
  if (themeStr == 'light') {
    themeNotifier.value = ThemeMode.light;
  } else if (themeStr == 'dark') {
    themeNotifier.value = ThemeMode.dark;
  } else {
    themeNotifier.value = ThemeMode.system;
  }

  runApp(const PrivateAgentApp());
}


class PrivateAgentApp extends StatelessWidget {
  const PrivateAgentApp({super.key});

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
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.indigo,
          brightness: Brightness.light,
        ),
        useMaterial3: true,
        appBarTheme: const AppBarTheme(
          centerTitle: true,
          elevation: 0,
          scrolledUnderElevation: 0,
        ),
        cardTheme: CardThemeData(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: Colors.black.withValues(alpha: 0.05)),
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
        ),
        cardTheme: CardThemeData(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: Colors.white.withValues(alpha: 0.05)),
          ),
          color: const Color(0xFF1E1E24), // Slightly lighter than pure black for depth
        ),
        scaffoldBackgroundColor: const Color(0xFF121212),
      ),
      home: const HomeScreen(),
        );
      },
    );
  }
}
