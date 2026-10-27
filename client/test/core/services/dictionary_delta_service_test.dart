import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wordchain/core/services/ai_opponent.dart';
import 'package:wordchain/core/services/dictionary_delta_service.dart';
import 'package:wordchain/core/services/dictionary_service.dart';

/// Serves queued `GET /dictionary/delta` pages and records the `since` asked.
class _Adapter implements HttpClientAdapter {
  final List<Map<String, dynamic>> pages = [];
  final List<int> asked = [];
  bool offline = false;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (offline) {
      throw DioException(requestOptions: options, message: 'offline');
    }
    asked.add(int.parse('${options.queryParameters['since']}'));
    final page = pages.isEmpty ? _page(seq: asked.last) : pages.removeAt(0);
    return ResponseBody.fromString(
      jsonEncode({'data': page}),
      200,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

Map<String, dynamic> _page({
  required int seq,
  bool more = false,
  bool reset = false,
  List<Map<String, dynamic>> changes = const [],
}) => {'seq': seq, 'more': more, 'reset': reset, 'changes': changes};

Map<String, dynamic> _c(String w, {bool present = true, bool ai = false}) => {
  'word': w,
  'present': present,
  'ai_blocked': ai,
};

void main() {
  late _Adapter adapter;
  late SharedPreferences prefs;
  late DictionaryService dictionary;
  var now = DateTime(2026, 10, 27, 12);

  DictionaryDeltaService make() => DictionaryDeltaService(
    dio: Dio()..httpClientAdapter = adapter,
    prefs: prefs,
    dictionary: dictionary,
    now: () => now,
  );

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    adapter = _Adapter();
    dictionary = DictionaryService.withWords(['کتاب', 'درخت', 'سیب']);
    now = DateTime(2026, 10, 27, 12);
  });

  test('applies additions, removals and AI blocks over the bundled list', () async {
    adapter.pages.add(
      _page(
        seq: 3,
        changes: [
          _c('تازهکلمه'),
          _c('درخت', present: false),
          _c('کتاب', ai: true),
        ],
      ),
    );
    final service = make();
    await service.refresh(force: true);

    expect(dictionary.isValid('تازهکلمه'), isTrue);
    expect(dictionary.isValid('درخت'), isFalse);
    expect(dictionary.isValid('کتاب'), isTrue, reason: 'AI-blocked stays valid');
    expect(dictionary.aiBlocked, {'کتاب'});
    expect(service.seq, 3);
  });

  test('pages through `more` and asks from the last seq', () async {
    adapter.pages
      ..add(_page(seq: 2, more: true, changes: [_c('یکم')]))
      ..add(_page(seq: 5, changes: [_c('دوم')]));
    final service = make();
    await service.refresh(force: true);

    expect(adapter.asked, [0, 2]);
    expect(dictionary.isValid('یکم'), isTrue);
    expect(dictionary.isValid('دوم'), isTrue);
    expect(service.seq, 5);
  });

  test('a later start applies the cached delta before any network', () async {
    adapter.pages.add(_page(seq: 4, changes: [_c('ماندگار'), _c('سیب', present: false)]));
    await make().refresh(force: true);

    // A new run: fresh dictionary, same prefs, no network.
    dictionary = DictionaryService.withWords(['کتاب', 'سیب']);
    adapter.offline = true;
    final service = make()..applyCached();

    expect(dictionary.isValid('ماندگار'), isTrue);
    expect(dictionary.isValid('سیب'), isFalse);
    expect(service.seq, 4);
    await service.refresh(force: true); // offline: must not throw
    expect(service.seq, 4);
  });

  test('a later entry for a word overrides the earlier one', () async {
    adapter.pages
      ..add(_page(seq: 1, changes: [_c('نوسان')]))
      ..add(_page(seq: 2, changes: [_c('نوسان', present: false)]));
    final service = make();
    await service.refresh(force: true);
    await service.refresh(force: true);
    expect(dictionary.isValid('نوسان'), isFalse);

    dictionary = DictionaryService.withWords([]);
    make().applyCached();
    expect(dictionary.isValid('نوسان'), isFalse);
  });

  test('unblocking removes the AI block', () async {
    adapter.pages
      ..add(_page(seq: 1, changes: [_c('کتاب', ai: true)]))
      ..add(_page(seq: 2, changes: [_c('کتاب')]));
    final service = make();
    await service.refresh(force: true);
    expect(dictionary.aiBlocked, contains('کتاب'));
    await service.refresh(force: true);
    expect(dictionary.aiBlocked, isEmpty);
  });

  test('reset drops the cached delta before applying the new one', () async {
    adapter.pages.add(_page(seq: 2, changes: [_c('قدیمی')]));
    final service = make();
    await service.refresh(force: true);

    adapter.pages.add(_page(seq: 1, reset: true, changes: [_c('جدید')]));
    await service.refresh(force: true);

    dictionary = DictionaryService.withWords([]);
    make().applyCached();
    expect(dictionary.isValid('جدید'), isTrue);
    expect(dictionary.isValid('قدیمی'), isFalse);
  });

  test('resume refreshes are throttled; a forced refresh is not', () async {
    final service = make();
    await service.refresh(force: true);
    final calls = adapter.asked.length;

    now = now.add(const Duration(minutes: 2));
    await service.refresh();
    expect(adapter.asked.length, calls);

    now = now.add(DictionaryDeltaService.minRefreshGap);
    await service.refresh();
    expect(adapter.asked.length, calls + 1);
  });

  test('a corrupt cache is ignored', () {
    prefs.setString(DictionaryDeltaService.cacheKey, '{not json');
    final service = make()..applyCached();
    expect(service.seq, 0);
    expect(dictionary.isValid('کتاب'), isTrue);
  });

  test('the AI never picks an AI-blocked word', () {
    final dict = DictionaryService.withWords(['کتاب', 'کبوتر']);
    dict.applyChanges([
      const DictionaryChange(word: 'کتاب', present: true, aiBlocked: true),
    ]);
    const easy = AIDifficultyConfig(
      delayMs: 0,
      mistakeRate: 0,
      minWordLength: 3,
      trapPref: 0,
      preferLongest: false,
    );
    for (var i = 0; i < 20; i++) {
      expect(
        selectAIWord(letter: 'ک', usedWords: {}, dictionary: dict, difficulty: easy),
        'کبوتر',
      );
    }
    expect(dict.isValid('کتاب'), isTrue);
  });
}
