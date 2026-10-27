import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';
import 'package:logger/logger.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wordchain/core/di/injection.dart';
import 'package:wordchain/core/network/api_endpoints.dart';
import 'package:wordchain/core/services/app_version.dart';
import 'package:wordchain/core/services/analytics_store.dart';

/// The fixed event vocabulary. Mirrors `service.AnalyticsEventNames` on the
/// server, which drops any name it does not know — add both sides together.
/// Props must stay small and free of PII: no phone, no free text, no words.
enum AnalyticsEvent {
  appOpen('app_open'),
  sessionStart('session_start'),
  sessionEnd('session_end'),
  screenView('screen_view'),
  signup('signup'),
  login('login'),
  identify('identify'),
  gameStart('game_start'),
  gameEnd('game_end'),
  continueUsed('continue_used'),
  powerupUsed('powerup_used'),
  dailyStart('daily_start'),
  dailyEnd('daily_end'),
  queueJoin('queue_join'),
  queueLeave('queue_leave'),
  matchFound('match_found'),
  adWatched('ad_watched'),
  purchaseTap('purchase_tap'),
  share('share'),
  friendRequest('friend_request'),
  challengeSent('challenge_sent'),
  wordSuggest('word_suggest');

  final String wire;
  const AnalyticsEvent(this.wire);
}

/// Fire-and-forget tracking from anywhere (blocs, cubits, repositories). A
/// no-op until [AnalyticsService] is registered, so unit tests that build a
/// bloc or cubit need no setup.
void trackEvent(AnalyticsEvent event, [Map<String, Object?> props = const {}]) {
  if (!getIt.isRegistered<AnalyticsService>()) return;
  unawaited(getIt<AnalyticsService>().track(event, props));
}

/// Uploads buffered events now (e.g. after a game ends or a login).
void flushAnalytics() {
  if (!getIt.isRegistered<AnalyticsService>()) return;
  unawaited(getIt<AnalyticsService>().flush());
}

String newUuid([Random? random]) {
  final r = random ?? Random.secure();
  final b = List<int>.generate(16, (_) => r.nextInt(256));
  b[6] = (b[6] & 0x0f) | 0x40; // version 4
  b[8] = (b[8] & 0x3f) | 0x80; // RFC 4122 variant
  String hex(int from, int to) =>
      b
          .sublist(from, to)
          .map((x) => x.toRadixString(16).padLeft(2, '0'))
          .join();
  return '${hex(0, 4)}-${hex(4, 6)}-${hex(6, 8)}-${hex(8, 10)}-${hex(10, 16)}';
}

/// Product analytics: events go into a local buffer and are uploaded in
/// batches, never straight to the network — so tracking works offline, survives
/// an app kill, and costs nothing during a solo/AI game (which must not call
/// the backend).
///
/// Identity is an `install_id` kept in `shared_preferences`; the server links
/// it to the account from the JWT on the upload request, so guests are tracked
/// too and a guest's pre-signup history joins up with the account on login.
///
/// A *session* is one foreground stint: it starts at launch / resume and ends
/// (with its duration) when the app is backgrounded.
class AnalyticsService with WidgetsBindingObserver {
  AnalyticsService({
    required AnalyticsEventStore store,
    required Dio dio,
    required SharedPreferences prefs,
    String? platform,
    String? appVersion,
    DateTime Function()? clock,
    Duration flushInterval = const Duration(seconds: 60),
  }) : _store = store,
       _dio = dio,
       _prefs = prefs,
       _platform = platform ?? _detectPlatform(),
       _appVersion = appVersion,
       _clock = clock ?? DateTime.now,
       _flushInterval = flushInterval;

  /// Used only if the platform version cannot be read.
  static const fallbackVersion = 'unknown';
  static const installIdKey = 'analytics_install_id';
  static const maxStoredEvents = 5000;
  static const batchSize = 100;
  static const _maxBatchesPerFlush = 5;

  /// The screen name during which periodic flushing pauses (the live game).
  static const gameScreen = '/game';

  final AnalyticsEventStore _store;
  final Dio _dio;
  final SharedPreferences _prefs;
  final String _platform;
  String? _appVersion; // resolved from the platform in start() unless injected
  final DateTime Function() _clock;
  final Duration _flushInterval;
  final Logger _log = Logger();

  late final String installId = _loadInstallId();
  String _sessionId = newUuid();
  final Stopwatch _sessionWatch = Stopwatch();
  final Stopwatch _screenWatch = Stopwatch();
  String? _screen;
  Timer? _timer;
  bool _foreground = true;
  bool _flushing = false;
  bool _started = false;

  String get sessionId => _sessionId;
  String? get currentScreen => _screen;

  static String _detectPlatform() {
    try {
      if (Platform.isAndroid) return 'android';
      if (Platform.isIOS) return 'ios';
    } catch (_) {}
    return 'other';
  }

  String _loadInstallId() {
    try {
      final saved = _prefs.getString(installIdKey);
      if (saved != null && saved.isNotEmpty) return saved;
      final fresh = newUuid();
      unawaited(_prefs.setString(installIdKey, fresh));
      return fresh;
    } catch (_) {
      return newUuid();
    }
  }

