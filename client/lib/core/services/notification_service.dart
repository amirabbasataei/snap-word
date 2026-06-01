import 'dart:async';

import 'package:dio/dio.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:logger/logger.dart';
import 'package:wordchain/core/network/api_endpoints.dart';

class NotificationService {
  final Dio _dio;
  final Logger _log = Logger();

  final _payloadController = StreamController<String?>.broadcast();

  Stream<String?> get payloadStream => _payloadController.stream;

  NotificationService(this._dio);

  Future<void> init() async {
    try {
      FirebaseMessaging.onMessage.listen(_handleForegroundMessage);
      FirebaseMessaging.onMessageOpenedApp.listen(_handleMessageOpenedApp);

      final initial = await FirebaseMessaging.instance.getInitialMessage();
      if (initial != null) _routeFromMessage(initial);
    } catch (e) {
      _log.w('NotificationService init skipped (Firebase not configured): $e');
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

  Future<void> registerToken() async {
    final token = await getToken();
    if (token == null) return;
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
    _routeFromMessage(message);
  }

  void _handleMessageOpenedApp(RemoteMessage message) {
    _log.d('FCM opened app: ${message.notification?.title}');
    _routeFromMessage(message);
  }

  void _routeFromMessage(RemoteMessage message) {
    final route = message.data['route'] as String?;
    if (route != null) _payloadController.add(route);
  }

  String _platform() {
    // dart:io is available in Flutter; simplified detection
    try {
      // ignore: avoid_dynamic_calls
      return const bool.fromEnvironment('dart.library.io') ? 'android' : 'ios';
    } catch (_) {
      return 'android';
    }
  }

  void dispose() => _payloadController.close();
}
