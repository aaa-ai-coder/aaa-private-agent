import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// PIN-based app lock.
///
/// The PIN is never stored in plaintext — only a salted SHA-256 hash lives in
/// SharedPreferences. The app auto-locks whenever it is backgrounded and the
/// lock is enabled, and stays locked until the correct PIN is entered.
class AppLockService {
  AppLockService._();

  static const String _enabledKey = 'app_lock_enabled';
  static const String _pinHashKey = 'app_lock_pin_hash';
  static const String _pinSaltKey = 'app_lock_pin_salt';

  /// Reflects the current in-memory lock state. When `true`, the UI shows the
  /// unlock screen instead of the main app.
  static final ValueNotifier<bool> lockedNotifier = ValueNotifier<bool>(false);

  static Future<bool> isEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_enabledKey) ?? false;
  }

  static Future<String> _generateSalt() async {
    final r = Random.secure();
    return base64UrlEncode(
      List<int>.generate(16, (_) => r.nextInt(256)),
    );
  }

  static Future<String> _hashPin(String pin, String salt) async {
    return sha256.convert(utf8.encode('$salt::$pin')).toString();
  }

  /// Store a new PIN (hashed with a fresh salt) and enable the lock.
  static Future<void> setPin(String pin) async {
    final salt = await _generateSalt();
    final hash = await _hashPin(pin, salt);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_pinHashKey, hash);
    await prefs.setString(_pinSaltKey, salt);
    await prefs.setBool(_enabledKey, true);
    lockedNotifier.value = false;
  }

  /// Verify a candidate PIN against the stored hash.
  static Future<bool> verifyPin(String pin) async {
    final prefs = await SharedPreferences.getInstance();
    final hash = prefs.getString(_pinHashKey);
    final salt = prefs.getString(_pinSaltKey);
    if (hash == null || salt == null || pin.isEmpty) return false;
    final candidate = await _hashPin(pin, salt);
    return candidate == hash;
  }

  /// Disable the lock and remove all PIN material.
  static Future<void> disable() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_enabledKey);
    await prefs.remove(_pinHashKey);
    await prefs.remove(_pinSaltKey);
    lockedNotifier.value = false;
  }

  /// Lock the app immediately (called when the app is backgrounded).
  static void lock() {
    if (lockedNotifier.value) return;
    lockedNotifier.value = true;
  }

  /// Unlock after a successful PIN entry.
  static void unlock() {
    lockedNotifier.value = false;
  }
}
