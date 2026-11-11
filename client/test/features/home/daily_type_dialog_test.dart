import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wordchain/features/home/view/widgets/home_daily_dialog.dart';

import '../../helpers/z_test_app.dart';

/// A stand-in for Home's «چالش روزانه» button.
class _Host extends StatelessWidget {
  final ValueChanged<int?> onResult;
  final List<int> played;

  const _Host(this.onResult, {this.played = const []});

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: TextButton(
        onPressed:
            () async =>
                onResult(await showDailyTypeDialog(context, played: played)),
        child: const Text('open'),
      ),
    ),
  );
}

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 700));
  await tester.pump(const Duration(milliseconds: 700));
}

Future<void> _open(
  WidgetTester tester,
  ValueChanged<int?> onResult, {
  List<int> played = const [],
  Brightness brightness = Brightness.light,
}) async {
  await tester.pumpWidget(
    zTestApp(
      _Host(onResult, played: played),
      brightness: brightness,
      reduceMotion: true,
    ),
  );
  await tester.tap(find.text('open'));
  await _settle(tester);
}

void _size(WidgetTester tester, double w, double h) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(w, h);
  addTearDown(tester.view.reset);
}

void main() {
  setUpAll(loadVazirmatn);

  test('three types, keyed by the link position the game takes', () {
    expect(dailyTypeOptions.map((o) => o.variant), [1, 2, 3]);
    expect(dailyTypeOptions.map((o) => o.level), ['کلاسیک', 'سخت', 'خیلی سخت']);
  });

  testWidgets('copy, timers and the examples; no start button', (tester) async {
    _size(tester, 396, 812);
    await _open(tester, (_) {});
    expect(find.text('نوع چالش رو انتخاب کن'), findsOneWidget);
    expect(find.text('هر نوع جدول و جایزهٔ خودش رو داره'), findsOneWidget);
    expect(find.text('حرف اول'), findsOneWidget);
    expect(find.text('حرف دوم'), findsOneWidget);
    expect(find.text('حرف سوم'), findsOneWidget);
    expect(find.text('کلاسیک · ۱۵ ثانیه'), findsOneWidget);
    expect(find.text('سخت · ۲۰ ثانیه'), findsOneWidget);
    expect(find.text('خیلی سخت · ۲۵ ثانیه'), findsOneWidget);
    expect(find.textContaining('انتظار'), findsOneWidget);
    expect(find.text('شروع بازی'), findsNothing);
    expect(find.textContaining('بازی کردی'), findsNothing);
  });

  for (final (label, variant) in [
    ('حرف اول', 1),
    ('حرف دوم', 2),
    ('حرف سوم', 3),
  ]) {
    testWidgets('tapping «$label» returns $variant at once', (tester) async {
      _size(tester, 396, 812);
      int? result = -1;
      await _open(tester, (r) => result = r);
      await tester.tap(find.text(label));
      await _settle(tester);
      expect(result, variant);
      expect(find.text('نوع چالش رو انتخاب کن'), findsNothing);
    });
  }

  testWidgets('types played today are marked and still open', (tester) async {
    _size(tester, 396, 812);
    int? result = -1;
    await _open(tester, (r) => result = r, played: const [2]);
    expect(find.text('بازی کردی ✓'), findsOneWidget);
    await tester.tap(find.text('حرف دوم'));
    await _settle(tester);
    expect(result, 2);
  });

  testWidgets('the close button and the scrim return null', (tester) async {
    _size(tester, 396, 812);
    int? result = -1;
    await _open(tester, (r) => result = r);
    await tester.tap(
      find.byWidgetPredicate(
        (w) =>
            w is Semantics &&
            w.properties.label == 'بستن' &&
            w.properties.button == true,
      ),
    );
    await _settle(tester);
    expect(result, isNull);

    result = -1;
    await tester.tap(find.text('open'));
    await _settle(tester);
    await tester.tapAt(const Offset(4, 4));
    await _settle(tester);
    expect(result, isNull);
  });

  testWidgets('each card reads as one button to a screen reader', (
    tester,
  ) async {
    _size(tester, 396, 812);
    final handle = tester.ensureSemantics();
    await _open(tester, (_) {}, played: const [1]);
    expect(
      find.bySemanticsLabel(RegExp('^حرف دوم، سخت، حرف دوم = حرف آخر قبلی')),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel(RegExp('امروز بازی کردی')), findsOneWidget);
    handle.dispose();
  });

  for (final b in Brightness.values) {
    for (final size in const [
      Size(320, 568),
      Size(360, 640),
      Size(393, 852),
      Size(430, 932),
    ]) {
      testWidgets(
        'no overflow ${size.width.toInt()}×${size.height.toInt()} ${b.name}',
        (tester) async {
          _size(tester, size.width, size.height);
          await _open(tester, (_) {}, played: const [1, 3], brightness: b);
          expect(tester.takeException(), isNull);
          expect(find.text('حرف سوم'), findsOneWidget);
        },
      );
    }
  }
}
