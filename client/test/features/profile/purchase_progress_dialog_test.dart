import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wordchain/core/theme/app_theme.dart';
import 'package:wordchain/features/profile/view/widgets/purchase_progress_dialog.dart';

void main() {
  testWidgets('blocks the screen until the purchase closes it', (tester) async {
    late BuildContext ctx;
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: Builder(
            builder: (c) {
              ctx = c;
              return Center(
                child: ElevatedButton(
                  onPressed: () => taps++,
                  child: const Text('buy'),
                ),
              );
            },
          ),
        ),
      ),
    );

    final close = showPurchaseProgress(ctx);
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('در حال اتصال به کافه‌بازار…'), findsOneWidget);

    // The scrim swallows taps and back does not dismiss it.
    await tester.tapAt(const Offset(20, 20));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('در حال اتصال به کافه‌بازار…'), findsOneWidget);
    expect(taps, 0);

    close();
    close(); // closing twice is harmless
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('در حال اتصال به کافه‌بازار…'), findsNothing);
  });
}
