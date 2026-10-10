import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wordchain/core/services/perks_catalog_service.dart';

class _Adapter implements HttpClientAdapter {
  Map<String, dynamic>? body;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final b = body;
    if (b == null) {
      throw DioException(requestOptions: options, message: 'offline');
    }
    return ResponseBody.fromString(
      jsonEncode({'data': b}),
      200,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

const _payload = {
  'taunts': [
    {'id': 'hurry_up', 'text': 'زود باش!'},
    {'id': 'blank', 'text': ''},
  ],
  'avatars': [
    {'id': 'lion'},
    {'id': 'fox'},
  ],
};

void main() {
  late _Adapter adapter;
  late SharedPreferences prefs;

  PerksCatalogService make() {
    final dio = Dio()..httpClientAdapter = adapter;
    return PerksCatalogService(dio: dio, prefs: prefs);
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    adapter = _Adapter();
  });

  test('parses the server catalogue in order and skips blank entries', () {
    final c = PerksCatalog.fromJson(_payload);
    expect(c.taunts.map((t) => t.id), ['hurry_up']);
    expect(c.taunts.single.text, 'زود باش!');
    expect(c.avatarIds, ['lion', 'fox']);
  });

  test(
    'refresh returns the server list and caches it for next launch',
    () async {
      adapter.body = _payload;
      final fresh = await make().refresh();
      expect(fresh.avatarIds, ['lion', 'fox']);

      // A new service instance (app restart) sees the cache without network.
      adapter.body = null;
      final restarted = make();
      expect(restarted.cached.avatarIds, ['lion', 'fox']);
      expect((await restarted.refresh()).avatarIds, ['lion', 'fox']);
    },
  );

  test('offline with nothing cached yields an empty catalogue', () async {
    final service = make();
    expect(service.cached.isEmpty, isTrue);
    expect((await service.refresh()).isEmpty, isTrue);
  });

  test('a corrupt cache is treated as empty', () async {
    await prefs.setString('perks_catalog_v1', '{not json');
    expect(make().cached.isEmpty, isTrue);
  });

  test('a removed avatar disappears on the next successful refresh', () async {
    adapter.body = _payload;
    final service = make();
    await service.refresh();
    adapter.body = {
      'taunts': _payload['taunts'],
      'avatars': [
        {'id': 'lion'},
      ],
    };
    expect((await service.refresh()).avatarIds, ['lion']);
  });
}
