import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:wordchain/core/router/app_router.dart';
import 'package:wordchain/core/theme/app_scene_tokens.dart';
import 'package:wordchain/core/theme/app_tokens.dart';
import 'package:wordchain/features/auth/cubit/auth_cubit.dart';
import 'package:wordchain/features/game/data/game_constants.dart';
import 'package:wordchain/features/home/view/widgets/home_logo.dart';
import 'package:wordchain/features/splash/view/splash_screen.dart';
import 'package:wordchain/features/splash/view/widgets/splash_hero.dart';
import 'package:wordchain/features/splash/view/widgets/splash_timeline.dart';

import '../../helpers/contrast.dart';
import '../../helpers/z_test_app.dart';
import '../auth/auth_fakes.dart';

late FakeAuth auth;
late List<String> visited;

const _total = Duration(milliseconds: 3200);
const _hint = 'کلمهٔ قبلی';

/// The app's own `/splash` + redirect rule with plain stand-ins for the
/// pages a splash can hand over to.
GoRouter _router({Future<String?>? version}) {
  Widget page(String name) => Scaffold(body: Center(child: Text('page:$name')));
  return GoRouter(
    initialLocation: '/splash',
    redirect: (context, state) {
      final to = authRedirect(
        uri: state.uri,
        extra: state.extra,
        authState: auth.state,
      );
      visited.add(to ?? state.uri.toString());
      return to;
    },
    routes: [
      GoRoute(
        path: '/splash',
        builder: (_, _) => SplashScreen(version: version),
      ),
      GoRoute(path: '/home', builder: (_, _) => page('home')),
      GoRoute(path: '/friends', builder: (_, _) => page('friends')),
      GoRoute(path: '/login', builder: (_, _) => page('login')),
    ],
  );
}

