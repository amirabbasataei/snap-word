import 'dart:async';

import 'package:dio/dio.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:logger/logger.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wordchain/core/network/api_endpoints.dart';

/// Runs in its own isolate when a push arrives while the app is terminated or
/// backgrounded. The OS shows the notification itself; nothing to do here.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {}

class NotificationService {
  final Dio _dio;
  final Logger _log = Logger();

  final _payloadController = StreamController<String?>.broadcast();

  Stream<String?> get payloadStream => _payloadController.stream;

  final _foregroundController = StreamController<RemoteMessage>.broadcast();

  /// Pushes received while the app is open (the OS does not display these).
  Stream<RemoteMessage> get foregroundStream => _foregroundController.stream;

  static const _lastToastIdKey = 'last_foreground_push_id';
  static const _maxToastAge = Duration(minutes: 2);

  bool _tokenRefreshWired = false;

  NotificationService(this._dio);

  Future<void> init() async {
    try {
      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
      FirebaseMessaging.onMessage.listen(_handleForegroundMessage);
      FirebaseMessaging.onMessageOpenedApp.listen(_handleMessageOpenedApp);

      // Can hang forever without APNs/Firebase config (iOS simulator).
      final initial = await FirebaseMessaging.instance
          .getInitialMessage()
          .timeout(const Duration(seconds: 3));
      if (initial != null) _routeFromMessage(initial);
    } catch (e) {
      _log.w('NotificationService init skipped (Firebase not configured): $e');
    }
  }

  Future<bool> isAuthorized() async {
    try {
      final settings =
          await FirebaseMessaging.instance.getNotificationSettings();
      return settings.authorizationStatus == AuthorizationStatus.authorized;
    } catch (e) {
      _log.w('FCM getNotificationSettings failed: $e');
      return false;
    }
  }

  Future<void> requestPermission() async {
    try {
      await FirebaseMessaging.instance.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
    } catch (e) {
      _log.w('FCM permission request failed: $e');
    }
  }

  Future<String?> getToken() async {
    try {
      return await FirebaseMessaging.instance.getToken();
    } catch (e) {
      _log.w('FCM getToken failed: $e');
      return null;
    }
  }

  /// Registers this device's token with the backend. Call only while signed
  /// in; also re-registers automatically when FCM rotates the token.
  Future<void> registerToken() async {
    final token = await getToken();
    if (token == null) return;
    await _postToken(token);
    if (_tokenRefreshWired) return;
    _tokenRefreshWired = true;
    try {
      FirebaseMessaging.instance.onTokenRefresh.listen(_postToken);
    } catch (e) {
      _log.w('FCM onTokenRefresh unavailable: $e');
    }
  }

  Future<void> _postToken(String token) async {
    try {
      await _dio.post(
        ApiEndpoints.notificationToken,
        data: {'token': token, 'platform': _platform()},
      );
    } catch (e) {
      _log.w('FCM token registration failed: $e');
    }
  }

  Future<void> deregisterToken() async {
    final token = await getToken();
    if (token == null) return;
    try {
      await _dio.delete(ApiEndpoints.notificationToken, data: {'token': token});
    } catch (e) {
      _log.w('FCM token deregistration failed: $e');
    }
  }

  Future<void> _handleForegroundMessage(RemoteMessage message) async {
    _log.d('FCM foreground: ${message.notification?.title}');
    // FCM can hand the same (or a long-queued) push to the app again on a later
    // launch; showing it as a toast each time looks like a repeating bug.
    final sent = message.sentTime;
    if (sent != null && DateTime.now().difference(sent) > _maxToastAge) {
      return;
    }
    final id = message.messageId;
    if (id != null) {
      try {
        final prefs = await SharedPreferences.getInstance();
        if (prefs.getString(_lastToastIdKey) == id) return;
        await prefs.setString(_lastToastIdKey, id);
      } catch (e) {
        _log.w('FCM toast dedupe unavailable: $e');
      }
    }
    _foregroundController.add(message);
  }

  void _handleMessageOpenedApp(RemoteMessage message) {
    _log.d('FCM opened app: ${message.notification?.title}');
    _routeFromMessage(message);
  }

  void _routeFromMessage(RemoteMessage message) {
    final route = message.data['route'] as String?;
    if (route != null) _payloadController.add(route);
  }

  String _platform() =>
      defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android';

  void dispose() {
    _payloadController.close();
    _foregroundController.close();
  }
}
