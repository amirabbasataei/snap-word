import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wordchain/core/theme/app_tokens.dart';
import 'package:wordchain/core/widgets/z_toast.dart';

import '../../helpers/z_test_app.dart';

late BuildContext _ctx;

/// The visible card (outline + surface), not the full-screen overlay slot.
final _card =
    find
        .ancestor(
          of: find.descendant(
            of: find.byType(ZToastCard),
            matching: find.byType(ClipRRect),
          ),
          matching: find.byType(Container),
        )
        .first;

Widget _app({bool reduceMotion = false, Brightness b = Brightness.light}) =>
    zTestApp(
      Builder(
        builder: (context) {
          _ctx = context;
          return const Scaffold(body: SizedBox.expand());
        },
      ),
      brightness: b,
      reduceMotion: reduceMotion,
    );

void main() {
  setUpAll(loadVazirmatn);

  testWidgets('title, message and amount are shown', (tester) async {
    await tester.pumpWidget(_app());
    ZToast.show(
      _ctx,
      'جایزهٔ روزانه',
      message: 'به کیف سکه‌ت اضافه شد.',
      amount: '۲۰',
      kind: ZToastKind.coin,
    );
    await tester.pump();
    expect(find.text('جایزهٔ روزانه'), findsOneWidget);
    expect(find.text('به کیف سکه‌ت اضافه شد.'), findsOneWidget);
    expect(find.text('۲۰'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('one-liner has no message line and no amount chip', (
    tester,
  ) async {
    await tester.pumpWidget(_app());
    ZToast.show(_ctx, 'اتصال قطع شد');
    await tester.pump();
    expect(find.byType(Text), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('floats 52 below the safe area, 12 gutters, 372 max', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(412, 892);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_app(reduceMotion: true));
    ZToast.show(_ctx, 'سلام');
    await tester.pump();
    final rect = tester.getRect(_card);
    expect(rect.top, 52);
    expect(rect.width, 372);
    expect(rect.left, 20);
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('drops in with the spring and fades in', (tester) async {
    await tester.pumpWidget(_app());
    ZToast.show(_ctx, 'سلام');
    await tester.pump();
    final start = tester.getTopLeft(_card).dy;
    expect(start, lessThan(52 - 40));
    await tester.pump(const Duration(milliseconds: 600));
    expect(tester.getTopLeft(_card).dy, 52);
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('drains and dismisses itself after the duration', (tester) async {
    await tester.pumpWidget(_app(reduceMotion: true));
    ZToast.show(_ctx, 'سلام', duration: const Duration(seconds: 2));
    await tester.pump();
    expect(find.byType(ZToastCard), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 1900));
    expect(find.byType(ZToastCard), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byType(ZToastCard), findsNothing);
  });

  testWidgets('✕ dismisses at once and is a 44 dp target', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(_app(reduceMotion: true));
    ZToast.show(_ctx, 'سلام');
    await tester.pump();
    final size = tester.getSize(
      find.descendant(
        of: find.byType(ZToastCard),
        matching: find.byType(GestureDetector),
      ),
    );
    expect(size, const Size(44, 44));
    expect(find.bySemanticsLabel('بستن'), findsOneWidget);
    await tester.tap(
      find.descendant(
        of: find.byType(ZToastCard),
        matching: find.byType(GestureDetector),
      ),
    );
    await tester.pump();
    expect(find.byType(ZToastCard), findsNothing);
    handle.dispose();
  });

  testWidgets('a new toast replaces the visible one', (tester) async {
    await tester.pumpWidget(_app(reduceMotion: true));
    ZToast.show(_ctx, 'اول');
    await tester.pump();
    ZToast.show(_ctx, 'دوم', kind: ZToastKind.error);
    await tester.pump();
    expect(find.text('اول'), findsNothing);
    expect(find.text('دوم'), findsOneWidget);
    expect(find.byType(ZToastCard), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('the card never blocks touches outside itself', (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      zTestApp(
        Builder(
          builder: (context) {
            _ctx = context;
            return Scaffold(
              body: Align(
                alignment: Alignment.bottomCenter,
                child: TextButton(
                  onPressed: () => taps++,
                  child: const Text('زیر'),
                ),
              ),
            );
          },
        ),
        reduceMotion: true,
      ),
    );
    ZToast.show(_ctx, 'سلام');
    await tester.pump();
    await tester.tap(find.text('زیر'));
    expect(taps, 1);
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('screen reader gets one live region with title and message', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(_app(reduceMotion: true));
    ZToast.show(_ctx, 'عنوان', message: 'پیام');
    await tester.pump();
    expect(
      tester.getSemantics(find.bySemanticsLabel('عنوان. پیام')),
      matchesSemantics(label: 'عنوان. پیام', isLiveRegion: true),
    );
    await tester.pump(const Duration(seconds: 5));
    handle.dispose();
  });

  testWidgets('the action runs once, then dismisses the toast', (tester) async {
    await tester.pumpWidget(_app(reduceMotion: true));
    var taps = 0;
    ZToast.show(_ctx, 'سؤال', actionLabel: 'گزارش بده', onAction: () => taps++);
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('z-toast-action')));
    await tester.pump();
    expect(taps, 1);
    expect(find.byType(ZToastCard), findsNothing);
  });

  testWidgets('no action label means no button', (tester) async {
    await tester.pumpWidget(_app(reduceMotion: true));
    ZToast.show(_ctx, 'سلام', onAction: () {});
    await tester.pump();
    expect(find.byType(Text), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
  });

  for (final b in Brightness.values) {
    testWidgets('kind colours come from the tokens — ${b.name}', (
      tester,
    ) async {
      await tester.pumpWidget(_app(reduceMotion: true, b: b));
      ZToast.show(_ctx, 'سلام', kind: ZToastKind.error);
      await tester.pump();
      final bar = tester.widget<ColoredBox>(
        find
            .descendant(
              of: find.byType(ZToastCard),
              matching: find.byType(ColoredBox),
            )
            .last,
      );
      expect(bar.color, _ctx.z.coral);
      await tester.pump(const Duration(seconds: 5));
    });
  }
}
