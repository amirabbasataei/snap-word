import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wordchain/core/services/analytics_service.dart';
import 'package:wordchain/core/services/analytics_store.dart';

class _MemoryStore implements AnalyticsEventStore {
  final rows = <StoredAnalyticsEvent>[];
  var _nextId = 1;

  @override
  Future<void> add(StoredAnalyticsEvent e) async {
    rows.add(
      StoredAnalyticsEvent(
        id: _nextId++,
        clientEventId: e.clientEventId,
        name: e.name,
        tsMs: e.tsMs,
        sessionId: e.sessionId,
        screen: e.screen,
        props: e.props,
      ),
    );
  }

  @override
  Future<List<StoredAnalyticsEvent>> oldest(int limit) async =>
      rows.take(limit).toList();

  @override
  Future<void> remove(List<int> ids) async =>
      rows.removeWhere((r) => ids.contains(r.id));

  @override
  Future<void> trim(int maxRows) async {
    while (rows.length > maxRows) {
      rows.removeAt(0);
    }
  }

  List<String> get names => [for (final r in rows) r.name];
}

/// Answers every POST with [status] (or fails like an offline phone when null)
/// and records the request bodies.
class _Adapter implements HttpClientAdapter {
  int? status = 200;
  final bodies = <Map<String, dynamic>>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final code = status;
    if (code == null) {
      throw DioException(
        requestOptions: options,
        type: DioExceptionType.connectionError,
      );
    }
    bodies.add(Map<String, dynamic>.from(options.data as Map));
    return ResponseBody.fromString(
      jsonEncode({
        'data': {'accepted': 1, 'rejected': 0},
      }),
      code,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _MemoryStore store;
  late _Adapter adapter;
  late SharedPreferences prefs;
  late AnalyticsService svc;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    store = _MemoryStore();
    adapter = _Adapter();
    svc = AnalyticsService(
      store: store,
      dio: Dio()..httpClientAdapter = adapter,
      prefs: prefs,
      platform: 'android',
      appVersion: '9.9.9',
    );
  });

  test(
    'flush uploads the buffered events and removes them on success',
    () async {
      await svc.track(AnalyticsEvent.appOpen);
      await svc.track(AnalyticsEvent.gameStart, {'mode': 'classic'});
      await svc.flush();

      expect(store.rows, isEmpty);
      final body = adapter.bodies.single;
      expect(body['install_id'], svc.installId);
      expect(body['platform'], 'android');
      expect(body['app_version'], '9.9.9');
      final events = body['events'] as List;
      expect(events.map((e) => e['name']), ['app_open', 'game_start']);
      expect(events[1]['props'], {'mode': 'classic'});
      expect(
        events.map((e) => e['client_event_id']).toSet().length,
        2,
        reason: 'every event needs its own dedup id',
      );
    },
  );

  test(
    'events stay buffered while the upload fails and go out later',
    () async {
      await svc.track(AnalyticsEvent.appOpen);
      adapter.status = null; // offline
      await svc.flush();
      expect(store.names, ['app_open']);

      adapter.status = 503;
      await svc.flush();
      expect(store.names, ['app_open'], reason: 'a server error is retried');

      adapter.status = 200;
      await svc.flush();
      expect(store.rows, isEmpty);
    },
  );

  test(
    'a batch the server rejects as malformed is dropped, not retried forever',
    () async {
      await svc.track(AnalyticsEvent.appOpen);
      adapter.status = 400;
      await svc.flush();
      expect(store.rows, isEmpty);
    },
  );

  test('uploads in batches of at most 100 events', () async {
    for (var i = 0; i < 150; i++) {
      await svc.track(AnalyticsEvent.share);
    }
    await svc.flush();
    expect(adapter.bodies.map((b) => (b['events'] as List).length), [100, 50]);
    expect(store.rows, isEmpty);
  });

  test('the buffer is capped, dropping the oldest events', () async {
    adapter.status = null;
    for (var i = 0; i < AnalyticsService.maxStoredEvents + 20; i++) {
      await svc.track(AnalyticsEvent.share, {'i': i});
    }
    await svc.flush();
    expect(store.rows.length, AnalyticsService.maxStoredEvents);
    expect(jsonDecode(store.rows.first.props!)['i'], 20);
  });

  test('the install id is created once and survives a new service', () async {
    final id = svc.installId;
    expect(RegExp(r'^[0-9a-f-]{36}$').hasMatch(id), isTrue);
    await Future<void>.delayed(Duration.zero);
    final again = AnalyticsService(store: store, dio: Dio(), prefs: prefs);
    expect(again.installId, id);
  });

  test('leaving a screen records a screen_view with the time spent', () async {
    svc.screen('/home');
    await Future<void>.delayed(const Duration(milliseconds: 30));
    svc.screen('/leaderboard');
    await Future<void>.delayed(Duration.zero);

    final view = store.rows.single;
    expect(view.name, 'screen_view');
    expect(view.screen, '/home');
    expect(jsonDecode(view.props!)['duration_ms'], greaterThanOrEqualTo(25));

    svc.screen('/leaderboard'); // same screen again: no new event
    await Future<void>.delayed(Duration.zero);
    expect(store.rows.length, 1);
  });

  test('backgrounding ends the session and stops the screen timer', () async {
    await svc.start();
    addTearDown(svc.dispose);
    svc.screen('/home');
    final firstSession = svc.sessionId;
    await Future<void>.delayed(const Duration(milliseconds: 20));

    svc.didChangeAppLifecycleState(AppLifecycleState.paused);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(
      store.names,
      isNot(contains('screen_view')),
      reason: 'flushed already',
    );
    final sent = adapter.bodies.expand((b) => b['events'] as List).toList();
    expect(
      sent.map((e) => e['name']),
      containsAll(['screen_view', 'session_end']),
    );
    final end = sent.firstWhere((e) => e['name'] == 'session_end');
    expect(end['props']['duration_ms'], greaterThanOrEqualTo(15));
    expect(end['session_id'], firstSession);

    svc.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(svc.sessionId, isNot(firstSession));
    final all = adapter.bodies
        .expand((b) => b['events'] as List)
        .map((e) => e['name']);
    expect(all, contains('session_start'));
  });

  test(
    'time spent in the background is not counted against a screen',
    () async {
      svc.screen('/home');
      svc.didChangeAppLifecycleState(AppLifecycleState.paused);
      await Future<void>.delayed(const Duration(milliseconds: 40));
      svc.screen('/friends'); // navigation while backgrounded
      await Future<void>.delayed(Duration.zero);
      final views = [
        ...store.rows,
        ...adapter.bodies.expand(
          (b) => (b['events'] as List).map(
            (e) => StoredAnalyticsEvent(
              clientEventId: e['client_event_id'] as String,
              name: e['name'] as String,
              tsMs: e['ts'] as int,
              screen: e['screen'] as String?,
              props: e['props'] == null ? null : jsonEncode(e['props']),
            ),
          ),
        ),
      ].where((r) => r.name == 'screen_view' && r.screen == '/home');
      for (final v in views) {
        expect(jsonDecode(v.props!)['duration_ms'], lessThan(35));
      }
    },
  );

  test('newUuid makes RFC 4122 version-4 ids', () {
    final id = newUuid();
    expect(
      RegExp(
        r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
      ).hasMatch(id),
      isTrue,
      reason: id,
    );
  });

  test('screenNameForPath ignores the splash intro', () {
    expect(screenNameForPath('/splash'), isNull);
    expect(screenNameForPath('/home'), '/home');
    expect(screenNameForPath('/daily/board'), '/daily/board');
  });

  test('trackEvent is a harmless no-op when the service is not registered', () {
    trackEvent(AnalyticsEvent.share, {'kind': 'x'});
    flushAnalytics();
  });
}
