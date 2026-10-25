import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wordchain/core/widgets/z_empty_state.dart';
import 'package:wordchain/core/widgets/z_load_state.dart';
import 'package:wordchain/core/widgets/z_mascot.dart';

import '../../helpers/z_test_app.dart';

Widget _app(
  ZLoadState child, {
  bool reduceMotion = true,
  Brightness brightness = Brightness.light,
  double textScale = 1,
}) => zTestApp(
  Builder(
    builder:
        (context) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: Scaffold(
            body: Center(child: SizedBox(width: 280, child: child)),
          ),
        ),
  ),
  brightness: brightness,
  reduceMotion: reduceMotion,
);

void main() {
  setUpAll(loadVazirmatn);

  group('loading', () {
    testWidgets('a thinking mascot and a short Persian label', (tester) async {
      await tester.pumpWidget(_app(const ZLoadState.loading()));

      expect(
        tester.widget<ZMascot>(find.byType(ZMascot)).mood,
        ZMascotMood.thinking,
      );
      expect(find.text(ZLoadState.loadingLabel), findsOneWidget);
      expect(find.text('تلاش دوباره'), findsNothing);
    });

    testWidgets('is announced to screen readers once, as a live region', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(_app(const ZLoadState.loading()));
      final node = tester.getSemantics(find.text(ZLoadState.loadingLabel));
      expect(node.label, ZLoadState.loadingLabel);
      expect(node.flagsCollection.isLiveRegion, isTrue);
      handle.dispose();
    });

    testWidgets('reduced motion: nothing keeps scheduling frames', (
      tester,
    ) async {
      await tester.pumpWidget(_app(const ZLoadState.loading()));
      await tester.pump(const Duration(seconds: 1));
      expect(tester.binding.hasScheduledFrame, isFalse);
    });
  });

  group('error', () {
    testWidgets('a sad mascot, the message and a retry', (tester) async {
      var retries = 0;
      await tester.pumpWidget(
        _app(
          ZLoadState.error(
            message: 'خطا در اتصال به اینترنت',
            onRetry: () => retries++,
          ),
        ),
      );

      expect(find.text('خطا در اتصال به اینترنت'), findsOneWidget);
      expect(
        tester.widget<ZMascot>(find.byType(ZMascot)).mood,
        ZMascotMood.sad,
      );
      expect(find.byType(ZEmptyState), findsOneWidget);

      await tester.tap(find.text(ZLoadState.retryLabel));
      expect(retries, 1);
    });
  });

  for (final brightness in Brightness.values) {
    for (final scale in [1.0, 1.6, 2.0]) {
      testWidgets('no overflow ×$scale ${brightness.name}', (tester) async {
        await tester.pumpWidget(
          _app(
            const ZLoadState.loading(),
            brightness: brightness,
            textScale: scale,
          ),
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(
          _app(
            ZLoadState.error(
              message: 'بارگذاری دوستان ناموفق بود، لطفاً دوباره تلاش کن',
              onRetry: () {},
            ),
            brightness: brightness,
            textScale: scale,
          ),
        );
        expect(tester.takeException(), isNull);
      });
    }
  }
}
