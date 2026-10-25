import 'package:flutter/animation.dart';
import 'package:wordchain/features/game/data/game_constants.dart';

/// The splash choreography from the canvas (`ZSplash.dc.html`), as pure
/// functions of the elapsed milliseconds so a single controller drives it and
/// tests can sample any instant. Times are the canvas's own; only the
/// progress-bar stretch that follows them was dropped (nothing backs it).
abstract final class SplashTimeline {
  /// The mascot lands on the chain at this instant.
  static const land = 1500.0;
  static const _mascotDrop = 520.0;

  /// End of the last entrance (the footer hint: `land + 380` + 520ms).
  static const introMs = 2400.0;

  static const holdMs = 0.0 + GameConstants.splashHoldMs;
  static const exitMs = 0.0 + GameConstants.splashExitMs;
  static const totalMs = introMs + holdMs + exitMs;

  static const _spring = Curves.easeOutBack;

  /// 0 → 1 over [dur] starting at [delay], eased by [curve]. Spring curves can
  /// overshoot 1; callers that fade clamp it.
  static double p(double ms, double delay, double dur, [Curve? curve]) =>
      (curve ?? Curves.linear).transform(((ms - delay) / dur).clamp(0.0, 1.0));

  /// Position of [t] inside the segment [a]…[b], clamped (float rounding can
  /// push the last step a hair past 1, which curves assert against).
  static double _seg(double t, double a, double b) =>
      ((t - a) / (b - a)).clamp(0.0, 1.0);

  /// The two big rings: `scale .2 → 1`, 700ms spring, 120ms apart.
  static double ring(double ms, int i) => p(ms, i * 120.0, 700, _spring);

  /// The glow behind the chain, after the mascot lands.
  static double glow(double ms) => p(ms, 1500, 600, Curves.easeOut);

  /// Tile [i] (0 = «ز») falls in from 460px up, spinning in from [tileSpin].
  static double tile(double ms, int i) => p(ms, 250 + i * 130.0, 620, _spring);

  static const tileSpin = [-28.0, 22.0, -18.0, 26.0, -24.0];

  /// Link [i] between tile i and i+1: scale 0 → 1.4 (at 60%) → 1.
  static double link(double ms, int i) {
    final t = p(ms, 620 + i * 130.0, 320);
    if (t < .6) return 1.4 * Curves.easeOut.transform(_seg(t, 0, .6));
    return 1.4 - .4 * Curves.easeOut.transform(_seg(t, .6, 1));
  }

  /// The mascot's drop: `(dy, scaleX, scaleY)` — falls 520px, squashes on the
  /// chain (1.22 × .78), bounces up 18px, settles.
  static (double, double, double) mascot(double ms) {
    final t = ((ms - (land - _mascotDrop)) / (_mascotDrop + 380)).clamp(
      0.0,
      1.0,
    );
    double lerp(double a, double b, double k) => a + (b - a) * k;
    if (t < .62) {
      final k = const Cubic(.55, 0, 1, .45).transform(_seg(t, 0, .62));
      return (lerp(-520, 0, k), lerp(.9, 1.22, k), lerp(1.12, .78, k));
    }
    if (t < .82) {
      final k = Curves.easeOut.transform(_seg(t, .62, .82));
      return (lerp(0, -18, k), lerp(1.22, .94, k), lerp(.78, 1.08, k));
    }
    final k = Curves.easeIn.transform(_seg(t, .82, 1));
    return (lerp(-18, 0, k), lerp(.94, 1, k), lerp(1.08, 1, k));
  }

  /// The tile row's dip when the mascot lands (px, positive = down).
  static double rowDip(double ms) {
    final t = p(ms, land - 140, 520);
    double lerp(double a, double b, double k) => a + (b - a) * k;
    final e = Curves.easeOut;
    if (t < .25) return lerp(0, 10, e.transform(_seg(t, 0, .25)));
    if (t < .6) return lerp(10, -3, e.transform(_seg(t, .25, .6)));
    return lerp(-3, 0, e.transform(_seg(t, .6, 1)));
  }

  /// Sparkle [i]: 0 until its window, then 0 → 1 → 0 over 700ms. Scale is
  /// `1.3 × s`, rotation `180° × t`; `t` is null outside the window.
  static double? spark(double ms, int i) {
    final t = (ms - (land - 120 + i * 60.0)) / 700;
    return t < 0 || t > 1 ? null : t;
  }

  static double sparkScale(double t) =>
      t < .5
          ? 1.3 * Curves.easeOut.transform(_seg(t, 0, .5))
          : 1.3 * (1 - Curves.easeOut.transform(_seg(t, .5, 1)));

  /// The «حرف آخر، حرف اول!» pill: scale 0 → 1, rotating in from −14°.
  static double tag(double ms) => p(ms, land + 260, 520, _spring);

  /// The footer hint: rises 30px while fading in.
  static double foot(double ms) => p(ms, land + 380, 520, _spring);

  /// The whole stage leaving: 0 → 1 over the exit window, ease-in.
  static double exit(double ms) =>
      p(ms, introMs + holdMs, exitMs, Curves.easeIn);
}
