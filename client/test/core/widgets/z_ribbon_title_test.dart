import 'package:flutter/rendering.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wordchain/core/widgets/chunky.dart';
import 'package:wordchain/core/widgets/z_dialog.dart';
import 'package:wordchain/core/widgets/z_ribbon_title.dart';

import '../../helpers/z_test_app.dart';

Widget _ribbon({
  double width = 300,
  double textScale = 1,
  Brightness brightness = Brightness.light,
  TextDirection direction = TextDirection.rtl,
  ZDialogAccent accent = ZDialogAccent.coral,
  String text = 'رویارویی آنلاین',
  bool expand = true,
}) => zTestApp(
  Builder(
    builder:
        (context) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: Directionality(
            textDirection: direction,
            child: Center(
              child: SizedBox(
                width: width,
                child: Center(
                  child: ZRibbonTitle(text, accent: accent, expand: expand),
                ),
              ),
            ),
          ),
        ),
  ),
  brightness: brightness,
);

void main() {
  setUpAll(loadVazirmatn);

  testWidgets('shows its text as a header', (tester) async {
    await tester.pumpWidget(_ribbon());
    expect(find.text('رویارویی آنلاین'), findsOneWidget);
    expect(
      tester.getSemantics(find.byType(ZRibbonTitle)).flagsCollection.isHeader,
      isTrue,
    );
  });

  testWidgets('the plate is 44 tall; two tails stand outside it', (
    tester,
  ) async {
    await tester.pumpWidget(_ribbon());
    final plate = tester.getRect(find.byType(ChunkyBox));
    expect(plate.height, ZRibbonTitle.height);

    final tails =
        find
            .descendant(
              of: find.byType(ZRibbonTitle),
              matching: find.byType(CustomPaint),
            )
            .evaluate()
            .map((e) => tester.getRect(find.byWidget(e.widget)))
            .where((r) => r.width == ZRibbonTitle.tailWidth)
            .toList();
    expect(tails, hasLength(2));
    tails.sort((a, b) => a.left.compareTo(b.left));
    expect(tails.first.left, plate.left - ZRibbonTitle.tailReach);
    expect(tails.last.right, plate.right + ZRibbonTitle.tailReach);
  });

  for (final direction in TextDirection.values) {
    testWidgets('renders in ${direction.name}', (tester) async {
      await tester.pumpWidget(_ribbon(direction: direction));
      expect(tester.takeException(), isNull);
    });
  }

  for (final width in [120.0, 160.0, 300.0]) {
    testWidgets('text scales down instead of overflowing in $width', (
      tester,
    ) async {
      await tester.pumpWidget(_ribbon(width: width, textScale: 2));
      expect(tester.takeException(), isNull);
      final box = tester.getRect(find.byType(ZRibbonTitle));
      expect(box.width, lessThanOrEqualTo(width));
    });
  }

  testWidgets('ignores text scale above 1.3', (tester) async {
    await tester.pumpWidget(_ribbon(textScale: 2));
    final paragraph = tester.renderObject<RenderParagraph>(
      find.text('رویارویی آنلاین'),
    );
    expect(paragraph.textScaler.scale(10), closeTo(13, .01));
    expect(tester.getRect(find.byType(ChunkyBox)).height, 44);
  });

  for (final accent in ZDialogAccent.values) {
    for (final brightness in Brightness.values) {
      testWidgets('${accent.name} ${brightness.name}', (tester) async {
        await tester.pumpWidget(
          _ribbon(accent: accent, brightness: brightness),
        );
        expect(tester.takeException(), isNull);
      });
    }
  }

  group('expand: false (the compact Friends ribbon)', () {
    testWidgets('hugs the text instead of filling the width', (tester) async {
      await tester.pumpWidget(_ribbon(width: 300));
      final full = tester.getRect(find.byType(ChunkyBox));
      await tester.pumpWidget(
        _ribbon(width: 300, expand: false, text: 'دوستان'),
      );
      final compact = tester.getRect(find.byType(ChunkyBox));

      expect(compact.width, lessThan(full.width / 2));
      expect(compact.height, ZRibbonTitle.height);
      // Still centred in the row it is given.
      expect(
        compact.center.dx,
        closeTo(tester.getRect(find.byType(SizedBox).first).center.dx, 1),
      );
      expect(find.text('دوستان'), findsOneWidget);
    });

    testWidgets('still scales down in a narrow slot at ×2', (tester) async {
      await tester.pumpWidget(
        _ribbon(
          width: 120,
          expand: false,
          textScale: 2,
          text: 'رویارویی آنلاین',
        ),
      );
      expect(tester.takeException(), isNull);
      expect(
        tester.getRect(find.byType(ZRibbonTitle)).width,
        lessThanOrEqualTo(120),
      );
    });

    testWidgets('the label is vertically centred in the plate', (tester) async {
      await tester.pumpWidget(_ribbon(expand: false, text: 'دوستان'));
      final plate = tester.getRect(find.byType(ChunkyBox));
      final label = tester.getRect(find.text('دوستان'));
      expect(label.center.dy, closeTo(plate.center.dy, 2));
    });
  });
}
