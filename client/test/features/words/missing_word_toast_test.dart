import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:wordchain/core/widgets/z_toast.dart';
import 'package:wordchain/features/auth/cubit/auth_cubit.dart';
import 'package:wordchain/features/words/data/word_suggestions_repository.dart';
import 'package:wordchain/features/words/view/missing_word_toast.dart';

import '../../helpers/game_fakes.dart';
import '../../helpers/z_test_app.dart';

class _FakeWords extends Fake implements WordSuggestionsRepository {
  final suggested = <String>[];
  Object? failWith;

  @override
  Future<bool> suggestWord(String word) async {
    suggested.add(word);
    final e = failWith;
    if (e != null) throw e;
    return false;
  }
}

late BuildContext _ctx;

Widget _app() => zTestApp(
  Builder(
    builder: (context) {
      _ctx = context;
      return const Scaffold(body: SizedBox.expand());
    },
  ),
  reduceMotion: true,
);

void main() {
  late _FakeWords words;

  setUpAll(loadVazirmatn);

  setUp(() {
    words = _FakeWords();
    GetIt.I
      ..registerSingleton<AuthCubit>(
        FakeAuthCubit(
          const AuthAuthenticated(userId: 'u', username: 'Maryam', coins: 0),
        ),
      )
      ..registerSingleton<WordSuggestionsRepository>(words);
  });

  tearDown(GetIt.I.reset);

  testWidgets('asks about the refused word', (tester) async {
    await tester.pumpWidget(_app());
    showMissingWordToast(_ctx, 'قلمم');
    await tester.pump();

    expect(
      find.text('«قلمم» تو لغات ما نبود، می‌خوای گزارش کنی؟'),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('z-toast-action')), findsOneWidget);
    expect(words.suggested, isEmpty);
    await tester.pump(const Duration(seconds: 8));
  });

  testWidgets('the button reports the word and confirms', (tester) async {
    await tester.pumpWidget(_app());
    showMissingWordToast(_ctx, 'قلمم');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('z-toast-action')));
    await tester.pump();
    await tester.pump();

    expect(words.suggested, ['قلمم']);
    expect(find.textContaining('گزارش شد'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('a failed report says why', (tester) async {
    words.failWith = const WordSuggestionException(
      'سقف گزارش امروز پر شده',
      code: 'rate_limited',
    );
    await tester.pumpWidget(_app());
    showMissingWordToast(_ctx, 'قلمم');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('z-toast-action')));
    await tester.pump();
    await tester.pump();

    expect(find.text('سقف گزارش امروز پر شده'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('without a tap the offer just times out', (tester) async {
    await tester.pumpWidget(_app());
    showMissingWordToast(_ctx, 'قلمم');
    await tester.pump();
    await tester.pump(const Duration(seconds: 8));

    expect(find.byType(ZToastCard), findsNothing);
    expect(words.suggested, isEmpty);
  });
}
