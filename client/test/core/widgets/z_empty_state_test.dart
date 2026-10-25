import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wordchain/core/widgets/z_dialog.dart';
import 'package:wordchain/core/widgets/z_empty_state.dart';
import 'package:wordchain/core/widgets/z_mascot.dart';

import '../../helpers/z_test_app.dart';

Widget _app(
  ZEmptyState child, {
  double width = 300,
  double textScale = 1,
  Brightness brightness = Brightness.light,
}) => zTestApp(
  Builder(
    builder:
        (context) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(textScale),
            disableAnimations: true,
          ),
          child: Scaffold(
            body: Center(
              child: SingleChildScrollView(
                child: SizedBox(width: width, child: child),
              ),
            ),
          ),
        ),
  ),
  brightness: brightness,
);

void main() {
  setUpAll(loadVazirmatn);

  testWidgets('mascot, title and body; no action means no button', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(const ZEmptyState(title: 'هنوز دوستی نداری', body: 'یکی اضافه کن.')),
    );

    expect(find.text('هنوز دوستی نداری'), findsOneWidget);
    expect(find.text('یکی اضافه کن.'), findsOneWidget);
    expect(find.byType(ZMascot), findsOneWidget);
    expect(find.byType(ZDialogButton), findsNothing);
    expect(
      tester
          .getSemantics(find.text('هنوز دوستی نداری'))
          .flagsCollection
          .isHeader,
      isTrue,
    );
  });

  testWidgets('the mood reaches the mascot', (tester) async {
    for (final mood in ZMascotMood.values) {
      await tester.pumpWidget(_app(ZEmptyState(title: 't', mood: mood)));
      expect(tester.widget<ZMascot>(find.byType(ZMascot)).mood, mood);
    }
  });

  testWidgets('the action is a tappable primary button by default', (
    tester,
  ) async {
    var taps = 0;
    await tester.pumpWidget(
      _app(
        ZEmptyState(
          title: 't',
          actionLabel: 'افزودن دوست',
          onAction: () => taps++,
        ),
      ),
    );
    await tester.tap(find.text('افزودن دوست'));
    expect(taps, 1);
    expect(find.byType(ZDialogButton), findsOneWidget);
  });

  testWidgets('a secondary action is the neutral button', (tester) async {
    await tester.pumpWidget(
      _app(
        ZEmptyState(
          title: 't',
          actionLabel: 'تلاش دوباره',
          onAction: () {},
          primaryAction: false,
        ),
      ),
    );
    final button = tester.widget<ZDialogButton>(find.byType(ZDialogButton));
    // The neutral one is 50 tall, the primary 52.
    expect(button.height, 50);
  });

  testWidgets('the action label ignores text scale above 1.3×', (tester) async {
    await tester.pumpWidget(
      _app(
        ZEmptyState(title: 't', actionLabel: 'افزودن دوست', onAction: () {}),
        textScale: 2,
      ),
    );
    final paragraph = tester.renderObject<RenderParagraph>(
      find.text('افزودن دوست'),
    );
    expect(paragraph.textScaler.scale(10), closeTo(13, .01));
    final title = tester.renderObject<RenderParagraph>(find.text('t'));
    expect(
      title.textScaler.scale(10),
      closeTo(20, .01),
      reason: 'title scales',
    );
  });

  testWidgets('an action needs both a label and a callback', (tester) async {
    expect(
      () => ZEmptyState(title: 't', actionLabel: 'x'),
      throwsAssertionError,
    );
  });

  for (final brightness in Brightness.values) {
    for (final width in [200.0, 300.0, 420.0]) {
      testWidgets('no overflow at $width wide, ×2 text (${brightness.name})', (
        tester,
      ) async {
        await tester.pumpWidget(
          _app(
            ZEmptyState(
              title: 'هنوز هیچ دوستی در فهرستت نیست و این عنوان طولانی است',
              body:
                  'نام کاربری دقیق دوستت را وارد کن، یا کد دعوتت را برایش بفرست تا بتوانید با هم بازی کنید.',
              actionLabel: 'افزودن دوست',
              onAction: () {},
            ),
            width: width,
            textScale: 2,
            brightness: brightness,
          ),
        );
        expect(tester.takeException(), isNull);
      });
    }
  }
}
