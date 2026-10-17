import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wordchain/core/widgets/z_mascot.dart';

import '../../helpers/z_test_app.dart';

Widget _sheet(Brightness b, {bool reduceMotion = true}) => zTestApp(
  Scaffold(
    body: Center(
      child: RepaintBoundary(
        key: const Key('golden'),
        child: Builder(
          builder:
              (context) => ColoredBox(
                color: Theme.of(context).scaffoldBackgroundColor,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Wrap(
                    spacing: 8,
                    children: [
                      for (final m in ZMascotMood.values)
                        ZMascot(mood: m, size: 100, animate: !reduceMotion),
                    ],
                  ),
                ),
              ),
        ),
      ),
    ),
  ),
  brightness: b,
  reduceMotion: reduceMotion,
);

void main() {
  setUpAll(loadVazirmatn);

  testWidgets('every mood renders at several sizes without errors', (
    tester,
  ) async {
    for (final size in [40.0, 88.0, 130.0, 260.0]) {
      await tester.pumpWidget(
        zTestApp(
          Scaffold(
            body: Wrap(
              children: [
                for (final m in ZMascotMood.values)
                  ZMascot(mood: m, size: size, shadow: size > 100),
              ],
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 500));
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('the layout box is the canvas ratio (155/130)', (tester) async {
    await tester.pumpWidget(
      zTestApp(const Scaffold(body: Align(child: ZMascot(size: 88)))),
    );
    final size = tester.getSize(find.byType(ZMascot));
    expect(size.width, 88);
    expect(size.height, ZMascot.heightFor(88));
    expect(ZMascot.heightFor(88), 105);
    expect(ZMascot.heightFor(130), 155);
  });

  testWidgets('has no letter on it', (tester) async {
    await tester.pumpWidget(
      zTestApp(const Scaffold(body: Align(child: ZMascot()))),
    );
    // Painted only: the mascot owns no text.
    expect(
      find.descendant(of: find.byType(ZMascot), matching: find.byType(Text)),
      findsNothing,
    );
  });

  testWidgets('reduced motion: nothing is scheduled', (tester) async {
    await tester.pumpWidget(
      zTestApp(
        const Scaffold(
          body: Column(
            children: [
              ZMascot(mood: ZMascotMood.sad),
              ZMascot(mood: ZMascotMood.thinking),
              ZMascot(mood: ZMascotMood.surprised),
            ],
          ),
        ),
        reduceMotion: true,
      ),
    );
    await tester.pump();
    expect(tester.hasRunningAnimations, isFalse);
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('animated moods keep a ticker running', (tester) async {
    await tester.pumpWidget(
      zTestApp(const Scaffold(body: ZMascot(mood: ZMascotMood.happy))),
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.binding.hasScheduledFrame, isTrue);
  });

  testWidgets('is described to screen readers', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      zTestApp(const Scaffold(body: Align(child: ZMascot(mood: ZMascotMood.sad)))),
    );
    expect(find.bySemanticsLabel('شخصیت زنجیر، ناراحت'), findsOneWidget);
    handle.dispose();
  });

  for (final b in Brightness.values) {
    testWidgets('golden: all five moods (${b.name})', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(580, 220);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(_sheet(b));
      await tester.pump(const Duration(milliseconds: 100));
      await expectLater(
        find.byKey(const Key('golden')),
        matchesGoldenFile('goldens/z_mascot_moods_${b.name}.png'),
      );
    });
  }
}
