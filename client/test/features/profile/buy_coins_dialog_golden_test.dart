import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wordchain/core/services/store_purchase_service.dart';
import 'package:wordchain/core/theme/app_scene_tokens.dart';
import 'package:wordchain/core/widgets/z_dialog.dart';
import 'package:wordchain/features/profile/view/widgets/buy_coins_dialog.dart';

import '../../helpers/z_test_app.dart';

/// Canvas `ZCoinShop`, frames 17a (picking) and 17b (connecting, then done),
/// 396×812 as in the canvas preview, light and dark.
void main() {
  setUpAll(loadVazirmatn);

  Future<Completer<StorePurchaseResult?>> open(
    WidgetTester tester,
    Brightness brightness, {
    List<String>? asked,
  }) async {
    tester.view.physicalSize = const Size(396, 812);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final pending = Completer<StorePurchaseResult?>();
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
    showBuyCoinsDialog(
      ctx,
      balance: 120,
      onBuy: (id) {
        asked?.add(id);
        return pending.future;
      },
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    return pending;
  }

  Future<void> shot(WidgetTester tester, String name) => expectLater(
    find.byType(MaterialApp),
    matchesGoldenFile('goldens/buy_coins_$name.png'),
  );

  for (final b in Brightness.values) {
    testWidgets('17a pick — ${b.name}', (tester) async {
      await open(tester, b);
      // The canvas card: 372 wide, 550.35 tall (padding + three 72 rows + 56
      // button), rows 72, button 56.
      final card = tester.getRect(find.byType(ZDialogCard));
      expect(card.width, 372);
      expect(card.height, closeTo(550.35 + 6, .5)); // + the 6dp solid edge
      await shot(tester, 'pick_${b.name}');
    });

    testWidgets('17a pick, large pack — ${b.name}', (tester) async {
      await open(tester, b);
      await tester.tap(find.text('۱٬۵۰۰'));
      await tester.pump(const Duration(milliseconds: 200));
      await shot(tester, 'pick_large_${b.name}');
    });

    testWidgets('17b connecting — ${b.name}', (tester) async {
      final asked = <String>[];
      await open(tester, b, asked: asked);
      await tester.tap(find.text('پرداخت ۲۵٬۰۰۰ تومان'));
      await tester.pump(const Duration(milliseconds: 200));
      expect(asked, ['coins_350']);
      expect(find.text('در حال اتصال به کافه‌بازار…'), findsOneWidget);
      await shot(tester, 'paying_${b.name}');
    });

    testWidgets('17b done — ${b.name}', (tester) async {
      final pending = await open(tester, b);
      await tester.tap(find.text('پرداخت ۲۵٬۰۰۰ تومان'));
      await tester.pump();
      pending.complete(
        const StorePurchaseResult(
          StorePurchaseStatus.success,
          'ok',
          coins: 470,
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('۳۵۰ سکه اضافه شد!'), findsOneWidget);
      await shot(tester, 'done_${b.name}');
    });
  }

  testWidgets('a failed purchase returns to the picker', (tester) async {
    final pending = await open(tester, Brightness.light);
    await tester.tap(find.text('پرداخت ۲۵٬۰۰۰ تومان'));
    await tester.pump();
    pending.complete(
      const StorePurchaseResult(StorePurchaseStatus.cancelled, 'لغو'),
    );
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('پرداخت ۲۵٬۰۰۰ تومان'), findsOneWidget);
  });

  testWidgets('cannot be closed while connecting', (tester) async {
    await open(tester, Brightness.light);
    await tester.tap(find.text('پرداخت ۲۵٬۰۰۰ تومان'));
    await tester.pump();
    await tester.tapAt(const Offset(5, 5)); // scrim
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(BuyCoinsDialog), findsOneWidget);
  });
}
