import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wordchain/core/widgets/z_mascot.dart';
import 'package:wordchain/features/home/view/widgets/home_hero.dart';

import '../../helpers/z_test_app.dart';

/// The mascot hanging on Home (canvas `ZHome3A`, frame 7a), at rest. The
/// 170×212 cell (20dp margin, 3× pixels) is rendered from the canvas markup
/// by the reference script too, so the PNGs can be diffed pixel for pixel.
void main() {
  setUpAll(loadVazirmatn);

  for (final (brightness, bg) in [
    (Brightness.light, const Color(0xFFEAF3FF)),
    (Brightness.dark, const Color(0xFF2B2632)),
  ]) {
    testWidgets('golden hanging mascot ${brightness.name}', (tester) async {
      tester.view.devicePixelRatio = 3;
      tester.view.physicalSize = const Size(170 * 3, 212 * 3);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        RepaintBoundary(
          key: const Key('golden'),
          child: zTestApp(
            ColoredBox(
              color: bg,
              child: Stack(
                clipBehavior: Clip.none,
                children: const [
                  Positioned(
                    left: 20,
                    top: 20,
                    child: ZMascot(
                      mood: ZMascotMood.hanging,
                      animate: false,
                    ),
                  ),
                ],
              ),
            ),
            brightness: brightness,
            reduceMotion: true,
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));
      await expectLater(
        find.byKey(const Key('golden')),
        matchesGoldenFile('goldens/home_mascot_hanging_${brightness.name}.png'),
      );
    });
  }

  testWidgets('golden home hero with the hanging mascot', (tester) async {
    tester.view.devicePixelRatio = 2;
    tester.view.physicalSize = const Size(396 * 2, 352 * 2);
    addTearDown(tester.view.reset);
    void noop() {}
    await tester.pumpWidget(
      RepaintBoundary(
        key: const Key('golden'),
        child: zTestApp(
          Stack(
            textDirection: TextDirection.ltr,
            children: [
              HomeHero(
                words: const ['سیب', 'بارانا', 'نمک', 'کتاب', 'برف'],
                animate: false,
                chestReady: true,
                dailyDot: true,
                onDaily: noop,
                onChest: noop,
                onAi: noop,
              ),
              // The ribbon's live Iran-midnight countdown is the only moving
              // part; cover it so the golden is stable.
              const Positioned(
                left: 150,
                top: 82,
                width: 95,
                height: 26,
                child: ColoredBox(color: Color(0xFF808080)),
              ),
            ],
          ),
          reduceMotion: true,
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    await expectLater(
      find.byKey(const Key('golden')),
      matchesGoldenFile('goldens/home_hero_light.png'),
    );
  });
}
