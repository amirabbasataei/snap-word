import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:wordchain/core/theme/app_game_metrics.dart';
import 'package:wordchain/core/theme/app_scene_tokens.dart';
import 'package:wordchain/core/theme/app_tokens.dart';
import 'package:wordchain/core/theme/app_typography.dart';
import 'package:wordchain/core/utils/persian_digits.dart';
import 'package:wordchain/core/widgets/chunky.dart';
import 'package:wordchain/core/widgets/dashed_tile.dart';
import 'package:wordchain/core/widgets/motion.dart';
import 'package:wordchain/core/widgets/z_disc_avatar.dart';
import 'package:wordchain/core/widgets/z_mascot.dart';
import 'package:wordchain/core/widgets/z_stroked_text.dart';

/// What the opponent slot and the mascot say about the queue.
enum LobbyStageMode { idle, searching, found, error }

/// The head-to-head stage of the lobby (canvas `ZLobbyA`): my disc on the
/// start side, the still-unknown opponent on the end side, «در برابر» between
/// them and the thinking mascot under it. While searching, radar rings pulse
/// around the opponent's disc and a chip counts the real elapsed time.
///
/// The canvas also shows «۳٬۴۰۱ نفر آنلاین · هم‌سطح تو» and a score under
/// my name; neither exists (no online-count endpoint, matchmaking pairs by
/// arrival order — `MatchmakingService.processQueue`), so the chip slot only
/// ever holds the elapsed time, and my sub-line is the real level.
class LobbyStage extends StatelessWidget {
  final LobbyStageMode mode;
  final String myName;
  final String myInitial;
  final String? myAvatarId;

  /// «سطح ۵»; null hides the line (stats not loaded).
  final String? mySubtitle;
  final int elapsedSeconds;

  /// Short phones get a tighter stage so the call to action stays on screen.
  final bool compact;

  const LobbyStage({
    super.key,
    required this.mode,
    required this.myName,
    required this.myInitial,
    this.myAvatarId,
    this.mySubtitle,
    this.elapsedSeconds = 0,
    this.compact = false,
  });

  static const _discSize = 88.0;

  String get _opponentLabel => switch (mode) {
    LobbyStageMode.idle => 'آمادهٔ شروع؟',
    LobbyStageMode.searching => 'در جست‌وجو…',
    LobbyStageMode.found => 'حریف پیدا شد!',
    LobbyStageMode.error => 'حریف پیدا نشد',
  };

  ZMascotMood get _mood => switch (mode) {
    LobbyStageMode.idle => ZMascotMood.idle,
    LobbyStageMode.searching => ZMascotMood.thinking,
    LobbyStageMode.found => ZMascotMood.happy,
    LobbyStageMode.error => ZMascotMood.sad,
  };

