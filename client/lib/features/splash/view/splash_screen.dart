import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:wordchain/core/theme/app_game_metrics.dart';
import 'package:wordchain/core/theme/app_scene_tokens.dart';
import 'package:wordchain/core/theme/app_tokens.dart';
import 'package:wordchain/core/theme/app_typography.dart';
import 'package:wordchain/core/widgets/chunky.dart';
import 'package:wordchain/core/widgets/motion.dart';
import 'package:wordchain/features/game/data/game_constants.dart';
import 'package:wordchain/features/home/view/widgets/home_scene_background.dart';
import 'package:wordchain/features/splash/view/widgets/splash_hero.dart';
import 'package:wordchain/features/splash/view/widgets/splash_timeline.dart';

/// Launch splash (canvas `ZSplash`): the wordmark tiles fall in, the mascot
/// drops onto the chain, then the app continues to `/home` — for guests and
/// signed-in players alike (never a login gate).
///
/// It waits for nothing. `main()` has already loaded the dictionary, wired
/// DI and resolved auth (`AuthCubit.init`) before the first frame, so this is
/// a fixed-length intro: [SplashTimeline.introMs] of choreography, a short
/// hold and a fade, [SplashTimeline.totalMs] in all. One controller owns the
/// timing — no timer to leak, and after the app was backgrounded the first
/// frame back lands past the end and continues at once. With reduced motion
/// the finished composition is shown still for
/// [GameConstants.splashReducedMs].
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  static const next = '/home';

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  AnimationController? _c;
  late GoRouter _router;
  bool _reduced = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_c != null) return;
    _reduced = homeReducedMotion(context);
    _router = GoRouter.of(context);
    _c = AnimationController(
      vsync: this,
      duration: Duration(
        milliseconds:
            _reduced
                ? GameConstants.splashReducedMs
                : SplashTimeline.totalMs.round(),
      ),
    )..addStatusListener((s) {
      if (s == AnimationStatus.completed && mounted && _stillHere) {
        _router.go(SplashScreen.next);
      }
    });
    _c!.forward();
  }

  /// A deep link or challenge can move the router on while the splash is
  /// still on screen (a route being replaced stays mounted for its exit
  /// transition); continuing Home then would drag the player off it.
  bool get _stillHere =>
      _router.routerDelegate.currentConfiguration.uri.path == '/splash';

  @override
  void dispose() {
    _c?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _c!;
    return Scaffold(
      backgroundColor: context.z.paper,
      body: Stack(
        fit: StackFit.expand,
        children: [
          const HomeSceneBackground(rings: false),
          // The wordmark reads «ز» on the right whatever the app's direction.
          Directionality(
            textDirection: TextDirection.rtl,
            child: SafeArea(
              child: AnimatedBuilder(
                animation: c,
                builder: (context, _) {
                  final ms =
                      _reduced
                          ? SplashTimeline.introMs
                          : c.value * SplashTimeline.totalMs;
                  final exit = _reduced ? 0.0 : SplashTimeline.exit(ms);
                  return Opacity(
                    opacity: 1 - exit,
                    child: Transform.scale(
                      scale: 1 + .06 * exit,
                      child: Stack(
                        children: [
                          // Centre of the hero sits at 45.6% of the canvas
                          // frame (y 370 of 812).
                          Align(
                            alignment: const Alignment(0, -.09),
                            child: MediaQuery.withNoTextScaling(
                              child: FittedBox(
                                child: SplashHero(ms: ms, animate: !_reduced),
                              ),
                            ),
                          ),
                          Align(
                            alignment: Alignment.bottomCenter,
                            child: Padding(
                              padding: const EdgeInsetsDirectional.fromSTEB(
                                44,
                                0,
                                44,
                                44,
                              ),
                              child: MediaQuery.withClampedTextScaling(
                                maxScaleFactor: 1.3,
                                child: _Foot(t: SplashTimeline.foot(ms)),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The rule in one sentence, rising in under the chain. The canvas also draws
/// a progress bar and «نسخهٔ ۱٫۰» here; nothing loads and the app does not
/// read its version, so neither is shown.
class _Foot extends StatelessWidget {
  final double t;

  const _Foot({required this.t});

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    final zs = context.zs;
    final style = ZTypography.body.copyWith(
      fontSize: 13,
      fontWeight: FontWeight.w700,
      height: 1.6,
      color: z.ink,
    );
    return Opacity(
      opacity: t.clamp(0.0, 1.0),
      child: Transform.translate(
        offset: Offset(0, 30 * (1 - t)),
        child: ChunkyBox(
          fill: z.surface,
          depth: ZGame.depthSm,
          radius: 14,
          highlight: false,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          child: Text.rich(
            TextSpan(
              style: style,
              children: [
                const TextSpan(text: 'هر کلمه با '),
                TextSpan(
                  text: 'حرف آخرِ',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    color: zs.coralInk,
                  ),
                ),
                const TextSpan(text: ' کلمهٔ قبلی شروع می‌شود'),
              ],
            ),
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}
