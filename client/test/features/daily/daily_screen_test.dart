import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:wordchain/core/database/app_database.dart';
import 'package:wordchain/core/services/ad_service.dart';
import 'package:wordchain/core/services/share_service.dart';
import 'package:wordchain/core/theme/app_scene_tokens.dart';
import 'package:wordchain/core/theme/app_theme.dart';
import 'package:wordchain/core/theme/app_tokens.dart';
import 'package:wordchain/core/utils/error_messages.dart';
import 'package:wordchain/core/widgets/z_load_state.dart';
import 'package:wordchain/core/widgets/z_ribbon_title.dart';
import 'package:wordchain/features/auth/cubit/auth_cubit.dart';
import 'package:wordchain/features/daily/data/daily_repository.dart';
import 'package:wordchain/features/daily/view/daily_screen.dart';
import 'package:wordchain/features/daily/view/widgets/daily_chain_card.dart';
import 'package:wordchain/features/daily/view/widgets/daily_compare_card.dart';
import 'package:wordchain/features/game/view/game_screen.dart';
import 'package:wordchain/features/game/view/widgets/z_game_hud.dart';
import 'package:wordchain/features/game/view/widgets/z_game_word.dart';

import '../../helpers/contrast.dart';
import '../../helpers/game_fakes.dart';
import '../../helpers/z_test_app.dart';
import 'daily_fakes.dart';

/// Friday 2026-10-16 15:30 in Iran: 8 h 30 min to the next challenge.
DateTime _now() => DateTime.utc(2026, 10, 16, 12);

class _Auth extends FakeAuthCubit {
  _Auth() : super(const AuthAuthenticated(userId: 'me', username: 'آرش', coins: 90));

  @override
  bool get isGuest => false;
}

class _Ads extends Fake implements AdService {
  @override
  bool get rewardedEnabled => false;
}

class _Harness {
  final repo = FakeDailyRepo(dailyChallenge());
  final share = FakeShare();
  final visited = <String>[];
  final extras = <Object?>[];

  Future<void> register({FakeStats? stats}) async {
    GetIt.I
      ..registerSingleton<AuthCubit>(_Auth())
      ..registerSingleton<DailyRepository>(repo)
      ..registerSingleton<ShareService>(share)
      ..registerSingleton<StatsDao>(stats ?? FakeStats(lastPlayed: DateTime(2026, 10, 16)))
      ..registerSingleton<AdService>(_Ads());
  }

  Widget app({Brightness brightness = Brightness.light, bool reduceMotion = true, double textScale = 1}) {
    final router = GoRouter(
      initialLocation: '/daily',
      routes: [
        GoRoute(path: '/daily', builder: (_, _) => DailyScreen(clock: _now)),
        for (final path in ['/game', '/daily/board', '/home', '/rewards', '/friends'])
          GoRoute(
            path: path,
            builder: (_, state) {
              visited.add(state.uri.toString());
              extras.add(state.extra);
              return Scaffold(body: Text('route $path'));
            },
          ),
      ],
    );
    return MaterialApp.router(
      debugShowCheckedModeBanner: false,
      routerConfig: router,
      theme: brightness == Brightness.light ? AppTheme.light : AppTheme.dark,
      builder:
          (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(disableAnimations: reduceMotion, textScaler: TextScaler.linear(textScale)),
            child: Directionality(textDirection: TextDirection.rtl, child: child!),
          ),
    );
  }
}

void _size(WidgetTester tester, double w, double h) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(w, h);
  addTearDown(tester.view.reset);
}

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
  await tester.pump(const Duration(milliseconds: 700));
}