  @override
  Widget build(BuildContext context) {
    final reduced = homeReducedMotion(context);
    final searching = mode == LobbyStageMode.searching;
    final height = compact ? 216.0 : 244.0;
    final discTop = compact ? 18.0 : 26.0;
    final vsTop = compact ? 46.0 : 56.0;
    final mascotSize = compact ? 80.0 : 90.0;
    final mascotTop = compact ? 88.0 : 104.0;
    final chipTop = compact ? 186.0 : 212.0;

    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.3,
      child: LayoutBuilder(
        builder: (context, c) {
          final inset = c.maxWidth >= 360 ? 30.0 : 14.0;
          final tagMax = (c.maxWidth - 2 * inset) / 2 + 8;
          return SizedBox(
            height: height,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                PositionedDirectional(
                  start: inset,
                  top: discTop,
                  child: _Contestant(
                    maxTagWidth: tagMax,
                    disc: ZDiscAvatar.me(
                      context,
                      letter: myInitial,
                      size: _discSize,
                      avatarId: myAvatarId,
                    ),
                    title: myName,
                    subtitle: mySubtitle,
                  ),
                ),
                PositionedDirectional(
                  end: inset,
                  top: discTop,
                  child: _Contestant(
                    maxTagWidth: tagMax,
                    disc: _UnknownOpponent(
                      size: _discSize,
                      radar: searching,
                      animate: !reduced,
                    ),
                    title: _opponentLabel,
                  ),
                ),
                // Between the two discs; shrinks (never wraps) on narrow phones.
                Positioned.fill(
                  top: vsTop,
                  bottom: null,
                  child: Center(
                    child: SizedBox(
                      width: (c.maxWidth - 2 * (inset + _discSize)).clamp(
                        64.0,
                        140.0,
                      ),
                      child: Transform.rotate(
                        angle: -4 * math.pi / 180,
                        child: ZStrokedText(
                          'در برابر',
                          fontSize: 24,
                          fill: context.z.amber,
                          stroke: 5,
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  top: mascotTop,
                  child: Center(
                    child: ZMascot(
                      mood: _mood,
                      size: mascotSize,
                      animate: !reduced,
                    ),
                  ),
                ),
                if (searching)
                  Positioned(
                    left: 0,
                    right: 0,
                    top: chipTop,
                    child: Center(
                      child: _ElapsedChip(
                        seconds: elapsedSeconds,
                        animate: !reduced,
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// A disc over its name tag (canvas: 2.5dp outlined surface plate, name 14/900,
/// optional second line 12/700 in `ink60`).
class _Contestant extends StatelessWidget {
  final Widget disc;
  final String title;
  final String? subtitle;
  final double maxTagWidth;

  const _Contestant({
    required this.disc,
    required this.title,
    required this.maxTagWidth,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    final subtitle = this.subtitle;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        disc,
        const SizedBox(height: 8),
        ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxTagWidth),
          child: ChunkyBox(
            fill: z.surface,
            depth: 0,
            radius: 12,
            borderWidth: ZGame.outlineInner,
            highlight: false,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: ZTypography.button.copyWith(
                    fontSize: 14,
                    height: 1.3,
                    color: z.ink,
                  ),
                ),
                if (subtitle != null)
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: ZTypography.metaLabel.copyWith(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      height: 1.3,
                      color: z.ink60,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// The opponent's disc before there is one: a dashed ring around «؟», with
/// two teal radar rings expanding off it while the queue is searching.
class _UnknownOpponent extends StatelessWidget {
  final double size;
  final bool radar;
  final bool animate;

  const _UnknownOpponent({
    required this.size,
    required this.radar,
    required this.animate,
  });

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    final disc = SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            decoration: BoxDecoration(color: z.surface, shape: BoxShape.circle),
          ),
          Positioned.fill(
            child: CustomPaint(
              painter: DashedBorderPainter(
                radius: size / 2,
                color: context.zs.chain,
                strokeWidth: ZGame.outline,
                dashWidth: 7,
                dashGap: 5,
              ),
            ),
          ),
          Text(
            '؟',
            style: ZTypography.button.copyWith(
              fontSize: 40,
              height: 1,
              color: z.ink60,
            ),
          ),
        ],
      ),
    );
    if (!radar) return disc;
    return HomeClock(
      enabled: animate,
      builder:
          (context, ms, child) => SizedBox(
            width: size,
            height: size,
            child: Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.center,
              children: [
                _Ring(ms: ms, delayMs: 0, size: size, color: z.teal),
                _Ring(ms: ms, delayMs: 1000, size: size, color: z.teal),
                child!,
              ],
            ),
          ),
      child: disc,
    );
  }
}

/// Canvas `radar`: scale .6 → 1.5 and opacity .9 → 0 over 2s, ease-out.
class _Ring extends StatelessWidget {
  final double ms;
  final int delayMs;
  final double size;
  final Color color;

  const _Ring({
    required this.ms,
    required this.delayMs,
    required this.size,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    // Reduced motion leaves ms at 0: show no rings rather than frozen ones.
    if (ms <= delayMs) return const SizedBox.shrink();
    final t = Curves.easeOut.transform(((ms - delayMs) % 2000) / 2000);
    return Opacity(
      opacity: .9 * (1 - t),
      child: Transform.scale(
        scale: .6 + .9 * t,
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: color, width: ZGame.outline),
          ),
        ),
      ),
    );
  }
}

class _ElapsedChip extends StatelessWidget {
  final int seconds;
  final bool animate;

  const _ElapsedChip({required this.seconds, required this.animate});

  String get _clock => toPersianDigits(
    '${(seconds ~/ 60).toString().padLeft(2, '0')}:${(seconds % 60).toString().padLeft(2, '0')}',
  );

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    return ChunkyBox(
      fill: z.inkSurface,
      depth: 0,
      radius: 999,
      borderWidth: ZGame.outlineInner,
      highlight: false,
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          HomeClock(
            enabled: animate,
            builder:
                (context, ms, _) => Opacity(
                  opacity: 1 - .7 * HomeLoop.pingPong(ms, 700),
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: z.coral,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
          ),
          const SizedBox(width: 6),
          Text(
            'در صف · $_clock',
            style: ZTypography.button.copyWith(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: z.onInkSurface,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}
