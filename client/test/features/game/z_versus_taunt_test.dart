import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wordchain/features/game/bloc/game_bloc.dart';
import 'package:wordchain/features/game/view/z_versus_screen.dart';

import '../../helpers/z_test_app.dart';

GameActive _active() => const GameActive(
  localMatchId: -1,
  mode: 'classic',
  opponentType: 'multiplayer',
  wordChain: [],
  wordScores: [],
  score: 0,
  streak: 0,
  turnTimeRemaining: 15,
  guestHintUsesLeft: 0,
  continueUsed: false,
  myPlayerId: 'me',
  opponentId: 'op',
  myPremium: true,
  opponentPremium: true,
);

Widget _host(GameActive s) => zTestApp(
  Scaffold(body: Stack(children: [TauntBubble(state: s)])),
);

void main() {
  testWidgets('a taunt shows as a bubble then hides after 3 s', (tester) async {
    final base = _active();
    await tester.pumpWidget(_host(base));
    await tester.pumpWidget(
      _host(base.copyWith(taunt: 'hurry_up', tauntFromMe: false)),
    );
    await tester.pump(const Duration(milliseconds: 300));
    final opacity = find.byType(AnimatedOpacity);
    expect(tester.widget<AnimatedOpacity>(opacity).opacity, 1);
    expect(find.text('زود باش!'), findsOneWidget);
    await tester.pump(const Duration(seconds: 4));
    expect(tester.widget<AnimatedOpacity>(opacity).opacity, 0);
  });
}
