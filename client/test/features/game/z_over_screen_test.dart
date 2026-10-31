import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:wordchain/core/database/app_database.dart';
import 'package:wordchain/core/services/ad_service.dart';
import 'package:wordchain/core/services/monetization_service.dart';
import 'package:wordchain/core/services/share_service.dart';
import 'package:wordchain/core/theme/app_theme.dart';
import 'package:wordchain/core/theme/app_tokens.dart';
import 'package:wordchain/core/utils/persian_digits.dart';
import 'package:wordchain/core/widgets/z_hud_coin_pill.dart';
import 'package:wordchain/core/widgets/z_disc_avatar.dart';
import 'package:wordchain/core/widgets/z_load_state.dart';
import 'package:wordchain/core/widgets/z_mascot.dart';
import 'package:wordchain/core/widgets/z_state_card.dart';
import 'package:wordchain/features/auth/cubit/auth_cubit.dart';
import 'package:wordchain/features/game/bloc/game_bloc.dart';
import 'package:wordchain/features/game/data/game_constants.dart';
import 'package:wordchain/features/game/view/game_screen.dart';
import 'package:wordchain/features/game/view/z_over_screen.dart';
import 'package:wordchain/features/words/data/word_suggestions_repository.dart';

import '../../helpers/contrast.dart';
import '../../helpers/game_fakes.dart';
import '../../helpers/z_test_app.dart';

const _chain = ['سیب', 'بازار', 'رود', 'دریا', 'انار'];

GameOver _over({
  String reason = 'timeout',
  String mode = 'classic',
  String? rejectedWord,
  String? rejectionReason,
  String? opponentType,
  bool? iWon,
  int score = 480,
  int chainLength = 17,
  List<String> chain = _chain,
  int opponentScore = 0,
  bool canContinue = false,
  int continueTimeRemaining = 0,
  bool isSaved = true,
  int entryFee = 0,
  int coinsNet = 0,
  String? myAvatarId,
  String? opponentAvatarId,
}) => GameOver(
  localMatchId: -1,
  mode: mode,
  reason: reason,
  rejectedWord: rejectedWord,
  rejectionReason: rejectionReason,
  score: score,
  chainLength: chainLength,
  wordChain: chain,
  canContinue: canContinue,
  continueTimeRemaining: continueTimeRemaining,
  isSaved: isSaved,
  winnerId: iWon == null ? null : 'winner',
  iWon: iWon,
  opponentScore: opponentScore,
  opponentType: opponentType,
  entryFee: entryFee,
  coinsNet: coinsNet,
  myAvatarId: myAvatarId,
  opponentAvatarId: opponentAvatarId,
);

/// The offer of a solo loss with the continue window open.
GameOver _continueOffer({String? opponentType = 'solo'}) => _over(
  reason: 'timeout',
  opponentType: opponentType,
  canContinue: true,
  continueTimeRemaining: 12,
  isSaved: false,
);

/// A won 1v1 with the entry fee settled.
GameOver _versusWin() => _over(
  iWon: true,
  score: 360,
  opponentScore: 240,
  entryFee: 20,
  coinsNet: 20,
);

GameOver _versusLoss() => _over(
  iWon: false,
  reason: 'invalid_word',
  rejectedWord: 'قلمم',
  rejectionReason: 'not_in_dictionary',
  score: 200,
  opponentScore: 350,
  entryFee: 20,
  coinsNet: -20,
);

class _FakeStats extends Fake implements StatsDao {
  final int best;
  _FakeStats(this.best);

  @override
  Future<LocalPlayerStat?> getStats() async => LocalPlayerStat(
    id: 1,
    totalMatches: 3,
    wins: 1,
    bestScore: 400,
    bestMatchStreak: best,
    dailyStreak: 0,
    longestDailyStreak: 0,
  );
}

class _SignedInAuth extends FakeAuthCubit {
  _SignedInAuth(super.state);

  @override
  bool get isGuest => current is! AuthAuthenticated;
}

