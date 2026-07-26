import 'dart:io';
import 'dart:developer' as developer;
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Centralized Firebase integration for FCM, Firestore, and Storage.
/// Complements Supabase — Firestore for real-time cross-device sync,
/// FCM for push notifications, Storage for heavy file uploads.
class FirebaseService {
  static final FirebaseMessaging _fcm = FirebaseMessaging.instance;
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static final FirebaseStorage _storage = FirebaseStorage.instance;

  static bool _initialized = false;
  static String? _fcmToken;
  static bool _fcmEnabled = false;

  // ─── Initialization ──────────────────────────────────────────────

  static Future<void> init() async {
    if (_initialized) return;

    try {
      // Request notification permission (iOS shows dialog, Android grants silently)
      final permission = await _fcm.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        provisional: false,
      );
      _fcmEnabled = permission.authorizationStatus == AuthorizationStatus.authorized ||
          permission.authorizationStatus == AuthorizationStatus.provisional;

      // Get FCM token
      _fcmToken = await _fcm.getToken();
      developer.log('FCM token: $_fcmToken', name: 'FirebaseService');

      // Listen for token refresh
      _fcm.onTokenRefresh.listen((newToken) {
        developer.log('FCM token refreshed: $newToken', name: 'FirebaseService');
        _fcmToken = newToken;
        _saveTokenLocally(newToken);
      });

      // Handle foreground messages
      FirebaseMessaging.onMessage.listen(_handleForegroundMessage);

      // Handle notification tap when app is in background
      FirebaseMessaging.onMessageOpenedApp.listen(_handleNotificationTap);

      // Handle notification that launched the app
      final initialMessage = await _fcm.getInitialMessage();
      if (initialMessage != null) {
        _handleNotificationTap(initialMessage);
      }

      // Load saved token
      final prefs = await SharedPreferences.getInstance();
      final savedToken = prefs.getString('fcm_token');
      if (savedToken != null && savedToken != _fcmToken) {
        _fcmToken = savedToken;
      }

      _initialized = true;
      developer.log('FirebaseService initialized', name: 'FirebaseService');
    } catch (e) {
      developer.log('FirebaseService init error: $e', name: 'FirebaseService');
    }
  }

  /// Get the current FCM device token
  static String? get fcmToken => _fcmToken;

  /// Whether FCM push is enabled
  static bool get isFcmEnabled => _fcmEnabled;

  // ─── FCM: Topic Subscription ─────────────────────────────────────

  /// Subscribe to a push topic for broadcast notifications
  static Future<bool> subscribeToTopic(String topic) async {
    try {
      await _fcm.subscribeToTopic(topic);
      developer.log('Subscribed to FCM topic: $topic', name: 'FirebaseService');
      return true;
    } catch (e) {
      developer.log('FCM subscribe error: $e', name: 'FirebaseService');
      return false;
    }
  }

  /// Unsubscribe from a push topic
  static Future<bool> unsubscribeFromTopic(String topic) async {
    try {
      await _fcm.unsubscribeFromTopic(topic);
      developer.log('Unsubscribed from FCM topic: $topic', name: 'FirebaseService');
      return true;
    } catch (e) {
      developer.log('FCM unsubscribe error: $e', name: 'FirebaseService');
      return false;
    }
  }

  /// Register the FCM token with the user's Supabase session for targeted pushes.
  /// Call this after user logs in.
  static Future<void> registerUserToken(String userId) async {
    if (_fcmToken == null) return;
    try {
      await _firestore.collection('user_tokens').doc(userId).set({
        'fcm_token': _fcmToken,
        'updated_at': FieldValue.serverTimestamp(),
        'platform': Platform.isAndroid ? 'android' : 'ios',
      }, SetOptions(merge: true));
      developer.log('FCM token registered for user: $userId', name: 'FirebaseService');
    } catch (e) {
      developer.log('FCM token register error: $e', name: 'FirebaseService');
    }
  }

  /// Remove FCM token on logout
  static Future<void> unregisterUserToken(String userId) async {
    try {
      await _firestore.collection('user_tokens').doc(userId).delete();
      developer.log('FCM token removed for user: $userId', name: 'FirebaseService');
    } catch (e) {
      developer.log('FCM token remove error: $e', name: 'FirebaseService');
    }
  }

  // ─── Firestore: User Settings Sync ───────────────────────────────

  /// Save user settings to Firestore for cross-device sync.
  /// Note: API keys are NEVER synced to Firestore — only non-sensitive settings.
  static Future<bool> syncSettingsToFirestore(
    String userId,
    Map<String, dynamic> settings,
  ) async {
    try {
      // Strip any sensitive keys before syncing
      final safeSettings = Map<String, dynamic>.from(settings);
      safeSettings.remove('api_key'); // Never sync API keys
      safeSettings.remove('r2_api_token');

      await _firestore.collection('user_settings').doc(userId).set({
        ...safeSettings,
        'updated_at': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      return true;
    } catch (e) {
      developer.log('Firestore settings sync error: $e', name: 'FirebaseService');
      return false;
    }
  }

  /// Load user settings from Firestore.
  static Future<Map<String, dynamic>?> loadSettingsFromFirestore(
    String userId,
  ) async {
    try {
      final doc = await _firestore.collection('user_settings').doc(userId).get();
      if (doc.exists) {
        return doc.data();
      }
      return null;
    } catch (e) {
      developer.log('Firestore settings load error: $e', name: 'FirebaseService');
      return null;
    }
  }

  /// Listen to real-time settings changes from Firestore.
  /// Returns a Stream that emits settings whenever they change on another device.
  static Stream<Map<String, dynamic>?> listenToSettingsChanges(String userId) {
    return _firestore
        .collection('user_settings')
        .doc(userId)
        .snapshots()
        .map((snapshot) => snapshot.data());
  }

  /// Save a message fragment (for cross-device handoff).
  static Future<bool> saveMessageFragment(
    String userId,
    Map<String, dynamic> message,
  ) async {
    try {
      await _firestore
          .collection('user_messages')
          .doc(userId)
          .collection('fragments')
          .add({
        ...message,
        'created_at': FieldValue.serverTimestamp(),
      });
      return true;
    } catch (e) {
      developer.log('Firestore message save error: $e', name: 'FirebaseService');
      return false;
    }
  }

  // ─── Firebase Storage (Heavy Files) ──────────────────────────────

  /// Upload a file to Firebase Storage.
  /// Returns the download URL on success, null on failure.
  static Future<String?> uploadToStorage({
    required File file,
    required String path,
    Map<String, String>? metadata,
  }) async {
    try {
      final ref = _storage.ref().child(path);
      final uploadTask = ref.putFile(
        file,
        SettableMetadata(
          customMetadata: metadata,
          contentType: _contentType(path),
        ),
      );
      final snapshot = await uploadTask;
      final downloadUrl = await snapshot.ref.getDownloadURL();
      developer.log(
        'Firebase Storage upload: $path -> $downloadUrl',
        name: 'FirebaseService',
      );
      return downloadUrl;
    } catch (e) {
      developer.log('Firebase Storage upload error: $e', name: 'FirebaseService');
      return null;
    }
  }

  /// Upload bytes directly to Firebase Storage.
  static Future<String?> uploadBytesToStorage({
    required List<int> bytes,
    required String path,
    String? contentType,
  }) async {
    try {
      final ref = _storage.ref().child(path);
      final uploadTask = ref.putData(
        bytes,
        SettableMetadata(contentType: contentType ?? 'application/octet-stream'),
      );
      final snapshot = await uploadTask;
      final downloadUrl = await snapshot.ref.getDownloadURL();
      return downloadUrl;
    } catch (e) {
      developer.log('Firebase Storage upload bytes error: $e', name: 'FirebaseService');
      return null;
    }
  }

  /// Delete a file from Firebase Storage.
  static Future<bool> deleteFromStorage(String path) async {
    try {
      await _storage.ref().child(path).delete();
      return true;
    } catch (e) {
      developer.log('Firebase Storage delete error: $e', name: 'FirebaseService');
      return false;
    }
  }

  /// List all files in a storage directory.
  static Future<List<String>> listStorageFiles(String prefix) async {
    try {
      final ref = _storage.ref().child(prefix);
      final result = await ref.listAll();
      final paths = <String>[];
      for (final item in result.items) {
        paths.add(item.fullPath);
      }
      return paths;
    } catch (e) {
      developer.log('Firebase Storage list error: $e', name: 'FirebaseService');
      return [];
    }
  }

  /// Get a download URL for a file path.
  static Future<String?> getStorageUrl(String path) async {
    try {
      return await _storage.ref().child(path).getDownloadURL();
    } catch (e) {
      developer.log('Firebase Storage URL error: $e', name: 'FirebaseService');
      return null;
    }
  }

  // ─── Helpers ─────────────────────────────────────────────────────

  static void _saveTokenLocally(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('fcm_token', token);
  }

  static void _handleForegroundMessage(RemoteMessage message) {
    developer.log(
      'FCM foreground message: ${message.notification?.title} - '
      '${message.notification?.body}',
      name: 'FirebaseService',
    );
    // Can integrate with NotificationService here if needed
  }

  static void _handleNotificationTap(RemoteMessage message) {
    developer.log(
      'FCM notification tapped: ${message.notification?.title}',
      name: 'FirebaseService',
    );
    // Handle deep links from notification data
    final data = message.data;
    if (data['action'] != null) {
      developer.log('FCM action data: ${data['action']}', name: 'FirebaseService');
    }
  }

  static String _contentType(String path) {
    final ext = path.split('.').last.toLowerCase();
    switch (ext) {
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      case 'gif':
        return 'image/gif';
      case 'mp4':
        return 'video/mp4';
      case 'mp3':
        return 'audio/mpeg';
      case 'wav':
        return 'audio/wav';
      case 'pdf':
        return 'application/pdf';
      case 'json':
        return 'application/json';
      default:
        return 'application/octet-stream';
    }
  }
}

/// Background message handler (must be top-level for FCM)
@pragma('vm:entry-point')
Future<void> firebaseBackgroundHandler(RemoteMessage message) async {
  developer.log(
    'FCM background message: ${message.notification?.title}',
    name: 'FirebaseBackground',
  );
}
