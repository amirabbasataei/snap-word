import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wordchain/core/utils/error_messages.dart';
import 'package:wordchain/features/words/data/word_suggestions_repository.dart';

class _Adapter implements HttpClientAdapter {
  int status = 200;
  Object body = {'data': {}};
  final bodies = <Map<String, dynamic>>[];
  final paths = <String>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    paths.add('${options.method} ${options.uri.path}');
    if (options.data is Map) bodies.add(Map<String, dynamic>.from(options.data as Map));
    return ResponseBody.fromString(
      jsonEncode(body),
      status,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

Map<String, Object> _err(String code) => {
  'error': {'code': code, 'message': 'english text that must never be shown'},
};

void main() {
  late _Adapter adapter;
  late WordSuggestionsRepository repo;

  setUp(() {
    adapter = _Adapter();
    repo = WordSuggestionsRepository(
      dio: Dio()..httpClientAdapter = adapter,
      installId: () => 'install-1',
    );
  });

  test('suggestWord posts an add with the install id', () async {
    adapter.body = {'data': {'status': 'pending', 'already_reported': false}};
    final already = await repo.suggestWord('آزمونک');
    expect(already, isFalse);
    expect(adapter.paths.single, 'POST /api/v1/words/suggestions');
    expect(adapter.bodies.single, {
      'word': 'آزمونک',
      'kind': 'add',
      'install_id': 'install-1',
    });
  });

  test('a repeat report is flagged', () async {
    adapter.body = {'data': {'status': 'pending', 'already_reported': true}};
    expect(await repo.suggestWord('آزمونک'), isTrue);
  });

  test('flagWord posts a removal with its reason', () async {
    await repo.flagWord('بدواژه', WordFlagReason.inappropriate);
    expect(adapter.bodies.single, {
      'word': 'بدواژه',
      'kind': 'remove',
      'reason': 'inappropriate',
      'install_id': 'install-1',
    });
  });

  test('server errors become Persian messages, never the English text', () async {
    for (final code in [
      'word_in_dictionary',
      'word_already_reviewed',
      'invalid_word',
      'word_unknown',
      'rate_limited',
    ]) {
      adapter
        ..status = 409
        ..body = _err(code);
      try {
        await repo.suggestWord('کلمه');
        fail('should throw');
      } on WordSuggestionException catch (e) {
        expect(e.code, code);
        expect(e.message, errorMessageFor(code));
        expect(e.message, isNot(contains('english')));
      }
    }
  });

  test('mine parses the player\'s reports', () async {
    adapter.body = {
      'data': {
        'items': [
          {
            'word': 'آزمونک',
            'kind': 'add',
            'status': 'approved',
            'rewarded': true,
            'created_at': '2026-10-27T12:00:00Z',
          },
          {'word': 'بدواژه', 'kind': 'remove', 'status': 'pending', 'rewarded': false},
        ],
      },
    };
    final items = await repo.mine();
    expect(items, hasLength(2));
    expect(items.first.isAdd, isTrue);
    expect(items.first.rewarded, isTrue);
    expect(items.first.createdAt, isNotNull);
    expect(items.last.isAdd, isFalse);
    expect(adapter.paths.single, 'GET /api/v1/words/suggestions/mine');
  });
}
