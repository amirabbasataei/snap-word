import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:wordchain/core/services/ad_service.dart';
import 'package:wordchain/core/theme/app_theme.dart';
import 'package:wordchain/core/theme/app_tokens.dart';
import 'package:wordchain/core/utils/error_messages.dart';
import 'package:wordchain/core/widgets/z_empty_state.dart';
import 'package:wordchain/core/widgets/z_hud_coin_pill.dart';
import 'package:wordchain/core/widgets/z_load_state.dart';
import 'package:wordchain/core/widgets/z_state_card.dart';
import 'package:wordchain/features/auth/cubit/auth_cubit.dart';
import 'package:wordchain/features/game/data/game_constants.dart';
import 'package:wordchain/features/game/data/game_repository.dart';
import 'package:wordchain/features/game/view/widgets/z_game_hud.dart';
import 'package:wordchain/features/rewards/cubit/rewards_cubit.dart';
import 'package:wordchain/features/rewards/data/rewards_repository.dart';
import 'package:wordchain/features/rewards/view/rewards_screen.dart';
import 'package:wordchain/features/rewards/view/widgets/reward_format.dart';
import 'package:wordchain/features/rewards/view/widgets/reward_tile.dart';
import 'package:wordchain/features/rewards/view/widgets/rewards_summary.dart';

import '../../helpers/contrast.dart';
import '../../helpers/z_test_app.dart';
import 'rewards_fakes.dart';

class _Harness {
  late FakeRewardsAuth auth;
  late FakeRewardsRepo repo;
  late FakeRewardedAds ads;
  final gameRepo = FakeAdGameRepo();
  final visited = <String>[];

  Future<void> register({
    List<RewardItem>? items,
    bool guest = false,
    bool adsOn = false,
  }) async {
    auth = FakeRewardsAuth(guest: guest);
    repo = FakeRewardsRepo(items ?? sampleRewards());
    ads = FakeRewardedAds(rewardedEnabled: adsOn);
    GetIt.I
      ..registerSingleton<AuthCubit>(auth)
      ..registerSingleton<RewardsRepository>(repo)
      ..registerSingleton<RewardsCubit>(RewardsCubit(repo: repo, auth: auth))
      ..registerSingleton<AdService>(ads)
      ..registerSingleton<GameRepository>(gameRepo);
  }

