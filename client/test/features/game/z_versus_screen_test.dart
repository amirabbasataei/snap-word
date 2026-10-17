import 'package:flutter/rendering.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:wordchain/core/services/perks_catalog_service.dart';
import 'package:wordchain/core/theme/app_scene_tokens.dart';
import 'package:wordchain/core/theme/app_tokens.dart';
import 'package:wordchain/core/widgets/chunky_pressable.dart';
import 'package:wordchain/core/widgets/z_disc_avatar.dart';
import 'package:wordchain/core/widgets/z_mascot.dart';
import 'package:wordchain/features/auth/cubit/auth_cubit.dart';
import 'package:wordchain/features/game/bloc/game_bloc.dart';
import 'package:wordchain/features/game/data/game_constants.dart';
import 'package:wordchain/features/game/view/widgets/z_game_bubbles.dart';
import 'package:wordchain/features/game/view/widgets/z_taunt_tray.dart';
import 'package:wordchain/features/game/view/z_versus_screen.dart';

import '../../helpers/contrast.dart';
import '../../helpers/game_fakes.dart';
import '../../helpers/z_test_app.dart';

const _me = 'me-id';
const _them = 'them-id';

/// A shared chain: I open, the opponent answers, alternating.
const _chain = ['سیب', 'باران', 'نمک', 'کتاب', 'برف', 'فرش', 'شیر', 'رنگ'];

GameActive _state({
  int words = 0,
  List<int> scores = const [],
  String? next,
  int score = 0,
  int opponentScore = 0,
  int time = 15,
  bool myTurn = true,
  bool myPremium = false,
  bool opponentPremium = false,
  String? myAvatarId,
  String? opponentName,
  bool continueWindow = false,
  String? taunt,
  String? tauntText,
  bool tauntFromMe = false,
  Map<String, int> counts = const {},
}) {
  final chain = _chain.take(words).toList();
  return GameActive(
    localMatchId: -1,
    mode: 'classic',
    opponentType: 'multiplayer',
    wordChain: chain,
    wordScores: scores,
    score: score,
    streak: 0,
    turnTimeRemaining: time,
    nextStartLetter: next,
    guestHintUsesLeft: 999,
    continueUsed: false,
    isMyTurn: myTurn,
    myPlayerId: _me,
    opponentId: _them,
    opponentUsername: opponentName,
    opponentScore: opponentScore,
    wordOwners: [for (var i = 0; i < chain.length; i++) i.isEven ? _me : _them],
    powerupCounts: counts,
    opponentContinueWindowActive: continueWindow,
    myPremium: myPremium,
    opponentPremium: opponentPremium,
    myAvatarId: myAvatarId,
    tauntId: taunt,
    tauntText: tauntText,
    tauntFromMe: tauntFromMe,
    tauntSeq: taunt == null ? 0 : 1,
  );
}

class _FakePerks extends Fake implements PerksCatalogService {
  PerksCatalog list;
  final Future<PerksCatalog>? pending;

  _FakePerks(this.list, {this.pending});

  @override
  PerksCatalog get cached => list;

  @override
  Future<PerksCatalog> refresh() async => pending ?? list;
}

const _taunts = PerksCatalog(
  taunts: [
    PerkTaunt(id: 'a', text: 'همین بود؟'),
    PerkTaunt(id: 'b', text: 'کم آوردی؟'),
    PerkTaunt(id: 'c', text: 'ساعت داره می‌دوه…'),
  ],
);

class _FeeBloc extends FakeGameBloc {
  final int fee;
  _FeeBloc(this.fee);

  @override
  int get entryFee => fee;
}

Widget _screen(
  GameActive s, {
  Brightness brightness = Brightness.light,
  bool reduceMotion = false,
  GameBloc? bloc,
  double textScale = 1,
}) => BlocProvider<GameBloc>.value(
  value: bloc ?? _FeeBloc(20),
  child: zTestApp(
    Builder(
      builder:
          (context) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              disableAnimations: reduceMotion,
              textScaler: TextScaler.linear(textScale),
            ),
            child: ZVersusActiveScreen(state: s),
          ),
    ),
    brightness: brightness,
  ),
);

Future<void> _size(WidgetTester tester, double w, double h) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(w, h);
  addTearDown(tester.view.reset);
}

Future<void> _settle(WidgetTester tester) =>
    tester.pump(const Duration(milliseconds: 700));

