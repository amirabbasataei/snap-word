import 'package:flutter_test/flutter_test.dart';
import 'package:wordchain/features/game/data/game_constants.dart';
import 'package:wordchain/features/splash/view/widgets/splash_timeline.dart';

void main() {
  const done = SplashTimeline.introMs;

  test('the total is intro + hold + exit, from the shared constants', () {
    expect(SplashTimeline.holdMs, GameConstants.splashHoldMs);
    expect(SplashTimeline.exitMs, GameConstants.splashExitMs);
    expect(
      SplashTimeline.totalMs,
      SplashTimeline.introMs +
          GameConstants.splashHoldMs +
          GameConstants.splashExitMs,
    );
  });

  test('before anything has started every piece rests at its first frame', () {
    expect(SplashTimeline.ring(0, 0), 0);
    expect(SplashTimeline.tile(0, 0), 0);
    expect(SplashTimeline.link(0, 0), 0);
    expect(SplashTimeline.tag(0), 0);
    expect(SplashTimeline.foot(0), 0);
    expect(SplashTimeline.glow(0), 0);
    expect(SplashTimeline.exit(0), 0);
    expect(SplashTimeline.spark(0, 0), isNull);
    final (dy, sx, sy) = SplashTimeline.mascot(0);
    expect((dy, sx, sy), (-520.0, .9, 1.12));
  });

  test('when the intro ends the composition is complete and still', () {
    for (var i = 0; i < 2; i++) {
      expect(SplashTimeline.ring(done, i), 1);
    }
    for (var i = 0; i < 5; i++) {
      expect(SplashTimeline.tile(done, i), 1);
    }
    for (var i = 0; i < 4; i++) {
      expect(SplashTimeline.link(done, i), closeTo(1, 1e-9));
      expect(SplashTimeline.spark(done, i), isNull);
    }
    expect(SplashTimeline.tag(done), closeTo(1, 1e-9));
    expect(SplashTimeline.foot(done), closeTo(1, 1e-9));
    expect(SplashTimeline.glow(done), 1);
    expect(SplashTimeline.rowDip(done), 0);
    final (dy, sx, sy) = SplashTimeline.mascot(done);
    expect((dy, sx, sy), (0.0, 1.0, 1.0));
  });

  test('tiles fall in reading order, «ز» first', () {
    // 300ms in: only the first tile has started moving.
    expect(SplashTimeline.tile(300, 0), greaterThan(0));
    expect(SplashTimeline.tile(300, 1), 0);
    for (var i = 0; i < 4; i++) {
      expect(
        SplashTimeline.tile(700, i),
        greaterThanOrEqualTo(SplashTimeline.tile(700, i + 1)),
      );
    }
  });

  test('the mascot squashes on the chain at the landing instant', () {
    // Canvas: it starts falling at land − 520 and the squash is 62% of the
    // 900ms drop, i.e. 38ms after the nominal `land`.
    const impact = SplashTimeline.land - 520 + .62 * 900;
    final (dy, sx, sy) = SplashTimeline.mascot(impact);
    expect(dy, closeTo(0, 1));
    expect(sx, closeTo(1.22, .01));
    expect(sy, closeTo(.78, .01));
    // Then it bounces up before settling.
    final (up, _, _) = SplashTimeline.mascot(impact + 130);
    expect(up, lessThan(-10));
  });

  test('the row dips when the mascot lands and comes back', () {
    var deepest = 0.0;
    for (var ms = 1300.0; ms < 1900; ms += 10) {
      deepest =
          deepest < SplashTimeline.rowDip(ms)
              ? SplashTimeline.rowDip(ms)
              : deepest;
    }
    expect(deepest, greaterThan(5));
  });

  test('sparkles shine only inside their 700ms window', () {
    expect(SplashTimeline.spark(1379, 0), isNull);
    expect(SplashTimeline.spark(1380, 0), 0);
    expect(SplashTimeline.spark(1740, 0), closeTo(.514, .001));
    expect(SplashTimeline.spark(2081, 0), isNull);
    // Each one starts 60ms after the previous.
    expect(SplashTimeline.spark(1440, 1), 0);
    expect(SplashTimeline.sparkScale(0), 0);
    expect(SplashTimeline.sparkScale(.5), closeTo(1.3, 1e-9));
    expect(SplashTimeline.sparkScale(1), closeTo(0, 1e-9));
  });

  test('the exit runs only after the hold', () {
    const start = SplashTimeline.introMs + SplashTimeline.holdMs;
    expect(SplashTimeline.exit(start), 0);
    expect(
      SplashTimeline.exit(start + SplashTimeline.exitMs / 2),
      inExclusiveRange(0, 1),
    );
    expect(SplashTimeline.exit(SplashTimeline.totalMs), 1);
  });
}
