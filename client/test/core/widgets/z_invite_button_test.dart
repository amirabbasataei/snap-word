import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wordchain/core/widgets/z_invite_button.dart';

import '../../helpers/z_test_app.dart';

Widget _app({
  bool invited = false,
  bool busy = false,
  VoidCallback? onTap,
  double textScale = 1,
  Brightness brightness = Brightness.light,
}) => zTestApp(
  Builder(
    builder:
        (context) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: Scaffold(
            body: Center(
              child: ZInviteButton(
                name: 'مریم ک.',
                invited: invited,
                busy: busy,
                onTap: onTap ?? () {},
              ),
            ),
          ),
        ),
  ),
  brightness: brightness,
);

void main() {
  setUpAll(loadVazirmatn);

  testWidgets('«دعوت به بازی» taps through', (tester) async {
    var taps = 0;
    await tester.pumpWidget(_app(onTap: () => taps++));
    await tester.tap(find.text('دعوت به بازی'));
    expect(taps, 1);
  });

  testWidgets('«دعوت شد» is inert', (tester) async {
    var taps = 0;
    await tester.pumpWidget(_app(invited: true, onTap: () => taps++));

    expect(find.text('دعوت شد'), findsOneWidget);
    expect(find.text('دعوت به بازی'), findsNothing);
    await tester.tap(find.text('دعوت شد'));
    expect(taps, 0);
  });

  testWidgets('busy keeps the label but ignores taps', (tester) async {
    var taps = 0;
    await tester.pumpWidget(_app(busy: true, onTap: () => taps++));
    await tester.tap(find.text('دعوت به بازی'));
    expect(taps, 0);
  });

  testWidgets('is 44 tall, names the friend, and caps text at 1.3×', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(_app(textScale: 2));

    expect(
      tester.getSize(find.byType(ZInviteButton)).height,
      greaterThanOrEqualTo(44),
    );
    expect(find.bySemanticsLabel(RegExp('مریم ک')), findsOneWidget);
    final paragraph = tester.renderObject<RenderParagraph>(
      find.text('دعوت به بازی'),
    );
    expect(paragraph.textScaler.scale(10), closeTo(13, .01));
    handle.dispose();
  });

  for (final brightness in Brightness.values) {
    testWidgets('renders in ${brightness.name}', (tester) async {
      await tester.pumpWidget(_app(brightness: brightness));
      await tester.pumpWidget(_app(brightness: brightness, invited: true));
      expect(tester.takeException(), isNull);
    });
  }
}
