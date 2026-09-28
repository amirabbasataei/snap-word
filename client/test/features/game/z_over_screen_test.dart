import 'package:flutter_test/flutter_test.dart';
import 'package:wordchain/features/game/bloc/game_bloc.dart';
import 'package:wordchain/features/game/view/z_over_screen.dart';

import '../../helpers/z_test_app.dart';

GameOver _over({
  String reason = 'game_over',
  String? opponentType,
  bool? iWon,
  int score = 120,
  int opponentScore = 150,
  bool canContinue = false,
  int continueTimeRemaining = 0,
  bool isSaved = true,
}) {
  return GameOver(
    localMatchId: -1,
    mode: 'classic',
    reason: reason,
    score: score,
    chainLength: 3,
    wordChain: const ['سیب', 'بازار', 'رود'],
    canContinue: canContinue,
    continueTimeRemaining: continueTimeRemaining,
    isSaved: isSaved,
    winnerId: iWon == null ? null : 'winner',
    iWon: iWon,
    opponentScore: opponentScore,
    opponentType: opponentType,
  );
}

void main() {
  // ZOver's StatsDao lookup is best-effort; with no DI registered it simply
  // leaves the record line at 0, which is fine for these assertions.

  group('ZOver — true multiplayer', () {
    testWidgets('server-declared win shows win title even with lower score', (tester) async {
      await tester.pumpWidget(zTestApp(ZOverScreen(state: _over(iWon: true))));
      expect(find.text('بردی! 🏆'), findsOneWidget);
      expect(find.textContaining('امتیاز حریف', findRichText: true), findsOneWidget);
      expect(find.textContaining('رکورد تو', findRichText: true), findsNothing);
    });

    testWidgets('server-declared loss shows loss title', (tester) async {
      await tester.pumpWidget(zTestApp(ZOverScreen(state: _over(iWon: false, score: 300))));
      expect(find.text('باختی 😞'), findsOneWidget);
    });

    testWidgets('own loss with continue window open offers continue', (tester) async {
      await tester.pumpWidget(zTestApp(ZOverScreen(
        state: _over(
          reason: 'invalid_word',
          canContinue: true,
          continueTimeRemaining: 12,
          isSaved: false,
        ),
      )));
      expect(find.text('زنجیر پاره شد!'), findsOneWidget);
      expect(find.text('ادامه با تماشای ویدیو'), findsOneWidget);
    });
  });

  group('ZOver — solo / vs-AI unchanged', () {
    testWidgets('solo shows record line, no opponent line', (tester) async {
      await tester.pumpWidget(zTestApp(ZOverScreen(
        state: _over(reason: 'invalid_word', opponentType: 'solo', opponentScore: 0),
      )));
      expect(find.text('زنجیر پاره شد!'), findsOneWidget);
      expect(find.textContaining('رکورد تو', findRichText: true), findsOneWidget);
      expect(find.textContaining('امتیاز حریف', findRichText: true), findsNothing);
    });

    testWidgets('vs-AI decides the winner by score', (tester) async {
      await tester.pumpWidget(zTestApp(ZOverScreen(
        state: _over(reason: 'timeout', opponentType: 'ai_easy', score: 200, opponentScore: 100),
      )));
      expect(find.text('بردی! 🏆'), findsOneWidget);
    });
  });
}