  Widget app({
    Brightness brightness = Brightness.light,
    bool reduceMotion = true,
    double textScale = 1,
  }) {
    final router = GoRouter(
      initialLocation: '/home',
      routes: [
        GoRoute(
          path: '/home',
          builder:
              (context, _) => Scaffold(
                body: TextButton(
                  onPressed: () => context.push('/rewards'),
                  child: const Text('open'),
                ),
              ),
        ),
        GoRoute(path: '/rewards', builder: (_, _) => const RewardsScreen()),
      ],
    );
    return MaterialApp.router(
      debugShowCheckedModeBanner: false,
      routerConfig: router,
      theme: brightness == Brightness.light ? AppTheme.light : AppTheme.dark,
      builder:
          (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              disableAnimations: reduceMotion,
              textScaler: TextScaler.linear(textScale),
            ),
            child: Directionality(
              textDirection: TextDirection.rtl,
              child: child!,
            ),
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

  /// Opens the screen the way the home gift icon does (a pushed route).
  Future<void> open(
    WidgetTester tester, {
    Brightness brightness = Brightness.light,
    bool reduceMotion = true,
    double textScale = 1,
    double w = 393,
    double hgt = 852,
    List<RewardItem>? items,
    bool guest = false,
    bool adsOn = false,
    bool register = true,
  }) async {
    _size(tester, w, hgt);
    if (register) await h.register(items: items, guest: guest, adsOn: adsOn);
    await tester.pumpWidget(
      h.app(
        brightness: brightness,
        reduceMotion: reduceMotion,
        textScale: textScale,
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await _settle(tester);
  }

  Future<void> tapText(WidgetTester tester, String text) async {
    final finder = find.text(text).first;
    await tester.ensureVisible(finder);
    await tester.pump();
    await tester.tap(finder);
    await tester.pump();
  }

  /// Lets a toast (2.6 s) come and go so no timer outlives the test.
  Future<void> drainToast(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 4));
    await tester.pump(const Duration(seconds: 1));
  }

  group('loading, failure, empty', () {
    testWidgets('loading: the mascot card, no spinner', (tester) async {
      await h.register();
      h.repo.fetchGate = Completer();
      await open(tester, register: false);
      expect(find.byType(ZLoadState), findsOneWidget);
      expect(find.byType(ZStateCard), findsOneWidget);
      expect(find.text(ZLoadState.loadingLabel), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.byType(RewardTile), findsNothing);
      expect(find.text('هدیه‌ای نداری'), findsNothing);
      expect(find.byType(ZGameBackButton), findsOneWidget);
      h.repo.fetchGate!.complete();
      await _settle(tester);
      expect(find.byType(ZLoadState), findsNothing);
    });

    testWidgets('failed first load: Persian message, retry reloads', (
      tester,
    ) async {
      await h.register();
      h.repo.fetchError = const RewardsException(networkErrorCode);
      await open(tester, register: false, hgt: 1600);
      expect(find.text(networkErrorMessage), findsOneWidget);
      expect(find.text(ZLoadState.retryLabel), findsOneWidget);
      expect(find.text('هدیه‌ای نداری'), findsNothing);
      expect(h.repo.fetches, 1);

      h.repo.fetchError = null;
      await tapText(tester, ZLoadState.retryLabel);
      await _settle(tester);
      expect(h.repo.fetches, 2);
      expect(find.byType(RewardTile), findsNWidgets(7));
      expect(find.text(ZLoadState.retryLabel), findsNothing);
    });

    testWidgets('an unknown error code shows the generic Persian text', (
      tester,
    ) async {
      await h.register();
      h.repo.fetchError = const RewardsException('weird_code');
      await open(tester, register: false);
      expect(find.text(genericErrorMessage), findsOneWidget);
    });

    testWidgets('a failed refresh keeps the list that was loaded', (
      tester,
    ) async {
      await open(tester, hgt: 1600);
      expect(find.byType(RewardTile), findsNWidgets(7));
      h.repo.fetchError = const RewardsException(networkErrorCode);
      await refreshRewards();
      await _settle(tester);
      expect(find.byType(RewardTile), findsNWidgets(7));
      expect(find.byType(ZLoadState), findsNothing);
    });

    testWidgets('empty list: the empty state, no summary', (tester) async {
      await open(tester, items: const []);
      expect(find.byType(ZEmptyState), findsOneWidget);
      expect(find.text('هدیه‌ای نداری'), findsOneWidget);
      expect(find.byType(RewardsSummary), findsNothing);
      expect(find.byType(RewardTile), findsNothing);
    });

    testWidgets('a signed-out player gets the empty state, not a spinner', (
      tester,
    ) async {
      await open(tester, guest: true);
      expect(h.repo.fetches, 0);
      expect(find.text('هدیه‌ای نداری'), findsOneWidget);
      expect(find.byType(ZLoadState), findsNothing);
    });
  });

  group('the list', () {
    testWidgets('header: back button, title, the live server balance', (
      tester,
    ) async {
      await open(tester);
      expect(find.byType(ZGameBackButton), findsOneWidget);
      expect(find.text('جایزه‌ها'), findsOneWidget);
      // GET /rewards carries the live balance (90 in the fake).
      expect(find.byType(ZHudCoinPill), findsOneWidget);
      expect(find.text('۹۰'), findsOneWidget);
    });

    testWidgets('back pops to where the player came from', (tester) async {
      await open(tester);
      await tester.tap(find.byType(ZGameBackButton));
      await _settle(tester);
      expect(find.text('open'), findsOneWidget);
      expect(find.byType(RewardsScreen), findsNothing);
    });

    testWidgets('summary counts the unclaimed prizes and their coins', (
      tester,
    ) async {
      await open(tester);
      expect(find.text('جایزه‌های آمادهٔ دریافت'), findsOneWidget);
      // 6 unclaimed: 10 + 300 + 100 + 10 + 50 + 200.
      expect(find.text('۶'), findsOneWidget);
      expect(find.text('روی هم ۶۷۰ سکه منتظر توست'), findsOneWidget);
    });

    testWidgets('nothing unclaimed: says so, and that all are taken', (
      tester,
    ) async {
      await open(
        tester,
        items: [reward('x', 'streak', detail: '3', claimed: true)],
      );
      expect(find.text('فعلاً جایزه‌ای آماده نیست'), findsOneWidget);
      expect(find.text('همهٔ جایزه‌هایت را گرفته‌ای'), findsOneWidget);
      expect(find.text('۰'), findsOneWidget);
    });

    testWidgets('unclaimed first, the claimed one last, server order kept', (
      tester,
    ) async {
      await open(tester, hgt: 1600);
      final tiles =
          tester.widgetList<RewardTile>(find.byType(RewardTile)).toList();
      expect(tiles.map((t) => t.item.id), ['a', 'c', 'd', 'e', 'f', 'g', 'b']);
      expect(tiles.last.item.claimed, isTrue);
    });

    testWidgets('each kind has its own Persian copy and disc glyph', (
      tester,
    ) async {
      await open(tester, hgt: 1600);
      for (final text in [
        'پاداش ورود روزانه',
        'پاداش روزهای پیاپی',
        '۷ روز پیاپی بازی کردی! ۱۰۰ سکه هدیه بگیر.',
        'در جدول هفتگی رتبهٔ ۲ شدی! ۳۰۰ سکه هدیه بگیر.',
        'در چالش دیروز رتبهٔ ۱ شدی! ۱۰۰ سکه هدیه بگیر.',
        'برای شرکت در چالش دیروز ۱۰ سکه هدیه بگیر.',
        'تیم زنجیر برایت ۲۰۰ سکه هدیه فرستاده است.',
        'برای سر زدن امروز ۱۰ سکه هدیه بگیر.',
      ]) {
        expect(find.text(text), findsOneWidget, reason: text);
      }
      expect(
        find.textContaining('سارا'),
        findsOneWidget,
        reason: 'referral names the friend',
      );
      expect(find.text('هدیهٔ دعوت'), findsOneWidget);
      for (final glyph in ['و', '۷', '۲', '۱', 'چ', '+', 'ز']) {
        expect(find.text(glyph), findsWidgets, reason: glyph);
      }
    });

    testWidgets('claimed prize shows «گرفتی» instead of a button', (
      tester,
    ) async {
      await open(tester, hgt: 1600);
      expect(find.text('گرفتی'), findsOneWidget);
      expect(find.text('دریافت'), findsNWidgets(6));
    });

    testWidgets('only real data: no progress, no catalogue counts', (
      tester,
    ) async {
      await open(tester, hgt: 1600);
      for (final invented in ['٪', ' / ', 'از ۶ جایزه', 'قفل']) {
        expect(find.textContaining(invented), findsNothing, reason: invented);
      }
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });
  });

  group('claiming', () {
    testWidgets('claim: server call, toast, tile claimed, balance + summary', (
      tester,
    ) async {
      await open(tester, hgt: 1600);
      final first = find.byType(RewardTile).first;
      await tester.tap(
        find.descendant(of: first, matching: find.text('دریافت')),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(h.repo.claimed, ['a']);
      // The id is the one on the tile: the daily-login prize, 10 coins.
      expect(find.text(coinsAwardedMessage(10)), findsOneWidget);
      expect(find.text('گرفتی'), findsNWidgets(2));
      expect(find.text('دریافت'), findsNWidgets(5));
      expect(find.text('۵'), findsOneWidget);
      expect(find.text('روی هم ۶۶۰ سکه منتظر توست'), findsOneWidget);
      // 90 + 10, credited on the live balance.
      expect(find.text('۱۰۰'), findsOneWidget);
      expect((h.auth.state as AuthAuthenticated).coins, 100);
      await drainToast(tester);
    });

    testWidgets('the claimed prize moves below the unclaimed ones', (
      tester,
    ) async {
      await open(tester, hgt: 1600);
      await tester.tap(
        find.descendant(
          of: find.byType(RewardTile).first,
          matching: find.text('دریافت'),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      final ids =
          tester
              .widgetList<RewardTile>(find.byType(RewardTile))
              .map((t) => t.item.id)
              .toList();
      expect(ids, ['c', 'd', 'e', 'f', 'g', 'a', 'b']);
      await drainToast(tester);
    });

    testWidgets(
      'while the claim runs: «کمی صبر کن…», a second tap is ignored',
      (tester) async {
        h.repo = FakeRewardsRepo(sampleRewards());
        await open(tester, hgt: 1600);
        h.repo.claimGate = Completer();
        final button = find.descendant(
          of: find.byType(RewardTile).first,
          matching: find.text('دریافت'),
        );
        await tester.tap(button);
        await tester.pump();
        expect(find.text('کمی صبر کن…'), findsOneWidget);
        expect(find.text('دریافت'), findsNWidgets(5));
        expect(h.repo.claimed, isEmpty);

        await tester.tap(find.text('کمی صبر کن…'), warnIfMissed: false);
        await tester.pump();
        h.repo.claimGate!.complete();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        expect(h.repo.claimed, ['a'], reason: 'claimed exactly once');
        expect(find.text('کمی صبر کن…'), findsNothing);
        await drainToast(tester);
      },
    );

    testWidgets('already claimed elsewhere: resync, no error toast', (
      tester,
    ) async {
      await open(tester, hgt: 1600);
      final before = h.repo.fetches;
      h.repo.claimError = const RewardsException('reward_not_found');
      h.repo.items = [
        for (final i in sampleRewards()) i.id == 'a' ? i.asClaimed() : i,
      ];
      await tester.tap(
        find.descendant(
          of: find.byType(RewardTile).first,
          matching: find.text('دریافت'),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(h.repo.fetches, before + 1);
      expect(find.text(errorMessageFor('reward_not_found')), findsNothing);
      expect(find.text('گرفتی'), findsNWidgets(2));
    });

    testWidgets('any other failure: Persian toast, the button stays', (
      tester,
    ) async {
      await open(tester, hgt: 1600);
      h.repo.claimError = const RewardsException(networkErrorCode);
      await tester.tap(
        find.descendant(
          of: find.byType(RewardTile).first,
          matching: find.text('دریافت'),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text(networkErrorMessage), findsOneWidget);
      expect(find.text('دریافت'), findsNWidgets(6));
      expect((h.auth.state as AuthAuthenticated).coins, 90);
      await drainToast(tester);
    });

    testWidgets('the balance pill pops when the balance grows (animated)', (
      tester,
    ) async {
      await open(tester, reduceMotion: false, hgt: 1600);
      await tester.tap(
        find.descendant(
          of: find.byType(RewardTile).first,
          matching: find.text('دریافت'),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      final scale = tester.widget<ScaleTransition>(
        find.ancestor(
          of: find.byType(ZHudCoinPill),
          matching: find.byType(ScaleTransition),
        ),
      );
      expect(scale.scale.value, greaterThan(1));
      await tester.pump(const Duration(milliseconds: 500));
      expect(scale.scale.value, closeTo(1, 1e-6));
      await drainToast(tester);
    });
  });

  group('free coins (rewarded ad)', () {
    testWidgets('hidden unless ads are on and the player is signed in', (
      tester,
    ) async {
      await open(tester);
      expect(find.text('سکهٔ رایگان'), findsNothing);
    });

    testWidgets('shown with the real coin amount; a watched ad credits it', (
      tester,
    ) async {
      await open(tester, adsOn: true, hgt: 1600);
      expect(find.text('سکهٔ رایگان'), findsOneWidget);
      expect(
        find.text(
          'با دیدن یک تبلیغ کوتاه ${GameConstants.rewardedAdCoins.toString().replaceAll('2', '۲').replaceAll('0', '۰')} سکه هدیه بگیر.',
        ),
        findsOneWidget,
      );
      await tapText(tester, 'دیدن تبلیغ');
      await tester.pump(const Duration(milliseconds: 100));
      expect(h.ads.shown, 1);
      expect(
        find.text(coinsAwardedMessage(GameConstants.rewardedAdCoins)),
        findsOneWidget,
      );
      expect((h.auth.state as AuthAuthenticated).coins, 500);
      await drainToast(tester);
    });

    testWidgets('no ad available: says so in Persian, nothing credited', (
      tester,
    ) async {
      await open(tester, adsOn: true, hgt: 1600);
      h.ads.watched = false;
      await tapText(tester, 'دیدن تبلیغ');
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text(adUnavailableMessage), findsOneWidget);
      expect((h.auth.state as AuthAuthenticated).coins, 90);
      await drainToast(tester);
    });
  });

  group('semantics', () {
    testWidgets('a prize reads as one stop that claims on activation', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await open(tester, hgt: 1600);
      final first = tester.getSemantics(find.byType(RewardTile).first);
      expect(first.label, contains('پاداش ورود روزانه'));
      expect(first.label, contains('۱۰ سکه'));
      expect(first.label, contains('دریافت'));
      expect(first.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);

      final claimed = tester.getSemantics(find.byType(RewardTile).last);
      expect(claimed.label, contains('گرفتی'));
      expect(claimed.label, isNot(contains('دریافت')));
      expect(
        claimed.getSemanticsData().hasAction(SemanticsAction.tap),
        isFalse,
      );
      handle.dispose();
    });

    testWidgets('the title is a header', (tester) async {
      final handle = tester.ensureSemantics();
      await open(tester);
      expect(
        tester.getSemantics(find.text('جایزه‌ها')).flagsCollection.isHeader,
        isTrue,
      );
      handle.dispose();
    });
  });

  group('contrast', () {
    for (final theme in [AppTheme.light, AppTheme.dark]) {
      final z = theme.extension<ZColors>()!;
      final name = theme == AppTheme.light ? 'light' : 'dark';
      test('disc glyphs and summary text are readable ($name)', () {
        for (final (fill, on) in [
          (z.amber, z.onAmber),
          (z.indigo, z.onIndigo),
          (z.teal, z.onTeal),
          (z.coral, z.onCoral),
        ]) {
          // Glyphs are 18–24dp w900: large text, 3:1.
          expect(contrastRatio(fill, on), greaterThanOrEqualTo(3));
        }
        expect(contrastRatio(z.amber, z.onAmber), greaterThanOrEqualTo(4.5));
        expect(contrastRatio(z.surface, z.ink60), greaterThanOrEqualTo(4.5));
      });
    }
  });

  group('reward_format', () {
    test('sort keeps each group in order', () {
      final sorted = sortRewards(sampleRewards());
      expect(sorted.map((i) => i.id), ['a', 'c', 'd', 'e', 'f', 'g', 'b']);
    });

    test('readyCoins sums only unclaimed prizes', () {
      expect(readyCoins(sampleRewards()), 670);
      expect(readyCoins(const []), 0);
    });

    test('an invite without a name falls back to «دوستت»', () {
      final face = rewardFace(reward('x', 'referral_reward', coins: 50));
      expect(face.body, contains('دوستت'));
    });

    test('an unknown kind is read as an invite (as before)', () {
      expect(rewardFace(reward('x', 'something_new')).title, 'هدیهٔ دعوت');
    });
  });

  group('layout', () {
    const sizes = [
      Size(320, 568),
      Size(360, 640),
      Size(393, 852),
      Size(430, 932),
    ];

    for (final size in sizes) {
      for (final brightness in Brightness.values) {
        for (final scale in [1.0, 1.3, 1.6, 2.0]) {
          testWidgets(
            'every state: no overflow ${size.width.toInt()}×${size.height.toInt()} ${brightness.name} ×$scale',
            (tester) async {
              final states = <String, Future<void> Function()>{
                'list+ads': () async {
                  await open(
                    tester,
                    adsOn: true,
                    brightness: brightness,
                    textScale: scale,
                    w: size.width,
                    hgt: size.height,
                  );
                },
                'list long names': () async {
                  await open(
                    tester,
                    items: [
                      reward(
                        'n',
                        'referral_reward',
                        detail: 'a_very_long_latin_username_32chars_xx',
                        coins: 1234567,
                      ),
                      reward('m', 'streak', detail: '365', coins: 500),
                      reward('o', 'admin_gift', coins: 2000, claimed: true),
                    ],
                    brightness: brightness,
                    textScale: scale,
                    w: size.width,
                    hgt: size.height,
                  );
                },
                'empty': () async {
                  await open(
                    tester,
                    items: const [],
                    brightness: brightness,
                    textScale: scale,
                    w: size.width,
                    hgt: size.height,
                  );
                },
                'error': () async {
                  await h.register();
                  h.repo.fetchError = const RewardsException(networkErrorCode);
                  await open(
                    tester,
                    register: false,
                    brightness: brightness,
                    textScale: scale,
                    w: size.width,
                    hgt: size.height,
                  );
                },
                'loading': () async {
                  await h.register();
                  h.repo.fetchGate = Completer();
                  await open(
                    tester,
                    register: false,
                    brightness: brightness,
                    textScale: scale,
                    w: size.width,
                    hgt: size.height,
                  );
                },
              };
              for (final entry in states.entries) {
                await GetIt.I.reset();
                h = _Harness();
                await entry.value();
                final reason =
                    '${entry.key} ${size.width}×${size.height} ×$scale';
                expect(tester.takeException(), isNull, reason: reason);
                final scroll = find.byType(Scrollable);
                if (scroll.evaluate().isNotEmpty) {
                  await tester.drag(scroll.first, const Offset(0, -3000));
                  await tester.pump();
                  expect(
                    tester.takeException(),
                    isNull,
                    reason: '$reason scrolled',
                  );
                }
              }
            },
          );
        }
      }
    }
  });

  group('goldens', () {
    Future<void> shot(WidgetTester tester, String name) async {
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/$name.png'),
      );
    }

    for (final brightness in Brightness.values) {
      testWidgets('list ${brightness.name}', (tester) async {
        await open(tester, brightness: brightness, hgt: 1250);
        await shot(tester, 'rewards_list_${brightness.name}');
      });
    }

    testWidgets('list small phone dark', (tester) async {
      await open(
        tester,
        brightness: Brightness.dark,
        w: 320,
        hgt: 568,
        adsOn: true,
      );
      await shot(tester, 'rewards_list_320_dark');
    });

    testWidgets('empty light', (tester) async {
      await open(tester, items: const []);
      await shot(tester, 'rewards_empty_light');
    });

    testWidgets('loading dark', (tester) async {
      await h.register();
      h.repo.fetchGate = Completer();
      await open(tester, brightness: Brightness.dark, register: false);
      await shot(tester, 'rewards_loading_dark');
    });

    testWidgets('error light', (tester) async {
      await h.register();
      h.repo.fetchError = const RewardsException(networkErrorCode);
      await open(tester, register: false);
      await shot(tester, 'rewards_error_light');
    });
  });
}

Future<void> refreshRewards() => GetIt.I<RewardsCubit>().refresh();