class _FakeShare extends Fake implements ShareService {
  final shared = <(int, int)>[];

  @override
  Future<void> shareMatch(
    BuildContext context, {
    required int score,
    required int chainLength,
    List<String> words = const [],
    bool? won,
  }) async => shared.add((score, chainLength));
}

class _FakeWords extends Fake implements WordSuggestionsRepository {
  final suggested = <String>[];
  final flagged = <(String, WordFlagReason)>[];

  @override
  Future<bool> suggestWord(String word) async {
    suggested.add(word);
    return false;
  }

  @override
  Future<bool> flagWord(String word, WordFlagReason reason) async {
    flagged.add((word, reason));
    return false;
  }
}

class _FakeAds extends Fake implements AdService {
  bool available = true;
  int shown = 0;

  @override
  bool get rewardedEnabled => true;

  @override
  Future<bool> showRewardedAd() async {
    shown++;
    return available;
  }
}

class _FakeMoney extends Fake implements MonetizationService {
  bool canPay = true;
  final spent = <int>[];

  @override
  bool spendCoins(int amount) {
    if (!canPay) return false;
    spent.add(amount);
    return true;
  }
}

class _Harness {
  final FakeGameBloc bloc = FakeGameBloc();
  final share = _FakeShare();
  final ads = _FakeAds();
  final money = _FakeMoney();
  final words = _FakeWords();
  final routes = <String>[];
  Object? gameExtra;

  void register({
    AuthState auth = const AuthAuthenticated(
      userId: 'u',
      username: 'Maryam',
      coins: 1240,
    ),
    int? bestChain,
  }) {
    final g = GetIt.I;
    g.registerSingleton<AuthCubit>(_SignedInAuth(auth));
    g.registerSingleton<ShareService>(share);
    g.registerSingleton<AdService>(ads);
    g.registerSingleton<MonetizationService>(money);
    g.registerSingleton<WordSuggestionsRepository>(words);
    if (bestChain != null) g.registerSingleton<StatsDao>(_FakeStats(bestChain));
  }

  /// [over] on the real router so `go`/`pushReplacement` land somewhere
  /// observable.
  Widget app(
    GameOver over, {
    Brightness brightness = Brightness.light,
    bool reduceMotion = false,
  }) {
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder:
              (context, _) => BlocProvider<GameBloc>.value(
                value: bloc,
                child: ZOverScreen(state: over),
              ),
        ),
        GoRoute(
          path: '/home',
          builder: (context, _) {
            routes.add('/home');
            return const Text('HOME');
          },
        ),
        GoRoute(
          path: '/lobby',
          builder: (context, _) {
            routes.add('/lobby');
            return const Text('LOBBY');
          },
        ),
        GoRoute(
          path: '/game',
          builder: (context, state) {
            routes.add('/game');
            gameExtra = state.extra;
            return const Text('GAME');
          },
        ),
      ],
    );
    return MaterialApp.router(
      debugShowCheckedModeBanner: false,
      theme: brightness == Brightness.light ? AppTheme.light : AppTheme.dark,
      routerConfig: router,
      builder:
          (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(disableAnimations: reduceMotion),
            child: Directionality(
              textDirection: TextDirection.rtl,
              child: child!,
            ),
          ),
    );
  }
}

Future<void> _size(WidgetTester t, double w, double h) async {
  t.view.devicePixelRatio = 1;
  t.view.physicalSize = Size(w, h);
  addTearDown(t.view.reset);
}

/// Lets the entrance animations (≤ 1 s) finish.
Future<void> _settle(WidgetTester t) async {
  await t.pump();
  await t.pump(const Duration(milliseconds: 1200));
}

Finder _rich(String s) => find.textContaining(s, findRichText: true);