Future<GoRouter> pumpSplash(
  WidgetTester tester, {
  Brightness brightness = Brightness.light,
  double textScale = 1,
  Size size = const Size(393, 852),
  bool reduceMotion = false,
  Future<String?>? version,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  visited = [];
  final router = _router(version: version);
  await tester.pumpWidget(
    loginApp(
      router,
      brightness: brightness,
      textScale: textScale,
      reduceMotion: reduceMotion,
    ),
  );
  return router;
}

String _path(GoRouter r) => r.routerDelegate.currentConfiguration.uri.path;

double _opacityOf(WidgetTester tester, Finder f) {
  final o = find.ancestor(of: f, matching: find.byType(Opacity));
  return tester.widget<Opacity>(o.first).opacity;
}

Finder get _hintText => find.textContaining(_hint, findRichText: true);
Finder get _tag => find.text(HomeLogo.tagline);

void main() {
  setUpAll(loadVazirmatn);

  test(
    'splashVersionLabel uses Persian digits and the build in parentheses',
    () {
      expect(splashVersionLabel('0.1.3+4'), 'نسخهٔ ۰٫۱٫۳ (۴)');
      expect(splashVersionLabel('1.0.0'), 'نسخهٔ ۱٫۰٫۰');
      expect(splashVersionLabel('2.5+'), 'نسخهٔ ۲٫۵');
    },
  );

  setUp(() => auth = FakeAuth());
  tearDown(() => auth.dispose());

  group('states', () {
    testWidgets(
      'start: the scene is up, the tagline and hint have not come in',
      (tester) async {
        final router = await pumpSplash(tester);
        expect(_path(router), '/splash');
        expect(find.byType(SplashHero), findsOneWidget);
        expect(_opacityOf(tester, _tag), 0, reason: 'tagline waits for 1.76 s');
        expect(_opacityOf(tester, _hintText), 0);
        await tester.pump(_total);
      },
    );

    testWidgets('mid-intro: still on the splash, tagline and hint arrive', (
      tester,
    ) async {
      final router = await pumpSplash(tester);
      await tester.pump(const Duration(milliseconds: 1000));
      expect(_path(router), '/splash');
      expect(_opacityOf(tester, _tag), 0);

      await tester.pump(const Duration(milliseconds: 1400));
      expect(_path(router), '/splash');
      expect(_opacityOf(tester, _tag), 1);
      expect(_opacityOf(tester, _hintText), 1);
      await tester.pump(_total);
    });

    testWidgets('the installed version is shown under the hint', (
      tester,
    ) async {
      await pumpSplash(
        tester,
        reduceMotion: true,
        version: Future.value('0.1.3+4'),
      );
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text('نسخهٔ ۰٫۱٫۳ (۴)'), findsOneWidget);
      await tester.pump(_total);
    });

    testWidgets('the canvas copy is there and nothing the app cannot back', (
      tester,
    ) async {
      await pumpSplash(tester, reduceMotion: true);
      await tester.pump(const Duration(milliseconds: 50));
      expect(_tag, findsOneWidget);
      expect(_hintText, findsOneWidget);
      expect(
        find.textContaining('نسخه'),
        findsNothing,
        reason: 'no version line when the platform cannot report one',
      );
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(find.textContaining('٪'), findsNothing);
      await tester.pump(_total);
    });

    testWidgets('screen readers get the wordmark, mascot, tagline and rule', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await pumpSplash(tester, reduceMotion: true);
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.bySemanticsLabel('زنجیر'), findsOneWidget);
      expect(find.bySemanticsLabel('شخصیت زنجیر'), findsOneWidget);
      expect(find.bySemanticsLabel(HomeLogo.tagline), findsOneWidget);
      handle.dispose();
      await tester.pump(_total);
    });
  });

  group('navigation', () {
    testWidgets('a guest goes to /home when the splash is over — not before', (
      tester,
    ) async {
      final router = await pumpSplash(tester);
      await tester.pump(_total - const Duration(milliseconds: 100));
      expect(_path(router), '/splash');

      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump(const Duration(milliseconds: 50));
      expect(_path(router), '/home');
      expect(find.text('page:home'), findsOneWidget);
      expect(visited, isNot(contains('/login')), reason: 'never a login gate');
    });

    testWidgets('a signed-in player goes to /home too', (tester) async {
      auth.emitState(
        const AuthAuthenticated(userId: 'u1', username: 'zanjir_1', coins: 340),
      );
      final router = await pumpSplash(tester);
      await tester.pump(_total);
      await tester.pump(const Duration(milliseconds: 50));
      expect(_path(router), '/home');
      expect(visited, isNot(contains('/login')));
    });

    testWidgets('it does not wait on auth: even a loading state continues', (
      tester,
    ) async {
      auth.emitState(const AuthLoading());
      final router = await pumpSplash(tester);
      await tester.pump(_total);
      await tester.pump(const Duration(milliseconds: 50));
      expect(_path(router), '/home');
    });

    testWidgets('a slow first frame does not stretch the splash', (
      tester,
    ) async {
      // A 1.2 s frame hitch (cold start doing work) is not added on top: the
      // controller counts from timestamps, so the intro stays 3.2 s long.
      final router = await pumpSplash(tester);
      await tester.pump(const Duration(milliseconds: 1200));
      await tester.pump(const Duration(milliseconds: 2100));
      await tester.pump(const Duration(milliseconds: 50));
      expect(_path(router), '/home');
    });

    testWidgets('back from the background past the end continues at once', (
      tester,
    ) async {
      final router = await pumpSplash(tester);
      await tester.pump(const Duration(milliseconds: 800));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump(const Duration(minutes: 5));
      await tester.pump(const Duration(milliseconds: 50));
      expect(_path(router), '/home');
      expect(tester.takeException(), isNull);
    });

    testWidgets('a push that routes elsewhere is not overridden', (
      tester,
    ) async {
      // A notification payload / challenge deep link can `go` away while the
      // splash plays; the splash is gone and must not pull the player Home.
      final router = await pumpSplash(tester);
      await tester.pump(const Duration(milliseconds: 600));
      router.go('/friends');
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump(const Duration(milliseconds: 50));
      expect(_path(router), '/friends');

      await tester.pump(_total);
      await tester.pump(const Duration(milliseconds: 50));
      expect(_path(router), '/friends');
      expect(tester.takeException(), isNull);
    });

    testWidgets('leaving early leaves no timer behind', (tester) async {
      final router = await pumpSplash(tester);
      await tester.pump(const Duration(milliseconds: 300));
      router.go('/login');
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.text('page:login'), findsOneWidget);
    });
  });

  group('reduced motion', () {
    testWidgets('shows the finished composition at once and holds it', (
      tester,
    ) async {
      final router = await pumpSplash(tester, reduceMotion: true);
      await tester.pump(const Duration(milliseconds: 50));
      expect(_opacityOf(tester, _tag), 1);
      expect(_opacityOf(tester, _hintText), 1);
      expect(_path(router), '/splash');

      await tester.pump(
        const Duration(milliseconds: GameConstants.splashReducedMs - 100),
      );
      expect(_path(router), '/splash');
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump(const Duration(milliseconds: 50));
      expect(_path(router), '/home');
    });

    testWidgets('is much shorter than the animated splash', (tester) async {
      expect(
        GameConstants.splashReducedMs,
        lessThan(SplashTimeline.totalMs.round() ~/ 2),
      );
    });
  });

  group('layout', () {
    const sizes = [
      Size(320, 568),
      Size(360, 640),
      Size(393, 852),
      Size(430, 932),
    ];
    const scales = [1.0, 1.3, 1.6, 2.0];

    for (final dark in [false, true]) {
      for (final size in sizes) {
        for (final scale in scales) {
          testWidgets('no overflow, hint clear of the tagline: '
              '${size.width.toInt()}x${size.height.toInt()} '
              '${dark ? 'dark' : 'light'} x$scale', (tester) async {
            await pumpSplash(
              tester,
              size: size,
              textScale: scale,
              brightness: dark ? Brightness.dark : Brightness.light,
              reduceMotion: true,
            );
            await tester.pump(const Duration(milliseconds: 50));
            expect(tester.takeException(), isNull);

            final screen = Offset.zero & size;
            final tag = tester.getRect(_tag);
            final hint = tester.getRect(
              find
                  .ancestor(of: _hintText, matching: find.byType(Container))
                  .first,
            );
            expect(
              screen.contains(tag.topLeft) && screen.contains(tag.bottomRight),
              isTrue,
              reason: 'tagline inside the screen',
            );
            expect(
              screen.contains(hint.topLeft) &&
                  screen.contains(hint.bottomRight),
              isTrue,
              reason: 'hint inside the screen',
            );
            expect(
              hint.top,
              greaterThanOrEqualTo(tag.bottom),
              reason: 'the hint must not cover the tagline',
            );
            await tester.pump(_total);
          });
        }
      }
    }

    testWidgets('mid-animation frames do not overflow either', (tester) async {
      await pumpSplash(tester, size: const Size(320, 568), textScale: 2);
      for (var i = 0; i < 40; i++) {
        await tester.pump(const Duration(milliseconds: 80));
        expect(tester.takeException(), isNull, reason: 'frame $i');
      }
    });
  });

  group('contrast', () {
    test('painted text keeps its contrast in both themes', () {
      for (final (name, z, zs) in [
        ('light', ZColors.light, ZScene.light),
        ('dark', ZColors.dark, ZScene.dark),
      ]) {
        // The wordmark letters are 36pt/900: large text, 3:1.
        for (final (pair, fg, bg) in [
          ('ز ر on indigo', z.onIndigo, z.indigo),
          ('ن on teal', z.onTeal, z.teal),
          ('ج on tile', zs.amberInk, zs.tile),
          ('ی on coral', z.onCoral, z.coral),
        ]) {
          expect(
            contrastRatio(fg, bg),
            greaterThanOrEqualTo(3),
            reason: '$name: $pair',
          );
        }
        for (final (pair, fg, bg) in [
          ('tagline on ink pill', z.onInkSurface, z.inkSurface),
          ('hint on card', z.ink, z.surface),
          ('«حرف آخرِ» on card', zs.coralInk, z.surface),
        ]) {
          expect(
            contrastRatio(fg, bg),
            greaterThanOrEqualTo(4.5),
            reason: '$name: $pair',
          );
        }
      }
    });
  });

  group('goldens', () {
    Future<void> golden(
      WidgetTester tester,
      String file, {
      required int atMs,
      Brightness brightness = Brightness.light,
      Size size = const Size(393, 852),
      double textScale = 1,
      bool reduceMotion = false,
    }) async {
      await pumpSplash(
        tester,
        brightness: brightness,
        size: size,
        textScale: textScale,
        reduceMotion: reduceMotion,
      );
      // Several frames so the mascot and scene tickers are past their start.
      var left = atMs;
      while (left > 0) {
        final step = left < 100 ? left : 100;
        await tester.pump(Duration(milliseconds: step));
        left -= step;
      }
      await expectLater(
        find.byType(SplashScreen),
        matchesGoldenFile('goldens/$file.png'),
      );
      await tester.pump(_total);
    }

    testWidgets('tiles falling, light', (tester) async {
      await golden(tester, 'splash_tiles_light', atMs: 700);
    });

    testWidgets('mascot landing, dark', (tester) async {
      await golden(
        tester,
        'splash_landing_dark',
        atMs: 1500,
        brightness: Brightness.dark,
      );
    });

    testWidgets('finished, light', (tester) async {
      await golden(tester, 'splash_done_light', atMs: 2600);
    });

    testWidgets('finished, dark', (tester) async {
      await golden(
        tester,
        'splash_done_dark',
        atMs: 2600,
        brightness: Brightness.dark,
      );
    });

    testWidgets('small phone, large text, reduced motion, dark', (
      tester,
    ) async {
      await golden(
        tester,
        'splash_small_dark',
        atMs: 100,
        brightness: Brightness.dark,
        size: const Size(320, 568),
        textScale: 1.6,
        reduceMotion: true,
      );
    });
  });
}
