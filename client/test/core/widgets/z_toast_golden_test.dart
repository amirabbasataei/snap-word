import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wordchain/core/theme/app_scene_tokens.dart';
import 'package:wordchain/core/widgets/z_toast.dart';

import '../../helpers/z_test_app.dart';

/// Canvas frames 16a/16b: every toast kind on the sky scene, light and dark.
/// Reduced motion lands the card in its resting pose on the first frame, with
/// the drain bar still full.
Widget _kinds() => Builder(
  builder: (context) {
    final zs = context.zs;
    return Align(
      alignment: Alignment.topLeft,
      child: RepaintBoundary(
        key: const ValueKey('frame'),
        child: Container(
          width: 372,
          padding: const EdgeInsets.symmetric(vertical: 18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [zs.sky1, zs.sky2, zs.sky3],
              stops: const [0, .6, 1],
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            spacing: 16,
            children: const [
              ZToastCard(
                title: 'آفرین! کلمه قبول شد',
                message: 'زنجیر ادامه داره — نوبت حریفه.',
              ),
              ZToastCard(
                kind: ZToastKind.error,
                title: 'این کلمه قبلاً اومده',
                message: 'یه کلمهٔ دیگه با «ر» پیدا کن.',
              ),
              ZToastCard(
                kind: ZToastKind.info,
                title: 'حریف وصل شد',
                message: 'بازی تا چند لحظهٔ دیگه شروع می‌شه.',
              ),
              ZToastCard(
                kind: ZToastKind.coin,
                title: 'جایزهٔ روزانه',
                message: 'به کیف سکه‌ت اضافه شد.',
                amount: '۲۰',
              ),
              ZToastCard(
                kind: ZToastKind.info,
                title: 'اتصال قطع شد، دوباره تلاش می‌کنیم…',
              ),
            ],
          ),
        ),
      ),
    );
  },
);

void main() {
  setUpAll(loadVazirmatn);

  for (final brightness in Brightness.values) {
    testWidgets('16b all kinds — ${brightness.name}', (tester) async {
      tester.view.physicalSize = const Size(744, 1280);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        zTestApp(
          Scaffold(backgroundColor: Colors.transparent, body: _kinds()),
          brightness: brightness,
          reduceMotion: true,
        ),
      );
      await tester.pump();
      await expectLater(
        find.byKey(const ValueKey('frame')),
        matchesGoldenFile('goldens/z_toast_kinds_${brightness.name}.png'),
      );
    });
  }

  for (final brightness in Brightness.values) {
    testWidgets('16a floating over the screen — ${brightness.name}', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(412, 892);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      late BuildContext ctx;
      await tester.pumpWidget(
        zTestApp(
          Builder(
            builder: (context) {
              ctx = context;
              return RepaintBoundary(
                key: const ValueKey('frame'),
                child: Scaffold(backgroundColor: context.zs.sky3),
              );
            },
          ),
          brightness: brightness,
          reduceMotion: true,
        ),
      );
      ZToast.show(
        ctx,
        'آفرین! کلمه قبول شد',
        message: 'زنجیر ادامه داره — نوبت حریفه.',
        kind: ZToastKind.success,
      );
      await tester.pump();
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/z_toast_floating_${brightness.name}.png'),
      );
      await tester.pump(const Duration(seconds: 5));
    });
  }
}