void main() {
  setUpAll(loadVazirmatn);
  tearDown(() => GetIt.I.reset());

  late _Harness h;
  setUp(() => h = _Harness());

  Future<void> show(
    WidgetTester t,
    GameOver over, {
    Brightness brightness = Brightness.light,
    bool reduceMotion = false,
    double w = 396,
    double hgt = 812,
  }) async {
    await _size(t, w, hgt);
    await t.pumpWidget(
      h.app(over, brightness: brightness, reduceMotion: reduceMotion),
    );
    await _settle(t);
  }

  group('loss', () {
    testWidgets('timeout: broken chain, reason, score and stat tiles', (
      t,
    ) async {
      h.register(bestChain: 23);
      await show(t, _over(opponentType: 'solo'));
      expect(find.text('زنجیر پاره شد!'), findsOneWidget);
      expect(find.text('وقت تموم شد؛ کلمه‌ای با «ر» نداشتی.'), findsOneWidget);
      expect(find.byType(ZMascot), findsOneWidget);
      expect(t.widget<ZMascot>(find.byType(ZMascot)).mood, ZMascotMood.sad);
      expect(find.text('امتیاز این دست'), findsOneWidget);
      expect(find.text(toPersianDigits(480)), findsOneWidget);
      expect(find.text('طول زنجیر'), findsOneWidget);
      expect(find.text('${toPersianDigits(17)} کلمه'), findsOneWidget);
      expect(find.text('بلندترین'), findsOneWidget);
      // The last three words and the dashed slot of the missed letter.
      expect(_rich('رود'), findsOneWidget);
      expect(_rich('دریا'), findsOneWidget);
      expect(_rich('انار'), findsOneWidget);
      expect(_rich('ر؟'), findsOneWidget);
      expect(_rich('سیب'), findsNothing);
    });

    testWidgets('rejected word reasons', (t) async {
      h.register();
      final cases = {
        'wrong_letter': '«قلم» با حرف درست شروع نمی‌شد.',
        'already_used': '«قلم» قبلاً استفاده شده بود.',
        'too_short': '«قلم» خیلی کوتاه بود.',
        'not_in_dictionary': '«قلم» توی فرهنگ لغت نبود.',
      };
      for (final e in cases.entries) {
        await show(
          t,
          _over(
            reason: 'invalid_word',
            opponentType: 'solo',
            rejectedWord: 'قلم',
            rejectionReason: e.key,
          ),
        );
        expect(find.text(e.value), findsOneWidget, reason: e.key);
      }
    });

    group('word report (Phase 24)', () {
      testWidgets('a word the dictionary refused can be reported in one tap', (
        t,
      ) async {
        h.register();
        await show(
          t,
          _over(
            reason: 'invalid_word',
            opponentType: 'solo',
            rejectedWord: 'قلمم',
            rejectionReason: 'not_in_dictionary',
          ),
        );
        final pill = find.text('«قلمم» درست بود؟ گزارش بده');
        expect(pill, findsOneWidget);
        await t.tap(pill);
        await t.pump();
        await t.pump(const Duration(milliseconds: 300));
        expect(h.words.suggested, ['قلمم']);
        expect(find.text('گزارش شد؛ ممنون'), findsOneWidget);
        // Sent once: the pill no longer reacts.
        await t.tap(find.text('گزارش شد؛ ممنون'));
        await t.pump();
        expect(h.words.suggested, hasLength(1));
        await t.pump(const Duration(seconds: 6)); // let the toast go
      });

      testWidgets('not offered for the player\'s own mistakes or a timeout', (
        t,
      ) async {
        h.register();
        for (final reason in ['wrong_letter', 'already_used', 'too_short']) {
          await show(
            t,
            _over(
              reason: 'invalid_word',
              opponentType: 'solo',
              rejectedWord: 'قلم',
              rejectionReason: reason,
            ),
          );
          expect(
            find.textContaining('گزارش بده'),
            findsNothing,
            reason: reason,
          );
        }
        await show(t, _over(opponentType: 'solo'));
        expect(find.textContaining('گزارش بده'), findsNothing);
      });

      testWidgets(
        'offered after a 1v1 loss too, and the chain can be flagged',
        (t) async {
          h.register();
          await show(t, _versusLoss());
          expect(find.text('«قلمم» درست بود؟ گزارش بده'), findsOneWidget);
          expect(find.text('کلمه‌ای اشتباه یا نامناسب بود؟'), findsOneWidget);
        },
      );

      testWidgets(
        'solo has no word to flag (every word is the player\'s own)',
        (t) async {
          h.register();
          await show(t, _over(opponentType: 'solo'));
          expect(find.text('کلمه‌ای اشتباه یا نامناسب بود؟'), findsNothing);
        },
      );

      testWidgets('flagging a chain word sends the chosen reason', (t) async {
        h.register();
        await show(t, _versusLoss());
        await t.tap(find.text('کلمه‌ای اشتباه یا نامناسب بود؟'));
        await _settle(
          t,
        ); // the dialog drops in (mascots loop, so no pumpAndSettle)
        await t.tap(find.text('دریا').last);
        await t.tap(find.text('نامناسب است'));
        await t.pump();
        await t.tap(find.text('ارسال گزارش'));
        await _settle(t);
        expect(h.words.flagged, [('دریا', WordFlagReason.inappropriate)]);
        expect(find.text('ممنون از گزارشت'), findsOneWidget);
      });
    });

    testWidgets('ending the game yourself is not «chain broken»', (t) async {
      h.register();
      await show(t, _over(reason: 'ended_by_user', opponentType: 'solo'));
      expect(find.text('بازی را پایان دادی'), findsOneWidget);
      expect(find.text('با میل خودت بازی رو تموم کردی.'), findsOneWidget);
    });

    testWidgets('empty chain: no tail, no required letter', (t) async {
      h.register();
      await show(
        t,
        _over(opponentType: 'solo', chain: const [], chainLength: 0, score: 0),
      );
      expect(find.text('وقت تموم شد.'), findsOneWidget);
      expect(_rich('؟'), findsNothing);
    });

    testWidgets('1v1 loss: opponent score and coin tiles, «باختی!»', (t) async {
      h.register();
      await show(t, _versusLoss());
      expect(find.text('باختی!'), findsOneWidget);
      expect(find.text('«قلمم» توی فرهنگ لغت نبود.'), findsOneWidget);
      expect(find.text('امتیاز حریف'), findsOneWidget);
      expect(find.text(toPersianDigits(350)), findsOneWidget);
      expect(find.text('سکه'), findsOneWidget);
      expect(find.text('−${toPersianDigits(20)}'), findsOneWidget);
      // No solo record in a duel.
      expect(find.textContaining('رکورد'), findsNothing);
    });

    testWidgets('draw: coins unchanged', (t) async {
      h.register();
      await show(t, _over(iWon: false, opponentScore: 5, entryFee: 20));
      expect(find.text('بدون تغییر'), findsOneWidget);
    });
  });

  group('record bar', () {
    testWidgets('near miss: gap to the record', (t) async {
      h.register(bestChain: 23);
      await show(t, _over(opponentType: 'solo'));
      expect(find.text('تا رکوردت (${toPersianDigits(23)})'), findsOneWidget);
      expect(find.text('${toPersianDigits(6)} کلمهٔ دیگر'), findsOneWidget);
      expect(
        find.text('${toPersianDigits(17)} / ${toPersianDigits(23)}'),
        findsOneWidget,
      );
    });

    testWidgets('record beaten (or equalled): «رکورد جدید!»', (t) async {
      h.register(bestChain: 17);
      await show(t, _over(opponentType: 'solo'));
      expect(find.text('رکورد جدید!'), findsOneWidget);
      expect(find.textContaining(' / '), findsNothing);
      expect(find.textContaining('کلمهٔ دیگر'), findsNothing);
    });

    testWidgets('hidden while the record is unknown', (t) async {
      h.register(); // no StatsDao registered
      await show(t, _over(opponentType: 'solo'));
      expect(find.textContaining('رکورد'), findsNothing);
    });

    testWidgets('vs-AI keeps the record as a tile, no bar', (t) async {
      h.register(bestChain: 23);
      await show(
        t,
        _over(opponentType: 'ai_easy', score: 100, opponentScore: 200),
      );
      expect(find.text('رکورد تو'), findsOneWidget);
      expect(find.text('${toPersianDigits(23)} کلمه'), findsOneWidget);
      expect(find.textContaining('تا رکوردت'), findsNothing);
    });
  });

  group('continue offer', () {
    testWidgets('video, coins at the real price, share, home, countdown', (
      t,
    ) async {
      h.register();
      await show(t, _continueOffer());
      expect(find.text('ادامه با ویدیو'), findsOneWidget);
      expect(
        find.text(
          'ادامه با ${toPersianDigits(GameConstants.continueCostCoins)} سکه',
        ),
        findsOneWidget,
      );
      expect(GameConstants.continueCostCoins, 25);
      expect(find.bySemanticsLabel('اشتراک‌گذاری نتیجه'), findsOneWidget);
      expect(
        find.text('فرصت ادامه: ${toPersianDigits(12)} ثانیه'),
        findsOneWidget,
      );
      // Final actions are not offered yet.
      expect(find.text('بازی دوباره'), findsNothing);
    });

    testWidgets('video: ad watched → ContinueRequested(ad)', (t) async {
      h.register();
      await show(t, _continueOffer());
      await t.tap(find.text('ادامه با ویدیو'));
      await t.pump();
      expect(h.ads.shown, 1);
      expect(h.bloc.events.single, isA<ContinueRequested>());
      expect((h.bloc.events.single as ContinueRequested).method, 'ad');
    });

    testWidgets('video: no ad available → toast, no continue', (t) async {
      h.register();
      h.ads.available = false;
      await show(t, _continueOffer());
      await t.tap(find.text('ادامه با ویدیو'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 300));
      expect(h.bloc.events, isEmpty);
      expect(
        find.text('تبلیغی در دسترس نیست؛ بعداً دوباره تلاش کن.'),
        findsOneWidget,
      );
      await t.pump(const Duration(seconds: 6));
    });

    testWidgets('coins: pays 25 → ContinueRequested(coins)', (t) async {
      h.register();
      await show(t, _continueOffer());
      await t.tap(find.textContaining('ادامه با ${toPersianDigits(25)}'));
      await t.pump();
      expect(h.money.spent, [25]);
      expect((h.bloc.events.single as ContinueRequested).method, 'coins');
    });

    testWidgets('coins: cannot pay → earn-coins dialog, no continue', (
      t,
    ) async {
      h.register();
      h.money.canPay = false;
      await show(t, _continueOffer());
      await t.tap(find.textContaining('ادامه با ${toPersianDigits(25)}'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 700));
      expect(h.bloc.events, isEmpty);
      expect(find.byType(Dialog), findsNothing); // custom ZDialog, not Material
      expect(find.textContaining('سکه'), findsWidgets);
      expect(h.money.spent, isEmpty);
    });

    testWidgets('home square and ✕ both decline the continue', (t) async {
      h.register();
      await show(t, _continueOffer());
      await t.tap(find.bySemanticsLabel('ادامه نمی‌دم؛ بازگشت به خانه'));
      await t.pump();
      expect(h.bloc.events.last, isA<AcceptDefeat>());
      await t.tap(find.bySemanticsLabel('بستن'));
      await t.pump();
      expect(h.bloc.events.whereType<AcceptDefeat>().length, 2);
      expect(h.routes, isEmpty);
    });

    testWidgets('share sends the score and the chain length', (t) async {
      h.register();
      await show(t, _continueOffer());
      await t.tap(find.bySemanticsLabel('اشتراک‌گذاری نتیجه'));
      await t.pump();
      expect(h.share.shared, [(480, 17)]);
    });

    testWidgets('multiplayer own loss offers it too', (t) async {
      h.register();
      await show(t, _continueOffer(opponentType: null));
      expect(find.text('زنجیر پاره شد!'), findsOneWidget);
      expect(find.text('ادامه با ویدیو'), findsOneWidget);
    });

    testWidgets('window over → final actions', (t) async {
      h.register();
      await show(
        t,
        _over(
          opponentType: 'solo',
          canContinue: true,
          continueTimeRemaining: 0,
          isSaved: false,
        ),
      );
      expect(find.text('ادامه با ویدیو'), findsNothing);
      expect(find.text('بازی دوباره'), findsOneWidget);
    });
  });

  group('final actions', () {
    testWidgets('solo: play again restarts a solo classic game', (t) async {
      h.register();
      await show(t, _over(opponentType: 'solo'));
      await t.tap(find.text('بازی دوباره'));
      await t.pumpAndSettle();
      final args = h.gameExtra as GameRouteArgs;
      expect(args.opponentType, 'solo');
      expect(args.mode, 'classic');
      expect(find.text('GAME'), findsOneWidget);
    });

    testWidgets('vs-AI: play again keeps the level', (t) async {
      h.register();
      await show(
        t,
        _over(opponentType: 'ai_hard', score: 100, opponentScore: 200),
      );
      await t.tap(find.text('بازی دوباره'));
      await t.pumpAndSettle();
      expect((h.gameExtra as GameRouteArgs).opponentType, 'ai_hard');
    });

    testWidgets('1v1: «حریف جدید» goes to the lobby', (t) async {
      h.register();
      await show(t, _versusLoss());
      expect(find.text('بازی دوباره'), findsNothing);
      await t.tap(find.text('حریف جدید'));
      await t.pumpAndSettle();
      expect(find.text('LOBBY'), findsOneWidget);
    });

    testWidgets('play again waits for the save', (t) async {
      h.register();
      await show(t, _over(opponentType: 'solo', isSaved: false));
      await t.tap(find.text('بازی دوباره'));
      await t.pump(const Duration(milliseconds: 500));
      expect(h.routes, isNot(contains('/game')));
    });

    testWidgets('home and ✕ go home', (t) async {
      h.register();
      await show(t, _over(opponentType: 'solo'));
      await t.tap(find.text('خانه'));
      await t.pumpAndSettle();
      expect(find.text('HOME'), findsOneWidget);
    });

    testWidgets('✕ goes home once there is nothing to decide', (t) async {
      h.register();
      await show(t, _over(opponentType: 'solo'));
      await t.tap(find.bySemanticsLabel('بستن'));
      await t.pumpAndSettle();
      expect(find.text('HOME'), findsOneWidget);
    });

    testWidgets('share', (t) async {
      h.register();
      await show(t, _over(opponentType: 'solo'));
      await t.tap(find.text('اشتراک‌گذاری'));
      await t.pump();
      expect(h.share.shared, [(480, 17)]);
    });
  });

  group('win', () {
    testWidgets('1v1 win: title, head-to-head, reward chips', (t) async {
      h.register();
      await show(t, _versusWin());
      expect(find.text('بردی!'), findsOneWidget);
      expect(t.widget<ZMascot>(find.byType(ZMascot)).mood, ZMascotMood.happy);
      expect(find.text(toPersianDigits(360)), findsOneWidget);
      expect(find.text(toPersianDigits(240)), findsOneWidget);
      expect(find.text('مقابل حریف'), findsOneWidget);
      expect(find.text('+${toPersianDigits(20)}'), findsOneWidget);
      expect(find.text('سکه · سود این بازی'), findsOneWidget);
      // XP is the game's score.
      expect(find.text('+${toPersianDigits(360)}'), findsOneWidget);
      expect(find.text('امتیاز تجربه'), findsOneWidget);
      expect(find.text('بلندترین کلمه'), findsOneWidget);
      // Never invented: rounds, a level bar, a rematch.
      expect(find.textContaining('دست'), findsNothing);
      expect(find.textContaining('دوباره با'), findsNothing);
      expect(find.text('حریف جدید'), findsOneWidget);
    });

    testWidgets('1v1 win: both discs carry their premium avatars', (t) async {
      h.register();
      await show(
        t,
        _over(
          iWon: true,
          score: 360,
          opponentScore: 240,
          myAvatarId: 'lion',
          opponentAvatarId: 'fox',
        ),
      );
      final ids =
          t
              .widgetList<ZDiscAvatar>(find.byType(ZDiscAvatar))
              .map((d) => d.avatarId)
              .whereType<String>();
      expect(ids, containsAll(['lion', 'fox']));
      // No avatar → initial, as before.
      await show(t, _over(iWon: true, score: 360, opponentScore: 240));
      expect(find.text('ح'), findsOneWidget);
    });

    testWidgets('server win with a lower score is still a win', (t) async {
      h.register();
      await show(
        t,
        _over(
          iWon: true,
          score: 100,
          opponentScore: 300,
          entryFee: 20,
          coinsNet: 20,
        ),
      );
      expect(find.text('بردی!'), findsOneWidget);
    });

    testWidgets('free match (no fee): no coin chip', (t) async {
      h.register();
      await show(t, _over(iWon: true, score: 360, opponentScore: 240));
      expect(find.text('سکه · سود این بازی'), findsNothing);
      expect(find.text('امتیاز تجربه'), findsOneWidget);
    });

    testWidgets('guest has no XP chip', (t) async {
      h.register(auth: const AuthGuest());
      await show(
        t,
        _over(opponentType: 'ai_easy', score: 300, opponentScore: 100),
      );
      expect(find.text('بردی!'), findsOneWidget);
      expect(find.text('امتیاز تجربه'), findsNothing);
      expect(find.byType(ZHudCoinPill), findsNothing);
    });

    testWidgets('vs-AI win by score names the level', (t) async {
      h.register();
      await show(
        t,
        _over(opponentType: 'ai_easy', score: 200, opponentScore: 100),
      );
      expect(find.text('بردی!'), findsOneWidget);
      expect(find.text('مقابل حریف هوشمند · آسان'), findsOneWidget);
    });

    testWidgets('vs-AI loss by score', (t) async {
      h.register(bestChain: 5);
      await show(
        t,
        _over(opponentType: 'ai_medium', score: 100, opponentScore: 200),
      );
      expect(find.text('باختی!'), findsOneWidget);
      expect(find.text('امتیاز حریف'), findsOneWidget);
    });
  });

  group('header', () {
    testWidgets('shows the live coin balance of a signed-in player', (t) async {
      h.register();
      await show(t, _over(opponentType: 'solo'));
      final pill = find.byType(ZHudCoinPill);
      expect(pill, findsOneWidget);
      expect(
        find.descendant(
          of: pill,
          matching: find.text(formatPersianNumber(1240)),
        ),
        findsOneWidget,
      );
      // A read-out: no «+» top-up affordance.
      expect(find.descendant(of: pill, matching: find.text('+')), findsNothing);
    });
  });

  group('daily', () {
    testWidgets('still only the saving frame (ZDailyAfter owns the result)', (
      t,
    ) async {
      h.register();
      await show(t, _over(mode: 'daily', opponentType: 'solo', isSaved: false));
      expect(find.byType(ZLoadState), findsOneWidget);
      expect(find.byType(ZStateCard), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('زنجیر پاره شد!'), findsNothing);
    });
  });

  group('reduced motion', () {
    for (final (name, over) in [
      ('loss', _continueOffer()),
      ('win', _versusWin()),
    ]) {
      testWidgets('$name: nothing animates', (t) async {
        h.register();
        await show(t, over, reduceMotion: true);
        await t.pump(const Duration(seconds: 1));
        expect(t.binding.hasScheduledFrame, isFalse);
      });
    }
  });

  group('layout', () {
    const sizes = [
      Size(320, 568),
      Size(360, 640),
      Size(393, 852),
      Size(430, 932),
    ];
    final cases = <(String, GameOver Function())>[
      ('loss + continue', _continueOffer),
      ('loss, final, 1v1', _versusLoss),
      (
        'long words',
        () => _over(
          opponentType: 'solo',
          chain: const ['مسئولیت‌پذیری', 'یکپارچه‌سازی', 'نامهربانانه'],
          chainLength: 3,
        ),
      ),
      ('win', _versusWin),
      (
        'win, huge scores',
        () => _over(
          iWon: true,
          score: 99999,
          opponentScore: 88888,
          entryFee: 20,
          coinsNet: 20,
        ),
      ),
    ];
    for (final brightness in Brightness.values) {
      for (final size in sizes) {
        for (final (name, build) in cases) {
          testWidgets('$name @ ${size.width.toInt()}×${size.height.toInt()} '
              '${brightness.name}', (t) async {
            h.register(bestChain: 23);
            await show(
              t,
              build(),
              brightness: brightness,
              reduceMotion: true,
              w: size.width,
              hgt: size.height,
            );
            final error = t.takeException();
            expect(error, isNull, reason: error?.toString());
          });
        }
      }
    }

    testWidgets('scales with big text without overflowing', (t) async {
      h.register(bestChain: 23);
      await _size(t, 360, 640);
      await t.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(1.6)),
          child: h.app(_continueOffer(), reduceMotion: true),
        ),
      );
      await _settle(t);
      final error = t.takeException();
      expect(error, isNull, reason: error?.toString());
    });
  });

  group('contrast (≥ 4.5:1 for text)', () {
    for (final b in Brightness.values) {
      test('stat tiles and chips, ${b.name}', () {
        final theme = b == Brightness.light ? AppTheme.light : AppTheme.dark;
        final z = theme.extension<ZColors>()!;
        void atLeast(Color fg, Color bg, String what) => expect(
          contrastRatio(fg, bg),
          greaterThanOrEqualTo(4.5),
          reason: what,
        );
        atLeast(z.ink, z.wash, 'tile value');
        atLeast(z.ink60, z.wash, 'tile label');
        atLeast(z.ink, z.surface, 'score');
        atLeast(z.ink60, z.surface, 'score label');
        atLeast(z.onInkSurface, z.inkSurface, 'reason pill');
        atLeast(z.onAmber, z.amber, 'coin chip');
        atLeast(z.onIndigo, z.indigo, 'xp chip');
        atLeast(z.ink, z.surface, 'longest-word chip');
        // 20–23sp / 900 labels are large text: the 3:1 bar applies (the same
        // white-on-teal pairing every teal button in the app uses).
        expect(
          contrastRatio(z.onTeal, z.teal),
          greaterThanOrEqualTo(3.0),
          reason: 'play-again label',
        );
        atLeast(z.ink, z.paper, 'ink on the page');
      });
    }
  });

  group('goldens', () {
    Future<void> shoot(
      WidgetTester t,
      GameOver over,
      Brightness b,
      String name, {
      int? best,
    }) async {
      h.register(bestChain: best);
      await show(t, over, brightness: b, reduceMotion: true);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/$name.png'),
      );
    }

    for (final b in Brightness.values) {
      final k = b.name;
      testWidgets('loss + continue $k', (t) async {
        await shoot(t, _continueOffer(), b, 'z_over_continue_$k', best: 23);
      });
      testWidgets('win $k', (t) async {
        await shoot(t, _versusWin(), b, 'z_over_win_$k');
      });
    }
    testWidgets('loss final, 1v1 light', (t) async {
      await shoot(t, _versusLoss(), Brightness.light, 'z_over_loss_light');
    });
    testWidgets('new record, final light', (t) async {
      await shoot(
        t,
        _over(opponentType: 'solo'),
        Brightness.light,
        'z_over_record_light',
        best: 17,
      );
    });
  });
}
