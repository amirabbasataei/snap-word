import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wordchain/features/home/view/widgets/home_view.dart';

import '../../helpers/z_test_app.dart';

/// Whole-Home goldens (reduced motion → fully static): they pin the HUD pills
/// (coins, streak), the level badge and the «ادامهٔ بازی» resume chip so the
/// shared chunky-pill refactor can be compared pixel for pixel.
void main() {
  setUpAll(loadVazirmatn);

  for (final brightness in Brightness.values) {
    testWidgets('golden home hud + resume chip ${brightness.name}', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(393, 852);
      addTearDown(tester.view.reset);
      void noop() {}
      await tester.pumpWidget(
        RepaintBoundary(
          key: const Key('golden'),
          child: Stack(
            textDirection: TextDirection.ltr,
            children: [
              zTestApp(
                Builder(
                  builder:
                      (context) => MediaQuery(
                        data: MediaQuery.of(context).copyWith(
                          disableAnimations: true,
                          padding: const EdgeInsets.only(bottom: 100),
                        ),
                        child: HomeView(
                          data: const HomeViewData(
                            coins: 1240,
                            streak: 12,
                            level: 9,
                            xpInLevel: 2220,
                            xpForNext: 9000,
                            unclaimedRewards: 1,
                            hasActiveMatch: true,
                          ),
                          onPlay: noop,
                          onAi: noop,
                          onOnline: noop,
                          onDaily: noop,
                          onChest: noop,
                          onCoins: noop,
                          onSettings: noop,
                          onLevel: noop,
                          onResume: noop,
                        ),
                      ),
                ),
                brightness: brightness,
              ),
              // The ribbon's live Iran-midnight countdown is the only moving
              // part of a static Home; cover it so the golden is stable.
              const Positioned(
                left: 150,
                top: 228,
                width: 95,
                height: 26,
                child: ColoredBox(color: Color(0xFF808080)),
              ),
            ],
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));
      await expectLater(
        find.byKey(const Key('golden')),
        matchesGoldenFile('goldens/home_hud_${brightness.name}.png'),
      );
    });
  }
}
