import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wordchain/features/words/cubit/word_report_cubit.dart';
import 'package:wordchain/features/words/data/word_suggestions_repository.dart';

class _FakeRepo extends WordSuggestionsRepository {
  bool already = false;
  WordSuggestionException? fail;
  final sent = <String>[];

  _FakeRepo() : super(dio: Dio(), installId: () => 'i');

  @override
  Future<bool> suggestWord(String word) async {
    sent.add('add:$word');
    if (fail != null) throw fail!;
    return already;
  }

  @override
  Future<bool> flagWord(String word, WordFlagReason reason) async {
    sent.add('remove:$word:${reason.wire}');
    if (fail != null) throw fail!;
    return already;
  }
}

void main() {
  test('suggest goes idle → sending → sent', () async {
    final repo = _FakeRepo();
    final cubit = WordReportCubit(repo, source: 'profile');
    final states = <WordReportStatus>[];
    cubit.stream.listen((s) => states.add(s.status));

    await cubit.suggest('آزمونک');
    await Future<void>.delayed(Duration.zero);

    expect(states, [WordReportStatus.sending, WordReportStatus.sent]);
    expect(repo.sent, ['add:آزمونک']);
    expect(cubit.state.alreadyReported, isFalse);
    await cubit.close();
  });

  test('a repeat report is surfaced', () async {
    final repo = _FakeRepo()..already = true;
    final cubit = WordReportCubit(repo, source: 'game_over');
    await cubit.suggest('آزمونک');
    expect(cubit.state.sent, isTrue);
    expect(cubit.state.alreadyReported, isTrue);
    await cubit.close();
  });

  test('a failure carries the Persian message and can be retried', () async {
    final repo =
        _FakeRepo()
          ..fail = const WordSuggestionException('پیام فارسی', code: 'x');
    final cubit = WordReportCubit(repo, source: 'chain');
    await cubit.flag('بدواژه', WordFlagReason.notAWord);
    expect(cubit.state.status, WordReportStatus.failed);
    expect(cubit.state.message, 'پیام فارسی');
    expect(repo.sent, ['remove:بدواژه:not_a_word']);

    repo.fail = null;
    await cubit.flag('بدواژه', WordFlagReason.notAWord);
    expect(cubit.state.sent, isTrue);
    await cubit.close();
  });

  test('a second tap while sending is ignored', () async {
    final repo = _FakeRepo();
    final cubit = WordReportCubit(repo, source: 'profile');
    final a = cubit.suggest('یکی');
    final b = cubit.suggest('یکی');
    await Future.wait([a, b]);
    expect(repo.sent, ['add:یکی']);
    await cubit.close();
  });
}