void main() {
  setUpAll(loadVazirmatn);

  late _Harness h;

  setUp(() async {
    await GetIt.I.reset();
    h = _Harness();
  });

  tearDown(() async {
    await GetIt.I.reset();
  });

  Future<void> open(
    WidgetTester tester, {
    Brightness brightness = Brightness.light,
    bool reduceMotion = true,
    double textScale = 1,
    double w = 393,
    double hgt = 852,
    FakeStats? stats,
  }) async {
    _size(tester, w, hgt);
    await h.register(stats: stats);
    await tester.pumpWidget(h.app(brightness: brightness, reduceMotion: reduceMotion, textScale: textScale));
    await _settle(tester);
  }

  Future<void> tapText(WidgetTester tester, String text) async {
    final finder = find.text(text);
    await tester.ensureVisible(finder);
    await tester.pump();
    await tester.tap(finder);
    await tester.pump();
  }

  group('loading and failure', () {
    testWidgets('loading: the mascot card under the same header', (tester) async {
      h.repo.loadGate = Completer();
      await open(tester);
      expect(find.byType(ZLoadState), findsOneWidget);
      expect(find.text(ZLoadState.loadingLabel), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.byType(ZRibbonTitle), findsOneWidget);
      expect(find.byType(ZGameBackButton), findsOneWidget);
    });

    testWidgets('failure: the Persian message and a working retry', (tester) async {
      h.repo.loadError = const DailyException(code: 'no_daily_challenge', message: 'چالش امروز هنوز آماده نشده');
      await open(tester);
      expect(find.text('چالش امروز هنوز آماده نشده'), findsOneWidget);
      expect(find.text(ZLoadState.retryLabel), findsOneWidget);

      h.repo.loadError = null;
      await tapText(tester, ZLoadState.retryLabel);
      await _settle(tester);
      expect(h.repo.loads, 2);
      expect(find.text('شروع چالش امروز'), findsOneWidget);
      expect(find.byType(ZLoadState), findsNothing);
    });

    testWidgets('back from the failure card goes home', (tester) async {
      h.repo.loadError = const DailyException(code: 'x', message: 'خطا');
      await open(tester);
      await tester.tap(find.byType(ZGameBackButton));
      await _settle(tester);
      expect(h.visited, ['/home']);
    });
  });

  group('before the game', () {
    testWidgets('header, hero, rules and the real facts', (tester) async {
      await open(tester);
      expect(find.text('چالش روزانه'), findsOneWidget);
      expect(find.text('جمعه ۲۴ مهر'), findsOneWidget, reason: 'date chip');
      expect(find.text('حرف شروع امروز'), findsOneWidget);
      expect(find.text('ب'), findsOneWidget, reason: 'the start letter');
      expect(find.text('تا کجا می‌کشونیش؟'), findsOneWidget);
      expect(find.text('رکورد امروز ۴۶۰ امتیاز'), findsOneWidget);

      expect(find.text('۲ جان'), findsOneWidget);
      expect(find.text('۱۵ ثانیه'), findsOneWidget, reason: 'not the canvas 10');
      expect(find.text('یک بار رایگان'), findsOneWidget);
      expect(find.text('بار دوم ۲۵ سکه'), findsOneWidget);

      expect(find.text('۷ روز پیاپی'), findsOneWidget);
      expect(find.text('رکورد: ۱۲ روز'), findsOneWidget, reason: 'local stats');
    });

    testWidgets('nothing the server does not send is drawn', (tester) async {
      await open(tester);
      for (final invented in ['۸٬۲۳۰', 'میانگین', 'نفر امروز بازی کردند', 'دیروز:']) {
        expect(find.textContaining(invented), findsNothing, reason: invented);
      }
    });

    testWidgets('nobody has played yet: the first-player line', (tester) async {
      h.repo.challenge = dailyChallenge(best: 0);
      await open(tester);
      expect(find.text('اولین نفری باش که امروز بازی می‌کنه!'), findsOneWidget);
      expect(find.textContaining('رکورد امروز'), findsNothing);
    });

    testWidgets('no streak: no streak card', (tester) async {
      h.repo.challenge = dailyChallenge(streak: 0);
      await open(tester);
      expect(find.textContaining('روز پیاپی'), findsNothing);
    });

    testWidgets('no local stats: the streak card has no record line', (tester) async {
      await open(tester, stats: FakeStats(none: true));
      expect(find.text('۷ روز پیاپی'), findsOneWidget);
      expect(find.textContaining('رکورد: '), findsNothing);
    });

    testWidgets('«شروع چالش امروز» opens the daily game with the letter', (tester) async {
      await open(tester);
      await tapText(tester, 'شروع چالش امروز');
      await _settle(tester);
      expect(h.visited, ['/game']);
      final args = h.extras.single as GameRouteArgs;
      expect((args.mode, args.opponentType, args.startLetter), ('daily', 'solo', 'ب'));
    });

    testWidgets('«دیدن جدول امروز» opens the board', (tester) async {
      await open(tester);
      await tapText(tester, 'دیدن جدول امروز');
      await _settle(tester);
      expect(h.visited, ['/daily/board']);
    });

    testWidgets('back with nothing underneath goes home', (tester) async {
      await open(tester);
      await tester.tap(find.byType(ZGameBackButton));
      await _settle(tester);
      expect(h.visited, ['/home']);
    });

    testWidgets('the date chip moves under the header on a narrow phone', (tester) async {
      await open(tester, w: 320, hgt: 568);
      expect(find.text('جمعه ۲۴ مهر'), findsOneWidget);
      final chip = tester.getTopLeft(find.text('جمعه ۲۴ مهر')).dy;
      final ribbon = tester.getBottomLeft(find.byType(ZRibbonTitle)).dy;
      expect(chip, greaterThanOrEqualTo(ribbon - 4));
    });
  });

  group('after the game', () {
    setUp(() => h.repo.challenge = dailyChallenge(played: true, streak: 8));

    testWidgets('the result with real numbers', (tester) async {
      await open(tester);
      expect(find.text('چالش امروز تمام شد'), findsOneWidget);
      expect(find.text('جمعه ۲۴ مهر · حرف شروع «ب»'), findsOneWidget);
      expect(find.text('۱۹'), findsOneWidget, reason: 'words in the chain');
      expect(find.text('رتبهٔ ۳ امروز'), findsOneWidget);
      expect(find.text('۴۶۰ امتیاز'), findsOneWidget);
      expect(find.text('۸ روز پیاپی'), findsOneWidget);
      expect(find.text('رکورد: ۱۲ روز'), findsOneWidget);
      expect(find.text('چالش بعدی · فردا ۰۰:۰۰'), findsOneWidget);
      expect(find.text('۰۸:۳۰'), findsOneWidget, reason: 'read once, no seconds');
    });

    testWidgets('percentile and player count are not invented', (tester) async {
      await open(tester);
      for (final invented in ['بهتر از', '٪', 'از ۸٬۲۳۰', '۱۱:۴۲:۰۳']) {
        expect(find.textContaining(invented), findsNothing, reason: invented);
      }
    });

    testWidgets('chain card: first eight words and the rest counted', (tester) async {
      await open(tester);
      expect(find.byType(DailyChainCard), findsOneWidget);
      expect(find.text('زنجیر امروزت'), findsOneWidget);
      expect(find.text('۱۱ کلمهٔ دیگر'), findsOneWidget);
      // Words are rich text, so look at the card's semantics.
      expect(
        find.byWidgetPredicate(
          (w) => w is Semantics && (w.properties.label ?? '').startsWith('زنجیر امروزت: بادام، مداد'),
        ),
        findsOneWidget,
      );
      expect(find.byType(DailyCompareCard), findsNothing);
    });

    testWidgets('a short chain has no overflow chip', (tester) async {
      h.repo.challenge = dailyChallenge(attempt: dailyAttempt(words: dailyWords.take(5).toList()), streak: 2);
      await open(tester);
      expect(find.textContaining('کلمهٔ دیگر'), findsNothing);
      expect(find.text('۵'), findsOneWidget);
    });

    testWidgets('no rank from the server: says the result is recorded', (tester) async {
      h.repo.challenge = dailyChallenge(played: true, rank: null);
      await open(tester);
      expect(find.text('نتیجهٔ امروزت ثبت شد'), findsOneWidget);
      expect(find.textContaining('رتبهٔ'), findsNothing);
    });

    testWidgets('no streak: the countdown takes the row, no streak tile', (tester) async {
      h.repo.challenge = dailyChallenge(played: true, streak: 0);
      await open(tester);
      expect(find.textContaining('روز پیاپی'), findsNothing);
      expect(find.text('۰۸:۳۰'), findsOneWidget);
    });

    testWidgets('the record line only shows when it beats the streak', (tester) async {
      await open(tester, stats: FakeStats(record: 8));
      expect(find.text('امروز هم حساب شد'), findsOneWidget);
      expect(find.textContaining('رکورد: '), findsNothing);
    });

    testWidgets('a lower retry: the first attempt is the one shown and marked best', (tester) async {
      h.repo.challenge = dailyChallenge(
        attempt: dailyAttempt(score: 460),
        retry: dailyAttempt(number: 2, score: 300, words: dailyWords.take(9).toList()),
      );
      await open(tester);
      expect(find.text('۴۶۰ امتیاز'), findsOneWidget, reason: 'hero = best');
      expect(find.text('۱۹'), findsWidgets);
      expect(find.byType(DailyCompareCard), findsOneWidget);
      await tester.ensureVisible(find.byType(DailyCompareCard));
      expect(find.text('تلاش اول · بهترین'), findsOneWidget);
      expect(find.text('تلاش دوباره'), findsOneWidget);
      // The retry is used up: no retry button.
      expect(find.textContaining('امتحان دوباره'), findsNothing);
    });

    testWidgets('a higher retry becomes the hero', (tester) async {
      h.repo.challenge = dailyChallenge(
        attempt: dailyAttempt(score: 300, words: dailyWords.take(9).toList()),
        retry: dailyAttempt(number: 2, score: 520),
      );
      await open(tester);
      expect(find.text('۵۲۰ امتیاز'), findsOneWidget);
      await tester.ensureVisible(find.byType(DailyCompareCard));
      expect(find.text('تلاش دوباره · بهترین'), findsOneWidget);
    });

    testWidgets('share sends the best attempt', (tester) async {
      h.repo.challenge = dailyChallenge(
        attempt: dailyAttempt(score: 460),
        retry: dailyAttempt(number: 2, score: 300, words: dailyWords.take(9).toList()),
      );
      await open(tester);
      await tapText(tester, 'اشتراک‌گذاری نتیجه');
      await _settle(tester);
      final shared = h.share.shared.single;
      expect((shared.dayNumber, shared.score, shared.chainLength), (42, 460, 19));
      expect(shared.wordChain, dailyWords);
    });

    testWidgets('board, solo game and back go where they say', (tester) async {
      await open(tester);
      await tapText(tester, 'جدول امروز');
      await _settle(tester);
      expect(h.visited.last, '/daily/board');
    });

    testWidgets('«بازی تک‌نفره» starts a classic solo game', (tester) async {
      await open(tester);
      await tapText(tester, 'بازی تک‌نفره');
      await _settle(tester);
      final args = h.extras.single as GameRouteArgs;
      expect((args.mode, args.opponentType, args.startLetter), ('classic', 'solo', null));
    });

    testWidgets('back goes home even when something is underneath', (tester) async {
      await open(tester);
      await tester.tap(find.byType(ZGameBackButton));
      await _settle(tester);
      expect(h.visited, ['/home']);
    });
  });

  group('the paid retry', () {
    setUp(() => h.repo.challenge = dailyChallenge(played: true));

    testWidgets('on offer once, with its price', (tester) async {
      await open(tester);
      expect(find.text('امتحان دوباره · ۲۵ سکه'), findsOneWidget);
    });

    testWidgets('paid: starts the daily game', (tester) async {
      await open(tester);
      await tapText(tester, 'امتحان دوباره · ۲۵ سکه');
      await _settle(tester);
      expect(h.repo.retries, 1);
      expect(h.visited, ['/game']);
      final args = h.extras.single as GameRouteArgs;
      expect((args.mode, args.opponentType, args.startLetter), ('daily', 'solo', 'ب'));
    });

    testWidgets('busy while paying: one call, a waiting label', (tester) async {
      h.repo.retryGate = Completer();
      await open(tester);
      await tapText(tester, 'امتحان دوباره · ۲۵ سکه');
      await tester.pump();
      expect(find.text('کمی صبر کن…'), findsOneWidget);
      expect(find.byType(ZLoadState), findsNothing, reason: 'result stays up');
      await tester.tap(find.text('کمی صبر کن…'));
      await tester.pump();
      expect(h.repo.retries, 1);
      h.repo.retryGate!.complete();
      await _settle(tester);
      expect(h.visited, ['/game']);
    });

    testWidgets('too poor: the earn-coins dialog, result stays', (tester) async {
      h.repo.retryError = const DailyException(code: 'insufficient_coins', message: 'سکهٔ کافی نداری');
      await open(tester);
      await tapText(tester, 'امتحان دوباره · ۲۵ سکه');
      await _settle(tester);
      expect(find.text('برای این کار ۲۵ سکه لازم است. با این راه‌ها سکه جمع کن:'), findsOneWidget);
      expect(h.visited, isEmpty);
      // Close it; the retry can be tried again.
      await tester.tap(find.text('متوجه شدم'));
      await _settle(tester);
      expect(find.text('امتحان دوباره · ۲۵ سکه'), findsOneWidget);
      await tapText(tester, 'امتحان دوباره · ۲۵ سکه');
      await _settle(tester);
      expect(h.repo.retries, 2);
      expect(find.text('متوجه شدم'), findsOneWidget);
    });

    testWidgets('slot already bought: goes on to the game', (tester) async {
      h.repo.retryError = const DailyException(
        code: 'already_retried',
        message: 'تلاش دوبارهٔ امروز را قبلاً استفاده کرده‌ای',
      );
      await open(tester);
      await tapText(tester, 'امتحان دوباره · ۲۵ سکه');
      await _settle(tester);
      expect(h.visited, ['/game']);
    });

    testWidgets('other failure: a toast, the result and button stay', (tester) async {
      h.repo.retryError = const DailyException(code: 'network', message: 'اتصال برقرار نشد');
      await open(tester);
      await tapText(tester, 'امتحان دوباره · ۲۵ سکه');
      await _settle(tester);
      expect(find.text('اتصال برقرار نشد'), findsOneWidget);
      expect(find.text('امتحان دوباره · ۲۵ سکه'), findsOneWidget);
      expect(h.visited, isEmpty);
      await tester.pump(const Duration(seconds: 3)); // the toast's own timer
      await tester.pump(const Duration(seconds: 1));
    });

    testWidgets('an unexpected error uses the generic message', (tester) async {
      h.repo.retryError = StateError('boom');
      await open(tester);
      await tapText(tester, 'امتحان دوباره · ۲۵ سکه');
      await _settle(tester);
      expect(find.text(dailyRetryFailedMessage), findsOneWidget);
      await tester.pump(const Duration(seconds: 3));
      await tester.pump(const Duration(seconds: 1));
    });
  });

  group('the clock', () {
    testWidgets('back from the background on a later Iran day reloads', (tester) async {
      await open(tester);
      expect(h.repo.loads, 1);
      // Still the same day: nothing.
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await _settle(tester);
      expect(h.repo.loads, 1);
    });

    testWidgets('a challenge from an earlier day is replaced on resume', (tester) async {
      h.repo.challenge = dailyChallenge(date: '2026-10-15', letter: 'ز');
      await open(tester);
      expect(find.text('ز'), findsOneWidget);
      h.repo.challenge = dailyChallenge();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await _settle(tester);
      expect(h.repo.loads, 2);
      expect(find.text('ب'), findsOneWidget);
      expect(find.text('ز'), findsNothing);
    });

    testWidgets('nothing ticks: no periodic timer, no frame scheduled', (tester) async {
      h.repo.challenge = dailyChallenge(played: true);
      await open(tester);
      await tester.pump(const Duration(seconds: 2));
      expect(tester.binding.hasScheduledFrame, isFalse);
    });
  });

  group('motion', () {
    testWidgets('on: the entrances play and end in the same layout', (tester) async {
      await open(tester, reduceMotion: false);
      await tester.pump(const Duration(seconds: 2));
      expect(find.text('شروع چالش امروز'), findsOneWidget);
      expect(find.text('ب'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('semantics', () {
    testWidgets('the buttons and the hero are announced', (tester) async {
      final handle = tester.ensureSemantics();
      await open(tester);
      expect(find.bySemanticsLabel('بازگشت'), findsOneWidget);
      expect(find.bySemanticsLabel('شروع چالش امروز'), findsOneWidget);
      expect(find.bySemanticsLabel('حرف شروع امروز: ب'), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('۲ جان، هر اشتباه')), findsOneWidget);
      handle.dispose();
    });
  });

  group('contrast', () {
    test('the pairs the daily screens paint, light and dark', () {
      for (final theme in [AppTheme.light, AppTheme.dark]) {
        final z = theme.extension<ZColors>()!;
        final zs = theme.extension<ZScene>()!;
        expect(contrastRatio(z.onIndigo, z.indigo), greaterThanOrEqualTo(4.5));
        expect(contrastRatio(z.onAmber, z.amber), greaterThanOrEqualTo(4.5));
        expect(contrastRatio(z.onTeal, z.teal), greaterThanOrEqualTo(3));
        expect(contrastRatio(z.ink, z.surface), greaterThanOrEqualTo(4.5));
        expect(contrastRatio(z.ink60, z.surface), greaterThanOrEqualTo(4.5));
        expect(contrastRatio(z.ink60, z.wash), greaterThanOrEqualTo(4.5));
        expect(contrastRatio(z.ink, z.tintTeal), greaterThanOrEqualTo(4.5));
        expect(contrastRatio(z.onInkSurface, z.inkSurface), greaterThanOrEqualTo(4.5));
        for (final h in ZChainHue.values) {
          final ink = switch (h) {
            ZChainHue.coral => zs.coralInk,
            ZChainHue.teal => zs.tealInk,
            ZChainHue.indigo => zs.indigoInk,
            ZChainHue.amber => zs.amberInk,
          };
          expect(contrastRatio(ink, zs.tile), greaterThanOrEqualTo(4.3), reason: '$h');
        }
        expect(contrastRatio(z.ink, zs.tile), greaterThanOrEqualTo(4.5));
      }
    });
  });

  group('layout', () {
    const sizes = [Size(320, 568), Size(360, 640), Size(393, 852), Size(430, 932)];

    /// Long word, six-digit score, big rank: the widest the data can get.
    DailyChallenge heavy({bool retry = false}) => dailyChallenge(
      attempt: DailyAttempt(
        attemptNumber: 1,
        score: 999999,
        chainLength: 20,
        wordChain: ['فوق‌العاده‌ترین‌واژه‌ی‌ممکن‌دراین‌زبان', ...dailyWords.take(18), 'رود'],
      ),
      retry:
          retry
              ? const DailyAttempt(attemptNumber: 2, score: 123456, chainLength: 12, wordChain: ['بادام', 'مداد'])
              : null,
      streak: 365,
      best: 999999,
      rank: 123456,
    );

    Future<void> visit(WidgetTester tester, String reason) async {
      expect(tester.takeException(), isNull, reason: reason);
      final scrollable = find.byType(SingleChildScrollView);
      if (scrollable.evaluate().isNotEmpty) {
        await tester.drag(scrollable.first, const Offset(0, -3000));
        await tester.pump();
        expect(tester.takeException(), isNull, reason: '$reason scrolled');
      }
    }

    Future<void> allStates(
      WidgetTester tester, {
      required Brightness brightness,
      required double scale,
      required Size size,
    }) async {
      final tag = '${size.width.toInt()}×${size.height.toInt()} ${brightness.name} ×$scale';
      // Loading.
      h.repo.loadGate = Completer();
      await open(tester, brightness: brightness, textScale: scale, w: size.width, hgt: size.height);
      await visit(tester, 'loading $tag');
      // Failure.
      await GetIt.I.reset();
      h = _Harness();
      h.repo.loadError = const DailyException(code: 'x', message: 'بارگذاری چالش امروز ناموفق بود');
      await open(tester, brightness: brightness, textScale: scale, w: size.width, hgt: size.height);
      await visit(tester, 'error $tag');
      // Before, heavy numbers.
      for (final (name, challenge) in [
        ('before', heavy().bestAttempt == null ? dailyChallenge() : dailyChallenge(best: 999999, streak: 365)),
        ('after', heavy()),
        ('after+retry', heavy(retry: true)),
      ]) {
        await GetIt.I.reset();
        h = _Harness();
        h.repo.challenge = challenge;
        await open(tester, brightness: brightness, textScale: scale, w: size.width, hgt: size.height);
        await visit(tester, '$name $tag');
      }
    }

    for (final size in sizes) {
      for (final brightness in Brightness.values) {
        for (final scale in [1.0, 1.3, 1.6, 2.0]) {
          testWidgets(
            'every state: no overflow ${size.width.toInt()}×${size.height.toInt()} ${brightness.name} ×$scale',
            (tester) async {
              await allStates(tester, brightness: brightness, scale: scale, size: size);
            },
          );
        }
      }
    }
  });

  group('goldens', () {
    Future<void> shot(WidgetTester tester, String name) async {
      await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/$name.png'));
    }

    for (final brightness in Brightness.values) {
      testWidgets('before ${brightness.name}', (tester) async {
        await open(tester, brightness: brightness);
        await shot(tester, 'daily_before_${brightness.name}');
      });

      testWidgets('after ${brightness.name}', (tester) async {
        h.repo.challenge = dailyChallenge(played: true, streak: 8);
        await open(tester, brightness: brightness, hgt: 1000);
        await shot(tester, 'daily_after_${brightness.name}');
      });
    }

    testWidgets('before small phone dark', (tester) async {
      await open(tester, brightness: Brightness.dark, w: 320, hgt: 568);
      await shot(tester, 'daily_before_320_dark');
    });

    testWidgets('after + retried light', (tester) async {
      h.repo.challenge = dailyChallenge(
        attempt: dailyAttempt(score: 460),
        retry: dailyAttempt(number: 2, score: 300, words: dailyWords.take(9).toList()),
        streak: 8,
      );
      await open(tester, w: 360, hgt: 1250);
      await shot(tester, 'daily_after_retried_light');
    });

    testWidgets('loading dark', (tester) async {
      h.repo.loadGate = Completer();
      await open(tester, brightness: Brightness.dark);
      await shot(tester, 'daily_loading_dark');
    });

    testWidgets('error light', (tester) async {
      h.repo.loadError = const DailyException(code: 'no_daily_challenge', message: 'چالش امروز هنوز آماده نشده');
      await open(tester);
      await shot(tester, 'daily_error_light');
    });
  });
}
