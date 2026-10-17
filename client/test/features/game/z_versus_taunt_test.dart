import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wordchain/features/game/bloc/game_bloc.dart';
import 'package:wordchain/features/game/view/widgets/z_taunt_tray.dart';

import '../../helpers/z_test_app.dart';

GameActive _active() => const GameActive(
  localMatchId: -1,
  mode: 'classic',
  opponentType: 'multiplayer',
  wordChain: ['سیب', 'باران'],
  wordScores: [30],
  score: 30,
  streak: 0,
  turnTimeRemaining: 15,
  guestHintUsesLeft: 0,
  continueUsed: false,
  myPlayerId: 'me',
  opponentId: 'op',
  wordOwners: ['me', 'op'],
  myPremium: true,
  opponentPremium: true,
);

Widget _host(GameActive s) =>
    zTestApp(Scaffold(body: ZVersusChain(state: s, myInitial: 'ت')));

void main() {
  testWidgets('a taunt joins the chain, then leaves it after 3 s', (
    tester,
  ) async {
    final base = _active();
    await tester.pumpWidget(_host(base));
    expect(find.text('زود باش!'), findsNothing);
    await tester.pumpWidget(
      _host(base.copyWith(taunt: 'hurry_up', tauntText: 'زود باش!')),
    );
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('زود باش!'), findsOneWidget);
    await tester.pump(const Duration(seconds: 4));
    expect(find.text('زود باش!'), findsNothing);
  });

  testWidgets(
    'a taunt already in the state when the chain opens stays hidden',
    (tester) async {
      // E.g. coming back from an overlay: the taunt is old news.
      final s = _active().copyWith(taunt: 'hurry_up', tauntText: 'زود باش!');
      await tester.pumpWidget(_host(s));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('زود باش!'), findsNothing);
    },
  );
}
