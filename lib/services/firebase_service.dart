import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:developer' as developer;
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'chat_history_service.dart';

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

  // ─── Firestore: Cross-Device Message Fragments ───────────────────

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

  // ─── Firestore: Chat Backup (Firebase = backup layer) ───────────

  /// Mirror every chat session to Firestore under `user_chats/<uid>/sessions`.
  /// Called by BackupService so the user's chats exist in Firebase as well as
  /// Supabase, surviving any single cloud outage.
  static Future<bool> backupChatsToFirestore(
    String userId,
    List<ChatSession> sessions,
  ) async {
    try {
      final col = _firestore
          .collection('user_chats')
          .doc(userId)
          .collection('sessions');
      await Future.wait(sessions.map((session) {
        return col.doc(session.id).set(
          {
            'json': jsonEncode(session.toJson()),
            'updated_at': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );
      }));
      return true;
    } catch (e) {
      developer.log('Firestore chat backup error: $e', name: 'FirebaseService');
      return false;
    }
  }

  /// Load the chat sessions mirrored in Firestore for a user.
  static Future<List<ChatSession>> restoreChatsFromFirestore(
    String userId,
  ) async {
    final sessions = <ChatSession>[];
    try {
      final snap = await _firestore
          .collection('user_chats')
          .doc(userId)
          .collection('sessions')
          .get();
      for (final doc in snap.docs) {
        final data = doc.data();
        final json = data['json'];
        if (json is String) {
          try {
            sessions.add(ChatSession.fromJson(jsonDecode(json)));
          } catch (_) {
            // skip malformed session
          }
        }
      }
    } catch (e) {
      developer.log('Firestore chat restore error: $e', name: 'FirebaseService');
    }
    return sessions;
  }

  /// Deletes Firestore mirror sessions last modified before [cutoff].
  /// Returns the number of sessions removed.
  static Future<int> pruneOldChatSessions(
    String userId,
    DateTime cutoff,
  ) async {
    try {
      final col = _firestore
          .collection('user_chats')
          .doc(userId)
          .collection('sessions');
      final snap = await col.get();
      if (snap.docs.isEmpty) return 0;

      final batch = _firestore.batch();
      int pruned = 0;
      for (final doc in snap.docs) {
        final data = doc.data();
        DateTime? ts;
        final json = data['json'];
        if (json is String) {
          try {
            final parsed = jsonDecode(json) as Map<String, dynamic>;
            final raw = parsed['timestamp'];
            if (raw is String) ts = DateTime.tryParse(raw);
          } catch (_) {
            // skip malformed session
          }
        }
        if (ts == null) continue;
        if (!ts.isBefore(cutoff)) continue;
        batch.delete(doc.reference);
        pruned++;
      }
      if (pruned > 0) await batch.commit();
      return pruned;
    } catch (e) {
      developer.log('Firestore chat prune error: $e', name: 'FirebaseService');
      return 0;
    }
  }

  // ─── Firebase Storage (Heavy Files) ──────────────────────────────

  /// Upload bytes directly to Firebase Storage.
  static Future<String?> uploadBytesToStorage({
    required List<int> bytes,
    required String path,
    String? contentType,
  }) async {
    try {
      final ref = _storage.ref().child(path);
      final uploadTask = ref.putData(
        Uint8List.fromList(bytes),
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
}

/// Background message handler (must be top-level for FCM)
@pragma('vm:entry-point')
Future<void> firebaseBackgroundHandler(RemoteMessage message) async {
  developer.log(
    'FCM background message: ${message.notification?.title}',
    name: 'FirebaseBackground',
  );
}
