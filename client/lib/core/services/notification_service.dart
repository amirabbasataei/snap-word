import 'dart:async';

import 'package:dio/dio.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:logger/logger.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wordchain/core/network/api_endpoints.dart';

/// Runs in its own isolate when a push arrives while the app is terminated or
/// backgrounded. The OS shows the notification itself; nothing to do here.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {}

/// `shared_preferences` key of the player's own on/off choice (ZProfile's
/// «اعلان‌ها» switch). Absent = on. Separate from the OS permission, which an
/// app can only ask for, never revoke.
const notificationsEnabledPrefKey = 'notifications_enabled';

class NotificationService with WidgetsBindingObserver {
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

  /// A player is signed in and this device is registered. Gates the resume
  /// re-report, so a signed-out device never posts its token.
  bool _registered = false;

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

  /// The player's in-app choice (default on). When off, this device is not
  /// registered with the server, FCM's token is deleted and foreground pushes
  /// are dropped; in-app messages are unaffected.
  Future<bool> isEnabled() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(notificationsEnabledPrefKey) ?? true;
    } catch (e) {
      _log.w('notification preference unreadable: $e');
      return true;
    }
  }

  /// Stores the choice and returns at once. Turning off then unregisters the
  /// device on the server and deletes the FCM token **in the background** (FCM
  /// can be unreachable for seconds; the stored flag already stops every push
  /// path, so nothing waits for it). Turning on only stores the choice — the
  /// caller registers the token once the OS permission is granted.
  Future<void> setEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(notificationsEnabledPrefKey, enabled);
    if (!enabled) unawaited(_stopPush());
  }

  Future<void> _stopPush() async {
    await deregisterToken();
    try {
      await FirebaseMessaging.instance.deleteToken().timeout(
        const Duration(seconds: 5),
      );
    } catch (e) {
      _log.w('FCM deleteToken failed: $e');
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

  /// What the OS currently lets this app do, in the words the server stores
  /// (`device_tokens.permission`): `granted`, `denied` (refused or switched off
  /// in system settings) or `not_determined` (never asked). The admin panel
  /// reads it to tell who a push can actually reach — a registered token alone
  /// does not mean the player allowed notifications.
  Future<String> permissionState() async {
    try {
      final settings =
          await FirebaseMessaging.instance.getNotificationSettings();
      return switch (settings.authorizationStatus) {
        AuthorizationStatus.authorized ||
        AuthorizationStatus.provisional => 'granted',
        AuthorizationStatus.denied => 'denied',
        AuthorizationStatus.notDetermined => 'not_determined',
      };
    } catch (e) {
      _log.w('FCM getNotificationSettings failed: $e');
      return 'not_determined';
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
    if (!await isEnabled()) return;
    final token = await getToken();
    if (token == null) return;
    if (!_registered) {
      _registered = true;
      WidgetsBinding.instance.addObserver(this);
    }
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
    // FCM can mint a fresh token right after `deleteToken`; it must not
    // re-register a device the player switched off.
    if (!await isEnabled()) return;
    try {
      await _dio.post(
        ApiEndpoints.notificationToken,
        data: {
          'token': token,
          'platform': _platform(),
          'permission': await permissionState(),
        },
      );
    } catch (e) {
      _log.w('FCM token registration failed: $e');
    }
  }

  /// The player may have changed the permission in system settings while the
  /// app was away; tell the server so reach numbers stay true.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _registered) {
      unawaited(registerToken());
    }
  }

  Future<void> deregisterToken() async {
    _registered = false;
    WidgetsBinding.instance.removeObserver(this);
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
    if (!await isEnabled()) return;
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
    WidgetsBinding.instance.removeObserver(this);
    _payloadController.close();
    _foregroundController.close();
  }
}