void main() {
  setUpAll(loadVazirmatn);

  setUp(() {
    GetIt.I.registerSingleton<AuthCubit>(
      FakeAuthCubit(
        const AuthAuthenticated(userId: _me, username: 'Amir', coins: 120),
      ),
    );
    GetIt.I.registerSingleton<PerksCatalogService>(_FakePerks(_taunts));
  });
  tearDown(() => GetIt.I.reset());

  group('states', () {
    testWidgets('empty chain, my turn: pill, fee chip, cue slot, power-ups', (
      tester,
    ) async {
      await _size(tester, 430, 932);
      await tester.pumpWidget(_screen(_state()));
      await _settle(tester);
      expect(find.text('شروع زنجیر'), findsOneWidget);
      expect(find.text('اولین کلمه رو بنویس'), findsOneWidget);
      expect(find.text('نوبت تو'), findsOneWidget);
      // Opponent name falls back to «حریف» (the WS state has no username).
      expect(find.text('حریف'), findsOneWidget);
      expect(find.text('ورودی ۲۰ سکه'), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
      for (final label in ['راهنما', 'انجماد حریف', 'وقت بیشتر', 'سپر']) {
        expect(find.text(label), findsOneWidget, reason: label);
      }
      // Signed-in initial on my disc, «ح» on the opponent's.
      expect(find.widgetWithText(ZDiscAvatar, 'A'), findsOneWidget);
      expect(find.widgetWithText(ZDiscAvatar, 'ح'), findsOneWidget);
    });

    testWidgets('mid-game: bubbles, my points only, both scores, ring', (
      tester,
    ) async {
      await _size(tester, 393, 852);
      await tester.pumpWidget(
        _screen(
          _state(
            words: 5,
            scores: [30, 40, 50],
            next: 'ف',
            score: 120,
            opponentScore: 80,
            time: 9,
          ),
        ),
      );
      await _settle(tester);
      for (final w in _chain.take(5)) {
        expect(find.bySemanticsLabel(w), findsOneWidget, reason: w);
      }
      expect(find.text('+۳۰'), findsOneWidget);
      expect(find.text('+۴۰'), findsOneWidget);
      expect(find.text('+۵۰'), findsOneWidget);
      expect(find.text('۱۲۰'), findsOneWidget);
      expect(find.text('۸۰'), findsOneWidget);
      expect(find.text('۰۹'), findsOneWidget);
      expect(find.text('حالا با «ف»'), findsOneWidget);
    });

    testWidgets('me on the start side, the opponent on the end side', (
      tester,
    ) async {
      await _size(tester, 393, 852);
      await tester.pumpWidget(_screen(_state(words: 2, next: 'ن')));
      await _settle(tester);
      final mine = tester.getCenter(find.bySemanticsLabel('سیب'));
      final theirs = tester.getCenter(find.bySemanticsLabel('باران'));
      // RTL: start = right.
      expect(mine.dx, greaterThan(theirs.dx));
      // The dashed slot is on the side of whoever moves: the opponent here.
      await tester.pumpWidget(
        _screen(_state(words: 2, next: 'ن', myTurn: false)),
      );
      await _settle(tester);
      final slot = tester.getCenter(find.text('حالا با «ن»'));
      expect(slot.dx, lessThan(tester.view.physicalSize.width / 2));
    });

    testWidgets('no fee chip when nothing was charged', (tester) async {
      await _size(tester, 393, 852);
      await tester.pumpWidget(_screen(_state(), bloc: _FeeBloc(0)));
      await _settle(tester);
      expect(find.textContaining('ورودی'), findsNothing);
    });

    testWidgets('opponent turn: chip, thinking card with mascot, no field', (
      tester,
    ) async {
      await _size(tester, 393, 852);
      await tester.pumpWidget(
        _screen(_state(words: 3, next: 'ک', myTurn: false)),
      );
      await _settle(tester);
      expect(find.text('نوبت حریف'), findsOneWidget);
      expect(find.text('نوبت تو'), findsNothing);
      expect(find.byType(TextField), findsNothing);
      expect(find.text('حریف در حال فکر کردن…'), findsOneWidget);
      expect(find.byType(ZMascot), findsOneWidget);
    });

    testWidgets('a named opponent shows in the pill, chip and thinking card', (
      tester,
    ) async {
      await _size(tester, 393, 852);
      await tester.pumpWidget(
        _screen(_state(words: 1, myTurn: false, opponentName: 'مریم')),
      );
      await _settle(tester);
      expect(find.text('مریم'), findsOneWidget);
      expect(find.text('نوبت مریم'), findsOneWidget);
      expect(find.text('مریم در حال فکر کردن…'), findsOneWidget);
      expect(find.widgetWithText(ZDiscAvatar, 'م'), findsWidgets);
    });

    testWidgets('premium crowns appear next to the premium players only', (
      tester,
    ) async {
      await _size(tester, 393, 852);
      Finder crowns() => find.bySemanticsLabel('اشتراک ویژه');
      await tester.pumpWidget(_screen(_state()));
      await _settle(tester);
      expect(crowns(), findsNothing);
      await tester.pumpWidget(_screen(_state(opponentPremium: true)));
      await _settle(tester);
      expect(crowns(), findsOneWidget);
      await tester.pumpWidget(
        _screen(_state(myPremium: true, opponentPremium: true)),
      );
      await _settle(tester);
      expect(crowns(), findsNWidgets(2));
    });

    testWidgets('omits what nothing backs: lives, rounds, typing, long tag', (
      tester,
    ) async {
      await _size(tester, 393, 852);
      await tester.pumpWidget(_screen(_state(words: 3, myTurn: false)));
      await _settle(tester);
      expect(find.textContaining('جان'), findsNothing);
      expect(find.textContaining('دست '), findsNothing);
      expect(find.textContaining('می‌نویسد'), findsNothing);
      expect(find.textContaining('دوبرابر'), findsNothing);
      expect(find.textContaining('۷ حرف'), findsNothing);
    });

    testWidgets('typing and sending a word dispatches WordSubmitted', (
      tester,
    ) async {
      await _size(tester, 393, 852);
      final bloc = _FeeBloc(20);
      await tester.pumpWidget(_screen(_state(next: 'س'), bloc: bloc));
      await _settle(tester);
      await tester.enterText(find.byType(TextField), 'سیب');
      await tester.tap(find.bySemanticsLabel('بفرست'));
      await tester.pump();
      expect((bloc.events.single as WordSubmitted).word, 'سیب');
    });

    testWidgets('the input is locked while the opponent is deciding', (
      tester,
    ) async {
      await _size(tester, 393, 852);
      await tester.pumpWidget(_screen(_state(next: 'س', continueWindow: true)));
      await _settle(tester);
      expect(tester.widget<TextField>(find.byType(TextField)).enabled, isFalse);
    });

    testWidgets('freeze is offered (a duel has an opponent to freeze)', (
      tester,
    ) async {
      await _size(tester, 393, 852);
      final bloc = _FeeBloc(20);
      await tester.pumpWidget(
        _screen(_state(counts: const {'freeze': 1}), bloc: bloc),
      );
      await _settle(tester);
      await tester.tap(find.bySemanticsLabel(RegExp('^انجماد حریف')));
      await tester.pump();
      expect((bloc.events.single as PowerupRequested).type, 'freeze');
    });

    testWidgets('back button asks before ending the game', (tester) async {
      await _size(tester, 393, 852);
      final bloc = ScriptedGameBloc(_state(words: 2), entryFee: 20);
      await tester.pumpWidget(_screen(_state(words: 2), bloc: bloc));
      await _settle(tester);
      await tester.tap(find.bySemanticsLabel('بازگشت'));
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.text('تسلیم می‌شی؟'), findsOneWidget);
      // Nothing is sent just by asking.
      expect(bloc.events, isEmpty);
    });
  });

  group('taunts', () {
    Future<void> openTray(WidgetTester tester) async {
      await tester.tap(find.bySemanticsLabel(RegExp('^طعنه')));
      await tester.pump(const Duration(milliseconds: 700));
    }

    testWidgets('premium: tray lists taunts, real rule line, sends the id', (
      tester,
    ) async {
      await _size(tester, 393, 852);
      final bloc = _FeeBloc(20);
      await tester.pumpWidget(_screen(_state(myPremium: true), bloc: bloc));
      await _settle(tester);
      await openTray(tester);
      expect(find.text('طعنه بفرست'), findsOneWidget);
      expect(
        find.text('هر ۵ ثانیه یک طعنه · تا ۸ طعنه در هر بازی'),
        findsOneWidget,
      );
      // The canvas's per-round claim is not shown.
      expect(find.textContaining('در هر دست'), findsNothing);
      expect(find.text('همین بود؟'), findsOneWidget);
      await tester.tap(find.text('کم آوردی؟'));
      await tester.pump(const Duration(milliseconds: 700));
      expect((bloc.events.single as TauntSent).tauntId, 'b');
      // The tray closed itself.
      expect(find.text('طعنه بفرست'), findsNothing);
    });

    testWidgets('the rule line follows the constants', (tester) async {
      expect(GameConstants.tauntCooldownSec, 5);
      expect(GameConstants.tauntMaxPerMatch, 8);
    });

    testWidgets('free player: taunts are locked, nothing is sent', (
      tester,
    ) async {
      await _size(tester, 393, 852);
      final bloc = _FeeBloc(20);
      await tester.pumpWidget(_screen(_state(), bloc: bloc));
      await _settle(tester);
      await openTray(tester);
      expect(find.textContaining('فقط برای اشتراک ویژه'), findsOneWidget);
      await tester.tap(find.text('همین بود؟'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(bloc.events, isEmpty);
      expect(find.text('طعنه بفرست'), findsOneWidget);
      await tester.tap(
        find.descendant(
          of: find.byType(ZTauntTray),
          matching: find.byType(ChunkyPressable),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1000));
      expect(find.text('طعنه بفرست'), findsNothing);
    });

    testWidgets('first fetch shows a skeleton, then the list', (tester) async {
      await _size(tester, 393, 852);
      final gate = Future<PerksCatalog>.delayed(
        const Duration(seconds: 1),
        () => _taunts,
      );
      GetIt.I.unregister<PerksCatalogService>();
      GetIt.I.registerSingleton<PerksCatalogService>(
        _FakePerks(PerksCatalog.empty, pending: gate),
      );
      await tester.pumpWidget(_screen(_state(myPremium: true)));
      await _settle(tester);
      await openTray(tester);
      expect(find.text('همین بود؟'), findsNothing);
      expect(find.text('طعنه‌ای در دسترس نیست'), findsNothing);
      await tester.pump(const Duration(seconds: 2));
      expect(find.text('همین بود؟'), findsOneWidget);
    });

    testWidgets('an empty catalogue says so', (tester) async {
      await _size(tester, 393, 852);
      GetIt.I.unregister<PerksCatalogService>();
      GetIt.I.registerSingleton<PerksCatalogService>(
        _FakePerks(PerksCatalog.empty),
      );
      await tester.pumpWidget(_screen(_state(myPremium: true)));
      await _settle(tester);
      await openTray(tester);
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('طعنه‌ای در دسترس نیست'), findsOneWidget);
    });

    /// Pumps [before] then [after], so the taunt arrives as a state change
    /// (the bubble is driven by `tauntSeq` bumping, as in a live match).
    Future<void> arrive(
      WidgetTester tester,
      GameActive before,
      GameActive after,
    ) async {
      await tester.pumpWidget(_screen(before));
      await _settle(tester);
      await tester.pumpWidget(_screen(after));
      await tester.pump(const Duration(milliseconds: 300));
    }

    double top(WidgetTester tester, String text) =>
        tester.getTopLeft(find.text(text)).dy;

    testWidgets('theirs sits in the chain under their last word, end side', (
      tester,
    ) async {
      await _size(tester, 393, 852);
      // me: سیب, them: باران, me: نمک → their last word is the middle one.
      await arrive(
        tester,
        _state(words: 3, scores: [30, 40], next: 'ک'),
        _state(
          words: 3,
          scores: [30, 40],
          next: 'ک',
          taunt: 'hurry_up',
          tauntText: 'زود باش!',
        ),
      );
      expect(find.text('زود باش!'), findsOneWidget);
      expect(top(tester, 'زود باش!'), greaterThan(top(tester, 'باران')));
      expect(top(tester, 'زود باش!'), lessThan(top(tester, 'نمک')));
      // End side (left in RTL), like their words.
      expect(
        tester.getCenter(find.text('زود باش!')).dx,
        lessThan(tester.view.physicalSize.width / 2),
      );
      // It is part of the chain, not an overlay pinned under the header.
      expect(
        find.ancestor(
          of: find.text('زود باش!'),
          matching: find.byType(SingleChildScrollView),
        ),
        findsWidgets,
      );
    });

    testWidgets('mine sits under my last word, start side, with my disc', (
      tester,
    ) async {
      await _size(tester, 393, 852);
      await arrive(
        tester,
        _state(words: 4, scores: [30, 40], myPremium: true),
        _state(
          words: 4,
          scores: [30, 40],
          myPremium: true,
          taunt: 'x',
          tauntText: 'همین بود؟',
          tauntFromMe: true,
        ),
      );
      // me: سیب, نمک; them: باران, کتاب → my last word is the third.
      expect(top(tester, 'همین بود؟'), greaterThan(top(tester, 'نمک')));
      expect(top(tester, 'همین بود؟'), lessThan(top(tester, 'کتاب')));
      expect(
        tester.getCenter(find.text('همین بود؟')).dx,
        greaterThan(tester.view.physicalSize.width / 2),
      );
    });

    testWidgets('sender and receiver both lose it after 3 s', (tester) async {
      await _size(tester, 393, 852);
      await arrive(
        tester,
        _state(words: 2),
        _state(words: 2, taunt: 'a', tauntText: 'زود باش!'),
      );
      await tester.pump(const Duration(milliseconds: 2500));
      expect(find.text('زود باش!'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 700));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('زود باش!'), findsNothing);
    });

    testWidgets('a second identical taunt shows again and restarts the 3 s', (
      tester,
    ) async {
      await _size(tester, 393, 852);
      await arrive(
        tester,
        _state(words: 2),
        _state(words: 2, taunt: 'a', tauntText: 'زود باش!'),
      );
      await tester.pump(const Duration(seconds: 4));
      expect(find.text('زود باش!'), findsNothing);
      final again = _state(words: 2, taunt: 'a', tauntText: 'زود باش!');
      await tester.pumpWidget(
        _screen(
          again.copyWith(taunt: 'a', tauntText: 'زود باش!', tauntFromMe: false),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('زود باش!'), findsOneWidget);
    });

    testWidgets('no word from the sender yet: it goes under the last word', (
      tester,
    ) async {
      await _size(tester, 393, 852);
      // Only my word exists; the opponent taunts first.
      await arrive(
        tester,
        _state(words: 1, scores: [30]),
        _state(words: 1, scores: [30], taunt: 'a', tauntText: 'زود باش!'),
      );
      expect(top(tester, 'زود باش!'), greaterThan(top(tester, 'سیب')));
      // Still on the sender's (end) side.
      expect(
        tester.getCenter(find.text('زود باش!')).dx,
        lessThan(tester.view.physicalSize.width / 2),
      );
    });

    testWidgets('empty chain: it goes right after the start chip', (
      tester,
    ) async {
      await _size(tester, 393, 852);
      await arrive(
        tester,
        _state(myPremium: true),
        _state(
          myPremium: true,
          taunt: 'a',
          tauntText: 'همین بود؟',
          tauntFromMe: true,
        ),
      );
      expect(find.text('شروع زنجیر'), findsOneWidget);
      expect(top(tester, 'همین بود؟'), greaterThan(top(tester, 'شروع زنجیر')));
      expect(tester.takeException(), isNull);
    });

    test(
      'zTauntAnchor: sender\'s last word, else the newest, else the start',
      () {
        const entries = [
          ZBubbleEntry(word: 'a', mine: true),
          ZBubbleEntry(word: 'b', mine: false),
          ZBubbleEntry(word: 'c', mine: true),
        ];
        expect(zTauntAnchor(entries, mine: true), 2);
        expect(zTauntAnchor(entries, mine: false), 1);
        expect(zTauntAnchor(entries.take(1).toList(), mine: false), 0);
        expect(zTauntAnchor(const [], mine: true), -1);
      },
    );
  });

  group('reduced motion', () {
    testWidgets('my turn: nothing schedules frames', (tester) async {
      await _size(tester, 393, 852);
      await tester.pumpWidget(
        _screen(_state(words: 2, time: 3), reduceMotion: true),
      );
      await tester.pump(const Duration(milliseconds: 600));
      expect(tester.hasRunningAnimations, isFalse);
    });

    testWidgets('opponent turn: no spinner, mascot still', (tester) async {
      await _size(tester, 393, 852);
      await tester.pumpWidget(
        _screen(_state(words: 3, myTurn: false), reduceMotion: true),
      );
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(tester.hasRunningAnimations, isFalse);
    });
  });

  group('layout', () {
    const sizes = [
      Size(320, 568),
      Size(360, 640),
      Size(393, 852),
      Size(430, 932),
    ];
    for (final brightness in Brightness.values) {
      for (final size in sizes) {
        testWidgets('no overflow ${size.width.toInt()}×${size.height.toInt()} '
            '${brightness.name}', (tester) async {
          await _size(tester, size.width, size.height);
          for (final s in [
            _state(),
            _state(
              words: 8,
              scores: [30, 40, 50, 60],
              next: 'گ',
              score: 99999,
              opponentScore: 88888,
              time: 3,
              myPremium: true,
              opponentPremium: true,
              opponentName: 'یک نام خیلی خیلی بلند برای حریف',
              taunt: 't',
              tauntText:
                  'یک طعنهٔ خیلی بلند که باید در دو خط جا شود و بریده شود',
              tauntFromMe: true,
            ),
            _state(words: 4, next: 'ب', myTurn: false, score: 1200),
          ]) {
            // Taunt states arrive as a change, so the in-chain pill is built.
            await tester.pumpWidget(_screen(_state(), brightness: brightness));
            await tester.pumpWidget(_screen(s, brightness: brightness));
            await tester.pump(const Duration(milliseconds: 700));
            expect(tester.takeException(), isNull);
          }
        });
      }
    }

    for (final brightness in Brightness.values) {
      testWidgets('tray fits at 320×568 ${brightness.name}', (tester) async {
        await _size(tester, 320, 568);
        await tester.pumpWidget(
          _screen(_state(myPremium: true), brightness: brightness),
        );
        await _settle(tester);
        await tester.tap(find.bySemanticsLabel(RegExp('^طعنه')));
        await tester.pump(const Duration(milliseconds: 700));
        expect(tester.takeException(), isNull);
        expect(find.text('طعنه بفرست'), findsOneWidget);
      });
    }

    for (final scale in [1.3, 1.6, 2.0]) {
      testWidgets('text ×$scale: no overflow, action labels capped at 1.3', (
        tester,
      ) async {
        await _size(tester, 360, 640);
        await tester.pumpWidget(
          _screen(
            _state(words: 4, next: 'ک', score: 1200, opponentScore: 980),
            textScale: scale,
          ),
        );
        await _settle(tester);
        expect(tester.takeException(), isNull);
        // The power-up labels sit inside fixed 66dp tiles: capped at 1.3×.
        final label = tester.renderObject<RenderParagraph>(
          find.text('وقت بیشتر'),
        );
        expect(label.textScaler.scale(10), closeTo(13, 0.01));
      });
    }

    testWidgets('thinking card with text ×1.6 at 320 wide: no overflow', (
      tester,
    ) async {
      await _size(tester, 320, 568);
      await tester.pumpWidget(
        _screen(
          _state(words: 3, myTurn: false, opponentName: 'یک نام بلند'),
          textScale: 1.6,
        ),
      );
      await _settle(tester);
      expect(tester.takeException(), isNull);
    });

    testWidgets('keyboard open on a small phone: no overflow', (tester) async {
      await _size(tester, 375, 667);
      tester.view.viewInsets = const FakeViewPadding(bottom: 260);
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpWidget(_screen(_state(words: 6, next: 'ب')));
      await _settle(tester);
      expect(tester.takeException(), isNull);
    });
  });

  goldens();

  group('contrast (≥ 4.5:1 for text)', () {
    for (final entry
        in {
          'light': (ZColors.light, ZScene.light),
          'dark': (ZColors.dark, ZScene.dark),
        }.entries) {
      test('${entry.key}: pill, chips, taunts, tray', () {
        final (z, zs) = entry.value;
        expect(contrastRatio(z.ink, z.surface), greaterThanOrEqualTo(4.5));
        expect(contrastRatio(z.ink60, z.surface), greaterThanOrEqualTo(4.5));
        // Locked taunts and the free-player line.
        expect(contrastRatio(z.ink60, z.wash), greaterThanOrEqualTo(4.5));
        expect(contrastRatio(z.ink, z.paper), greaterThanOrEqualTo(4.5));
        // Taunt pill and the tray's «ویژه» tag.
        expect(contrastRatio(z.onAmber, z.amber), greaterThanOrEqualTo(4.5));
        // Turn chip.
        expect(
          contrastRatio(z.onInkSurface, z.inkSurface),
          greaterThanOrEqualTo(4.5),
        );
        expect(contrastRatio(z.ink, z.wash), greaterThanOrEqualTo(4.5));
        // Lock badge on the taunt button.
        expect(
          contrastRatio(z.onInkSurface, z.inkSurface),
          greaterThanOrEqualTo(3),
        );
        // Opponent initial on the coral disc (large text, 3:1).
        expect(contrastRatio(zs.onCoralSm, z.coral), greaterThanOrEqualTo(3));
        expect(contrastRatio(z.onIndigo, z.indigo), greaterThanOrEqualTo(3));
        // Crown next to a premium name.
        expect(contrastRatio(z.amberDeep, z.surface), greaterThanOrEqualTo(3));
      });
    }
  });
}

class _GoldenHost extends StatelessWidget {
  final Widget child;
  const _GoldenHost(this.child);

  @override
  Widget build(BuildContext context) =>
      RepaintBoundary(key: const Key('golden'), child: child);
}

void goldens() {
  Future<void> shot(WidgetTester tester, String name) async {
    await tester.pump(const Duration(milliseconds: 100));
    await expectLater(
      find.byKey(const Key('golden')),
      matchesGoldenFile('goldens/$name.png'),
    );
  }

  for (final brightness in Brightness.values) {
    testWidgets('golden my turn mid-game ${brightness.name}', (tester) async {
      await _size(tester, 393, 852);
      final s = _state(
        words: 5,
        scores: [30, 40, 40],
        next: 'ف',
        score: 320,
        opponentScore: 290,
        time: 8,
        myPremium: true,
      );
      await tester.pumpWidget(
        _GoldenHost(_screen(s, brightness: brightness, reduceMotion: true)),
      );
      await shot(tester, 'z_versus_my_turn_${brightness.name}');
    });
  }

  for (final brightness in Brightness.values) {
    testWidgets('golden opponent turn, urgent ${brightness.name}', (
      tester,
    ) async {
      await _size(tester, 393, 852);
      final s = _state(
        words: 4,
        scores: [30, 40],
        next: 'ب',
        score: 70,
        opponentScore: 90,
        time: 4,
        myTurn: false,
        opponentPremium: true,
      );
      await tester.pumpWidget(
        _GoldenHost(_screen(s, brightness: brightness, reduceMotion: true)),
      );
      await shot(tester, 'z_versus_opponent_turn_${brightness.name}');
    });
  }

  testWidgets('golden received taunt light', (tester) async {
    await _size(tester, 393, 852);
    final base = _state(words: 3, scores: [30, 40], next: 'ک');
    await tester.pumpWidget(_GoldenHost(_screen(base, reduceMotion: true)));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpWidget(
      _GoldenHost(
        _screen(
          _state(
            words: 3,
            scores: [30, 40],
            next: 'ک',
            taunt: 'hurry_up',
            tauntText: 'ساعت داره می‌دوه…',
          ),
          reduceMotion: true,
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    await shot(tester, 'z_versus_taunt_light');
  });

  testWidgets('golden my taunt dark', (tester) async {
    await _size(tester, 393, 852);
    final base = _state(words: 4, scores: [30, 40], next: 'ب', myPremium: true);
    await tester.pumpWidget(
      _GoldenHost(
        _screen(base, brightness: Brightness.dark, reduceMotion: true),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpWidget(
      _GoldenHost(
        _screen(
          _state(
            words: 4,
            scores: [30, 40],
            next: 'ب',
            myPremium: true,
            taunt: 'a',
            tauntText: 'همین بود؟',
            tauntFromMe: true,
          ),
          brightness: Brightness.dark,
          reduceMotion: true,
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    await shot(tester, 'z_versus_taunt_mine_dark');
  });

  for (final brightness in Brightness.values) {
    for (final premium in [true, false]) {
      if (brightness == Brightness.dark && !premium) continue;
      testWidgets(
        'golden taunt tray ${premium ? 'premium' : 'free'} ${brightness.name}',
        (tester) async {
          await _size(tester, 393, 852);
          await tester.pumpWidget(
            _GoldenHost(
              _screen(
                _state(words: 3, next: 'ک', myPremium: premium),
                brightness: brightness,
                reduceMotion: true,
              ),
            ),
          );
          await tester.pump(const Duration(milliseconds: 100));
          await tester.tap(find.bySemanticsLabel(RegExp('^طعنه')));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 600));
          await shot(
            tester,
            'z_versus_tray_${premium ? 'premium' : 'free'}_${brightness.name}',
          );
        },
      );
    }
  }
}
