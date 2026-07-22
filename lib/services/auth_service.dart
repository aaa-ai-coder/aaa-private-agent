import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/supabase_config.dart';

class AuthService extends ChangeNotifier {
  User? _user;
  Session? _session;
  bool _isLoading = false;
  String? _error;

  User? get user => _user;
  Session? get session => _session;
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get isLoggedIn => _user != null;
  String? get userId => _user?.id;
  String? get email => _user?.email;

  AuthService() {
    _checkSession();
    SupabaseConfig.client.auth.onAuthStateChange.listen((data) {
      _user = data.session?.user;
      _session = data.session;
      notifyListeners();
    });
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

  Future<bool> signInWithGoogle() async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      await SupabaseConfig.client.auth.signInWithOAuth(
        OAuthProvider.google,
        redirectTo: 'com.aaa.privateagent://callback',
      );
      _user = SupabaseConfig.client.auth.currentUser;
      _session = SupabaseConfig.client.auth.currentSession;
      _isLoading = false;
      notifyListeners();
      return _user != null;
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
      await SupabaseConfig.client.auth.signInWithPasskey();
      _user = SupabaseConfig.client.auth.currentUser;
      _session = SupabaseConfig.client.auth.currentSession;
      _isLoading = false;
      notifyListeners();
      return _user != null;
    } catch (e) {
      _error = e.toString().replaceFirst('Exception: ', '');
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<bool> signUpWithPasskey() async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      await SupabaseConfig.client.auth.signUpWithPasskey();
      _user = SupabaseConfig.client.auth.currentUser;
      _session = SupabaseConfig.client.auth.currentSession;
      _isLoading = false;
      notifyListeners();
      return _user != null;
    } catch (e) {
      _error = e.toString().replaceFirst('Exception: ', '');
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
