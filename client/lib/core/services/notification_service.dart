import 'dart:async';

import 'package:dio/dio.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:logger/logger.dart';
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

  bool _tokenRefreshWired = false;

  NotificationService(this._dio);

  Future<void> init() async {
    try {
      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
      FirebaseMessaging.onMessage.listen(_handleForegroundMessage);
      FirebaseMessaging.onMessageOpenedApp.listen(_handleMessageOpenedApp);

      final initial = await FirebaseMessaging.instance.getInitialMessage();
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

  void _handleForegroundMessage(RemoteMessage message) {
    _log.d('FCM foreground: ${message.notification?.title}');
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
