import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wordchain/core/widgets/z_bottom_nav.dart';

import '../../helpers/z_test_app.dart';

void main() {
  setUpAll(loadVazirmatn);

  for (final brightness in Brightness.values) {
    for (final index in [0, 2]) {
      testWidgets('dock — ${brightness.name}, tab $index', (tester) async {
        tester.view.physicalSize = const Size(792, 220);
        tester.view.devicePixelRatio = 2;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          zTestApp(
            Scaffold(
              backgroundColor:
                  brightness == Brightness.light
                      ? const Color(0xFFF6F1E7)
                      : const Color(0xFF211D26),
              body: const SizedBox.expand(),
              bottomNavigationBar: ZBottomNav(
                currentIndex: index,
                friendsBadge: 2,
                onTap: (_) {},
              ),
            ),
            brightness: brightness,
          ),
        );
        await tester.pumpAndSettle();
        await expectLater(
          find.byType(Scaffold),
          matchesGoldenFile(
            'goldens/z_bottom_nav_${brightness.name}_$index.png',
          ),
        );
      });
    }
  }
}