  /// Call once, after DI is ready. Records `app_open`, begins the first
  /// session and starts the periodic upload.
  Future<void> start() async {
    if (_started) return;
    _started = true;
    _appVersion ??= await AppVersion.load() ?? fallbackVersion;
    WidgetsBinding.instance.addObserver(this);
    await track(AnalyticsEvent.appOpen);
    await _beginSession();
    _startTimer();
    unawaited(flush());
  }

  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _timer = null;
  }

  /// Buffers one event. Never throws — analytics must not break the app.
  Future<void> track(
    AnalyticsEvent event, [
    Map<String, Object?> props = const {},
  ]) => _record(event.wire, props: props, screen: _screen);

  Future<void> _record(
    String name, {
    Map<String, Object?> props = const {},
    String? screen,
  }) async {
    try {
      await _store.add(
        StoredAnalyticsEvent(
          clientEventId: newUuid(),
          name: name,
          tsMs: _clock().millisecondsSinceEpoch,
          sessionId: _sessionId,
          screen: screen,
          props: props.isEmpty ? null : jsonEncode(props),
        ),
      );
    } catch (e) {
      _log.w('analytics: could not buffer $name: $e');
    }
  }

  /// Marks the screen the player is now on (a route path such as `/home`).
  /// Closing the previous screen records its `screen_view` with the time spent
  /// in the foreground. Pass null for chrome that is not a screen.
  void screen(String? name) {
    if (name == _screen) return;
    _closeScreen();
    _screen = name;
    _screenWatch.reset();
    if (name != null && _foreground) _screenWatch.start();
  }

  void _closeScreen() {
    final current = _screen;
    if (current == null) return;
    _screenWatch.stop();
    final ms = _screenWatch.elapsedMilliseconds;
    _screenWatch.reset();
    // A view with no foreground time (flicked past, or the app was already in
    // the background) says nothing about engagement.
    if (ms <= 0) return;
    unawaited(
      _record(
        AnalyticsEvent.screenView.wire,
        props: {'duration_ms': ms},
        screen: current,
      ),
    );
  }

  Future<void> _beginSession() async {
    _sessionId = newUuid();
    _sessionWatch
      ..reset()
      ..start();
    if (_screen != null) _screenWatch.start();
    await track(AnalyticsEvent.sessionStart);
  }

  Future<void> _endSession() async {
    _closeScreen();
    final ms = _sessionWatch.elapsedMilliseconds;
    _sessionWatch
      ..stop()
      ..reset();
    await _record(AnalyticsEvent.sessionEnd.wire, props: {'duration_ms': ms});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused && _foreground) {
      _foreground = false;
      _timer?.cancel();
      _timer = null;
      unawaited(_endSession().then((_) => flush()));
    } else if (state == AppLifecycleState.resumed && !_foreground) {
      _foreground = true;
      unawaited(_beginSession().then((_) => flush()));
      _startTimer();
    }
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(_flushInterval, (_) {
      // The backend is never called mid-game; the end of the game flushes.
      if (_screen == gameScreen) return;
      unawaited(flush());
    });
  }

  /// Uploads buffered events in batches of [batchSize]. Rows are deleted only
  /// after the server acknowledges them, so a failure keeps them for the next
  /// attempt (the server dedupes retries by `client_event_id`).
  Future<void> flush() async {
    if (_flushing) return;
    _flushing = true;
    try {
      for (var i = 0; i < _maxBatchesPerFlush; i++) {
        final rows = await _store.oldest(batchSize);
        if (rows.isEmpty) break;
        if (!await _send(rows)) break;
        await _store.remove([for (final r in rows) r.id]);
        if (rows.length < batchSize) break;
      }
      await _store.trim(maxStoredEvents);
    } catch (e) {
      _log.w('analytics: flush failed: $e');
    } finally {
      _flushing = false;
    }
  }

  /// True when the batch can be dropped from the buffer.
  Future<bool> _send(List<StoredAnalyticsEvent> rows) async {
    try {
      await _dio.post(
        ApiEndpoints.analyticsEvents,
        data: {
          'install_id': installId,
          'platform': _platform,
          'app_version': _appVersion ?? fallbackVersion,
          'events': [
            for (final r in rows)
              {
                'client_event_id': r.clientEventId,
                'name': r.name,
                'ts': r.tsMs,
                if (r.sessionId != null) 'session_id': r.sessionId,
                if (r.screen != null) 'screen': r.screen,
                if (r.props != null) 'props': jsonDecode(r.props!),
              },
          ],
        },
      );
      return true;
    } on DioException catch (e) {
      // 400 means the batch itself is malformed; retrying it would block the
      // queue forever. Everything else (offline, 429, 5xx) is retried later.
      if (e.response?.statusCode == 400) {
        _log.w('analytics: dropping a batch the server rejected');
        return true;
      }
      return false;
    }
  }
}

/// Feeds [AnalyticsService.screen] from the router's location. Listening to
/// the router delegate (rather than a NavigatorObserver) also covers the
/// bottom-nav tabs — a tab switch changes the location but pushes no route —
/// and `go()` replacing the whole stack.
class RouterScreenTracker {
  RouterScreenTracker(this._router, this._analytics) {
    _router.routerDelegate.addListener(_onChange);
    _onChange();
  }

  final GoRouter _router;
  final AnalyticsService _analytics;

  void _onChange() {
    final path = _router.routerDelegate.currentConfiguration.uri.path;
    _analytics.screen(screenNameForPath(path));
  }

  void dispose() => _router.routerDelegate.removeListener(_onChange);
}

/// The screen name recorded for a route path; null for the splash intro.
String? screenNameForPath(String path) {
  if (path.isEmpty || path == '/splash') return null;
  return path;
}
