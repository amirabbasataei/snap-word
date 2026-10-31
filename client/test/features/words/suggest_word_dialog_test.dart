import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:wordchain/core/services/dictionary_service.dart';
import 'package:wordchain/core/utils/persian_digits.dart';
import 'package:wordchain/features/auth/cubit/auth_cubit.dart';
import 'package:wordchain/features/game/data/game_constants.dart';
import 'package:wordchain/features/words/data/word_suggestions_repository.dart';
import 'package:wordchain/features/words/view/my_word_reports_dialog.dart';
import 'package:wordchain/features/words/view/suggest_word_dialog.dart';

import '../../helpers/game_fakes.dart';
import '../../helpers/z_test_app.dart';

/// Records suggestions; `mine` returns [reports].
class _FakeWords extends Fake implements WordSuggestionsRepository {
  final suggested = <String>[];
  bool already = false;
  WordSuggestionException? fail;
  List<MyWordReport> reports = const [];

  @override
  Future<bool> suggestWord(String word) async {
    suggested.add(word);
    if (fail != null) throw fail!;
    return already;
  }

  @override
  Future<List<MyWordReport>> mine() async => reports;
}

Future<void> _open(
  WidgetTester t,
  Future<void> Function(BuildContext) opener,
) async {
  t.view.devicePixelRatio = 1;
  t.view.physicalSize = const Size(396, 812);
  addTearDown(t.view.reset);
  await t.pumpWidget(
    zTestApp(
      Builder(
        builder:
            (context) => Center(
              child: TextButton(
                onPressed: () => opener(context),
                child: const Text('open'),
              ),
            ),
      ),
    ),
  );
  await t.tap(find.text('open'));
  await t.pump();
  await t.pump(const Duration(milliseconds: 800));
}

void main() {
  late _FakeWords words;

  setUpAll(loadVazirmatn);
  setUp(() {
    words = _FakeWords();
    GetIt.I.registerSingleton<WordSuggestionsRepository>(words);
    GetIt.I.registerSingleton<DictionaryService>(
      DictionaryService.withWords(['کتاب', 'درخت']),
    );
  });
  tearDown(() => GetIt.I.reset());

  Finder send() => find.text('ارسال');

  void signedIn(bool v) => GetIt.I.registerSingleton<AuthCubit>(
    FakeAuthCubit(
      v
          ? const AuthAuthenticated(userId: 'u', username: 'Maryam', coins: 10)
          : const AuthGuest(),
    ),
  );

  group('SuggestWordDialog', () {
    testWidgets('checks the word locally before it can be sent', (t) async {
      signedIn(true);
      await _open(t, showSuggestWordDialog);
      final field = find.byType(TextField);

      // Nothing typed: send is disabled and no complaint is shown yet.
      expect(find.textContaining('حداقل'), findsNothing);
      await t.tap(send());
      await t.pump();
      expect(words.suggested, isEmpty);

      await t.enterText(field, 'اب');
      await t.pump();
      expect(find.textContaining('حداقل'), findsOneWidget);

      await t.enterText(field, 'abc');
      await t.pump();
      expect(find.text('فقط حرف فارسی، بدون فاصله و عدد'), findsOneWidget);

      await t.enterText(field, 'کتاب');
      await t.pump();
      expect(find.text('این کلمه از قبل در بازی هست'), findsOneWidget);
      await t.tap(send());
      await t.pump();
      expect(words.suggested, isEmpty);
    });

    testWidgets(
      'sends a new word and tells a signed-in player about the reward',
      (t) async {
        signedIn(true);
        await _open(t, showSuggestWordDialog);
        await t.enterText(find.byType(TextField), '  آزمونک ');
        await t.pump();
        await t.tap(send());
        await t.pump();
        await t.pump(const Duration(milliseconds: 600));

        expect(words.suggested, ['آزمونک']);
        expect(find.text('ممنون از کمکت!'), findsOneWidget);
        expect(
          find.textContaining(
            toPersianDigits(GameConstants.wordSuggestionCoins),
          ),
          findsOneWidget,
        );
        expect(find.text('کلمهٔ دیگر'), findsOneWidget);
      },
    );

    testWidgets(
      'a guest can send but is pointed at signing in for the reward',
      (t) async {
        signedIn(false);
        await _open(t, showSuggestWordDialog);
        await t.enterText(find.byType(TextField), 'آزمونک');
        await t.pump();
        await t.tap(send());
        await t.pump();
        await t.pump(const Duration(milliseconds: 600));

        expect(words.suggested, ['آزمونک']);
        expect(find.textContaining('وارد شو'), findsOneWidget);
      },
    );

    testWidgets(
      'a server refusal is shown in Persian and the word can be corrected',
      (t) async {
        signedIn(true);
        words.fail = const WordSuggestionException(
          'این کلمه قبلاً بررسی شده است',
          code: 'word_already_reviewed',
        );
        await _open(t, showSuggestWordDialog);
        await t.enterText(find.byType(TextField), 'آزمونک');
        await t.pump();
        await t.tap(send());
        await t.pump();
        await t.pump(const Duration(milliseconds: 300));
        expect(find.text('این کلمه قبلاً بررسی شده است'), findsOneWidget);

        words.fail = null;
        await t.enterText(find.byType(TextField), 'آزمونکی');
        await t.pump();
        expect(find.text('این کلمه قبلاً بررسی شده است'), findsNothing);
      },
    );
  });

  group('MyWordReportsDialog', () {
    testWidgets('lists each report with what became of it', (t) async {
      signedIn(true);
      words.reports = const [
        MyWordReport(
          word: 'آزمونک',
          kind: 'add',
          status: 'approved',
          rewarded: true,
        ),
        MyWordReport(word: 'نوآموزی', kind: 'add', status: 'pending'),
        MyWordReport(
          word: 'بدواژه',
          kind: 'remove',
          status: 'approved',
          outcome: 'ai_block',
        ),
        MyWordReport(word: 'رد', kind: 'add', status: 'rejected'),
      ];
      await _open(t, showMyWordReportsDialog);
      await t.pump(const Duration(milliseconds: 300));

      expect(find.text('آزمونک'), findsOneWidget);
      expect(find.textContaining('اضافه شد · سکه در جوایز'), findsOneWidget);
      expect(find.textContaining('در انتظار بررسی'), findsOneWidget);
      expect(find.textContaining('برای هوش مصنوعی مسدود شد'), findsOneWidget);
      expect(find.textContaining('رد شد'), findsOneWidget);
    });

    testWidgets('empty state', (t) async {
      signedIn(true);
      await _open(t, showMyWordReportsDialog);
      await t.pump(const Duration(milliseconds: 300));
      expect(find.text('هنوز کلمه‌ای نفرستاده‌ای.'), findsOneWidget);
    });
  });

  test('status labels', () {
    expect(
      wordReportStatusLabel(
        const MyWordReport(
          word: 'a',
          kind: 'remove',
          status: 'approved',
          outcome: 'remove',
        ),
      ),
      'حذف شد',
    );
  });
}
