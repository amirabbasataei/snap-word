import 'package:flutter/material.dart';
import 'package:wordchain/core/theme/app_game_metrics.dart';
import 'package:wordchain/core/theme/app_scene_tokens.dart';
import 'package:wordchain/core/theme/app_tokens.dart';
import 'package:wordchain/core/theme/app_typography.dart';
import 'package:wordchain/core/widgets/chunky.dart';
import 'package:wordchain/core/widgets/motion.dart';
import 'package:wordchain/core/widgets/z_mascot.dart';
import 'package:wordchain/features/game/view/widgets/z_over_hero.dart';
import 'package:wordchain/features/home/view/widgets/home_logo.dart';

/// Top of the phone screen (canvas `ZPhoneA`, a 268dp block): the «زنجیر»
/// lockup with its tagline, the idle mascot and two word tiles that bob —
/// «سلام» and «ماه» share the م, which is the whole game in two tiles.
/// Decorative, so it ignores text scaling; reduced motion holds it still.
class LoginHero extends StatelessWidget {
  const LoginHero({super.key});

  static const height = 268.0;

  @override
  Widget build(BuildContext context) {
    final narrow = MediaQuery.sizeOf(context).width < 360;
    final animate = !homeReducedMotion(context);
    final mascot = narrow ? 84.0 : 104.0;
    final edge = narrow ? 12.0 : 30.0;
    return MediaQuery.withNoTextScaling(
      child: SizedBox(
        height: height,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            const Positioned(
              top: 20,
              left: 0,
              right: 0,
              child: ZOverEnter(
                kind: ZOverEnterKind.pop,
                delayMs: 0,
                child: HomeLogo(),
              ),
            ),
            Positioned(
              top: 122,
              left: 0,
              right: 0,
              child: Center(
                child: ZOverEnter(
                  kind: ZOverEnterKind.pop,
                  delayMs: 250,
                  child: ZMascot(size: mascot, animate: animate),
                ),
              ),
            ),
            PositionedDirectional(
              start: edge,
              top: 150,
              child: ZOverEnter(
                kind: ZOverEnterKind.up,
                delayMs: 400,
                child: _BobbingTile(
                  animate: animate,
                  angle: -8,
                  periodMs: 2200,
                  before: 'سلا',
                  shared: 'م',
                  after: '',
                ),
              ),
            ),
            PositionedDirectional(
              end: edge + (narrow ? 0 : 4),
              top: 178,
              child: ZOverEnter(
                kind: ZOverEnterKind.up,
                delayMs: 500,
                child: _BobbingTile(
                  animate: animate,
                  angle: 7,
                  periodMs: 2600,
                  delayMs: 600,
                  before: '',
                  shared: 'م',
                  after: 'اه',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A 44dp word tile with the shared letter picked out in teal.
class _BobbingTile extends StatelessWidget {
  final bool animate;
  final double angle;
  final int periodMs;
  final int delayMs;
  final String before;
  final String shared;
  final String after;

  const _BobbingTile({
    required this.animate,
    required this.angle,
    required this.periodMs,
    this.delayMs = 0,
    required this.before,
    required this.shared,
    required this.after,
  });

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    final zs = context.zs;
    final base = ZTypography.display.copyWith(
      fontSize: 20,
      height: 1,
      color: z.ink,
    );
    return Semantics(
      label: '$before$shared$after',
      excludeSemantics: true,
      child: HomeClock(
        enabled: animate,
        builder:
            (context, ms, child) => Transform.translate(
              offset: Offset(
                0,
                HomeLoop.swing(ms, periodMs, 0, -5, delayMs: delayMs),
              ),
              child: child,
            ),
        child: Transform.rotate(
          angle: HomeLoop.deg(angle),
          child: ChunkyBox(
            fill: zs.tile,
            deep: zs.tileDeep,
            depth: ZGame.depthMd,
            radius: 14,
            height: 44,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            alignment: Alignment.center,
            child: Text.rich(
              TextSpan(
                style: base,
                children: [
                  TextSpan(text: before),
                  TextSpan(text: shared, style: TextStyle(color: zs.tealInk)),
                  TextSpan(text: after),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
