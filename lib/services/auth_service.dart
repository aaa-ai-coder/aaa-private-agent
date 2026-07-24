import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:google_sign_in/google_sign_in.dart';
import 'package:passkeys/authenticator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;
import '../config/supabase_config.dart';

class AuthService extends ChangeNotifier {
  sb.User? _user;
  sb.Session? _session;
  bool _isLoading = false;
  String? _error;

  final GoogleSignIn _googleSignIn = GoogleSignIn(
    serverClientId: '844358886395-tsh4o7eo55r14e6cbrs6oc1faisu6l33.apps.googleusercontent.com',
  );

  String? get deviceSha => _deviceSha;
  String? _deviceSha;

  sb.User? get user => _user;
  sb.Session? get session => _session;
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get isLoggedIn => _user != null;
  String? get userId => _user?.id;
  String? get email => _user?.email;

  AuthService() {
    _initDeviceSha();
    _checkSession();
    SupabaseConfig.client.auth.onAuthStateChange.listen((data) {
      _user = data.session?.user;
      _session = data.session;
      notifyListeners();
    });
  }

  Future<void> _initDeviceSha() async {
    final prefs = await SharedPreferences.getInstance();
    _deviceSha = prefs.getString('device_sha');
    if (_deviceSha == null) {
      final raw = DateTime.now().millisecondsSinceEpoch.toString() +
          DateTime.now().toIso8601String() +
          (kDebugMode ? 'debug' : 'release');
      _deviceSha = sha256.convert(utf8.encode(raw)).toString();
      await prefs.setString('device_sha', _deviceSha!);
    }
  }

  Future<void> _checkSession() async {
    _session = SupabaseConfig.client.auth.currentSession;
    _user = SupabaseConfig.client.auth.currentUser;
    notifyListeners();
  }

  Future<bool> signInWithEmail(String email, String password) async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      final response = await SupabaseConfig.client.auth.signInWithPassword(
        email: email.trim(),
        password: password,
      );
      _user = response.user;
      _session = response.session;
      await _linkDevice();
      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _error = e.toString().replaceFirst('Exception: ', '');
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<bool> signUp(String email, String password) async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      final response = await SupabaseConfig.client.auth.signUp(
        email: email.trim(),
        password: password,
      );
      _user = response.user;
      _session = response.session;
      await _linkDevice();
      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _error = e.toString().replaceFirst('Exception: ', '');
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<void> _linkDevice() async {
    if (_user == null || _deviceSha == null) return;
    try {
      await SupabaseConfig.client.from('user_devices').upsert({
        'user_id': _user!.id,
        'device_sha': _deviceSha,
        'auth_provider': 'supabase',
        'created_at': DateTime.now().toIso8601String(),
      }, onConflict: 'user_id,device_sha');
    } catch (_) {}
  }

  Future<bool> signInWithDevice() async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      if (_deviceSha == null) await _initDeviceSha();
      final deviceEmail = 'device_${_deviceSha!.substring(0, 16)}@privateagent.local';
      final devicePassword = 'DevicePass_${_deviceSha!}';

      try {
        final response = await SupabaseConfig.client.auth.signInWithPassword(
          email: deviceEmail,
          password: devicePassword,
        );
        _user = response.user;
        _session = response.session;
      } catch (_) {
        final response = await SupabaseConfig.client.auth.signUp(
          email: deviceEmail,
          password: devicePassword,
        );
        _user = response.user;
        _session = response.session;
      }
      await _linkDevice();
      _isLoading = false;
      notifyListeners();
      return _user != null;
    } catch (e) {
      _error = 'Device sign in error: ${e.toString().replaceFirst('Exception: ', '')}';
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<bool> signInWithGoogle() async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      final googleUser = await _googleSignIn.signIn();
      if (googleUser == null) {
        _isLoading = false;
        notifyListeners();
        return false;
      }
      final googleAuth = await googleUser.authentication;
      final idToken = googleAuth.idToken;
      final accessToken = googleAuth.accessToken;

      if (idToken != null) {
        final response = await SupabaseConfig.client.auth.signInWithIdToken(
          provider: sb.OAuthProvider.google,
          idToken: idToken,
          accessToken: accessToken,
        );
        _user = response.user;
        _session = response.session;
        await _linkDevice();
        _isLoading = false;
        notifyListeners();
        return _user != null;
      } else {
        throw Exception('Failed to obtain Google authentication tokens.');
      }
    } catch (e) {
      String errStr = e.toString();
      if (errStr.contains('10') || errStr.contains('sign_in_failed')) {
        errStr = 'Google Sign-In configuration error on this device (Code 10). Switching to instant Quick Device Sign-In...';
        _isLoading = false;
        notifyListeners();
        // Fallback to seamless Device Sha Sign In automatically
        return await signInWithDevice();
      }
      _error = errStr.replaceFirst('Exception: ', '');
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<bool> signInWithFirebaseGoogle() async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      final googleUser = await _googleSignIn.signIn();
      if (googleUser == null) {
        _isLoading = false;
        notifyListeners();
        return false;
      }
      final googleAuth = await googleUser.authentication;
      final credential = fb.GoogleAuthProvider.credential(
        idToken: googleAuth.idToken,
        accessToken: googleAuth.accessToken,
      );
      final firebaseUser = (await fb.FirebaseAuth.instance.signInWithCredential(credential)).user;
      if (firebaseUser != null) {
        final idToken = await firebaseUser.getIdToken();
        if (idToken != null) {
          final response = await SupabaseConfig.client.auth.signInWithIdToken(
            provider: sb.OAuthProvider.google,
            idToken: idToken,
            accessToken: googleAuth.accessToken,
          );
          _user = response.user;
          _session = response.session;
          await _linkDevice();
          _isLoading = false;
          notifyListeners();
          return _user != null;
        }
      }
      throw Exception('Firebase Google sign in failed.');
    } catch (e) {
      _error = e.toString().replaceFirst('Exception: ', '');
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<bool> signInWithPasskey() async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      final authenticator = PasskeyAuthenticator();
      final response = await SupabaseConfig.client.auth.signInWithPasskey(authenticator);
      _user = response.user;
      _session = response.session;
      await _linkDevice();
      _isLoading = false;
      notifyListeners();
      return _user != null;
    } catch (e) {
      String errStr = e.toString();
      if (errStr.contains('NoCredentialsAvailableException') || errStr.contains('credential')) {
        errStr = 'No passkeys found on this device. Please sign in with Google or Email first, then register a passkey.';
      } else if (errStr.contains('cancelled') || errStr.contains('Cancel')) {
        errStr = 'Passkey sign in cancelled.';
      }
      _error = errStr.replaceFirst('Exception: ', '');
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<bool> sendMagicLink(String email) async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      await SupabaseConfig.client.auth.signInWithOtp(
        email: email.trim(),
        emailRedirectTo: 'com.aaa.privateagent://callback',
      );
      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _error = e.toString().replaceFirst('Exception: ', '');
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<void> signOut() async {
    await fb.FirebaseAuth.instance.signOut();
    await SupabaseConfig.client.auth.signOut();
    _user = null;
    _session = null;
    notifyListeners();
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }
}
