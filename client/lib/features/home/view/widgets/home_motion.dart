import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// Idle-loop helpers for the home scene. Each loop is a pure function of the
/// elapsed time so a whole subtree can animate off one [Ticker].
abstract final class HomeLoop {
  /// CSS `animation-direction: alternate` with `ease-in-out`: 0 → 1 → 0 over
  /// two [periodMs]. Holds 0 until [delayMs] has passed.
  static double pingPong(double ms, int periodMs, {int delayMs = 0}) {
    final t = ms - delayMs;
    if (t <= 0) return 0;
    final k = (t / periodMs) % 2;
    return Curves.easeInOut.transform(k <= 1 ? k : 2 - k);
  }

  /// [pingPong] mapped to `[a, b]`.
  static double swing(
    double ms,
    int periodMs,
    double a,
    double b, {
    int delayMs = 0,
  }) => a + (b - a) * pingPong(ms, periodMs, delayMs: delayMs);

  /// Sparkle: scale/opacity up then down over two [pingPong] halves.
  static double twinkle(double ms, {int delayMs = 0}) =>
      pingPong(ms, 900, delayMs: delayMs);

  /// Piecewise keyframes `(offset, value)` over one cycle, eased per segment.
  static double keyframes(
    double ms,
    int periodMs,
    List<(double, double)> frames, {
    int delayMs = 0,
  }) {
    final t = ms - delayMs;
    if (t <= 0) return frames.first.$2;
    final p = (t % periodMs) / periodMs;
    for (var i = 0; i < frames.length - 1; i++) {
      final (o0, v0) = frames[i];
      final (o1, v1) = frames[i + 1];
      if (p >= o0 && p < o1) {
        final x = (p - o0) / (o1 - o0);
        return v0 + (v1 - v0) * Curves.easeInOut.transform(x);
      }
    }
    return frames.last.$2;
  }

  /// Play button idle pulse: a short 1 → 1.035 → 1 beat, then rest.
  static double pulse(double ms) => keyframes(ms, 2200, const [
    (0, 1),
    (.2, 1.035),
    (.4, 1),
    (1, 1),
  ], delayMs: 1000);

  /// Chest wiggle (degrees), a quick shake at the start of each cycle.
  static double wiggle(double ms) => keyframes(ms, 3500, const [
    (0, 0),
    (.05, -8),
    (.1, 8),
    (.15, -5),
    (.2, 0),
    (1, 0),
  ], delayMs: 1400);

  /// Eye scale-Y: open, then a quick blink near the end of each cycle.
  static double blink(double ms) {
    final p = (ms % 4200) / 4200;
    if (p < .9 || p >= .96) return 1;
    return p < .93 ? 1 - 0.9 * ((p - .9) / .03) : .1 + .9 * ((p - .93) / .03);
  }

  static double deg(double degrees) => degrees * math.pi / 180;
}

/// True when the OS asks for reduced motion — idle loops are frozen then.
bool homeReducedMotion(BuildContext context) =>
    MediaQuery.maybeDisableAnimationsOf(context) ?? false;

/// Drives [builder] with the elapsed milliseconds of a free-running ticker.
/// With [enabled] false (reduced motion) no ticker runs and `ms` stays 0, so
/// every loop rests in its base pose.
class HomeClock extends StatefulWidget {
  final bool enabled;
  final Widget? child;
  final Widget Function(BuildContext context, double ms, Widget? child) builder;

  const HomeClock({
    super.key,
    required this.enabled,
    required this.builder,
    this.child,
  });

  @override
  State<HomeClock> createState() => _HomeClockState();
}

class _HomeClockState extends State<HomeClock>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  final _ms = ValueNotifier<double>(0);

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((d) => _ms.value = d.inMicroseconds / 1000.0);
    if (widget.enabled) _ticker.start();
  }

  @override
  void didUpdateWidget(HomeClock old) {
    super.didUpdateWidget(old);
    if (widget.enabled && !_ticker.isActive) {
      _ticker.start();
    } else if (!widget.enabled && _ticker.isActive) {
      _ticker.stop();
      _ms.value = 0;
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    _ms.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<double>(
      valueListenable: _ms,
      child: widget.child,
      builder: (context, ms, child) => widget.builder(context, ms, child),
    );
  }
}
