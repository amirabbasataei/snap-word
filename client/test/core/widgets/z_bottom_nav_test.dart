import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wordchain/core/widgets/z_bottom_nav.dart';

import '../../helpers/z_test_app.dart';

void main() {
  Future<void> pump(
    WidgetTester tester, {
    int index = 0,
    int badge = 0,
    ValueChanged<int>? onTap,
    Brightness brightness = Brightness.light,
    Size size = const Size(393, 852),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      zTestApp(
        Scaffold(
          bottomNavigationBar: ZBottomNav(
            currentIndex: index,
            friendsBadge: badge,
            onTap: onTap ?? (_) {},
          ),
        ),
        brightness: brightness,
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('reports tab indices in tab order', (tester) async {
    final tapped = <int>[];
    await pump(tester, onTap: tapped.add);
    for (final label in ['جدول', 'دوستان', 'من', 'خانه']) {
      await tester.tap(find.text(label));
    }
    expect(tapped, [1, 2, 3, 0]);
  });

  testWidgets('home sits at the right (RTL), me at the left', (tester) async {
    await pump(tester);
    final home = tester.getCenter(find.text('خانه')).dx;
    final me = tester.getCenter(find.text('من')).dx;
    expect(home, greaterThan(me));
  });

  testWidgets('badge shows Persian digits and hides on the friends tab', (
    tester,
  ) async {
    await pump(tester, badge: 2);
    expect(find.text('۲'), findsOneWidget);
    await pump(tester, index: ZBottomNav.friendsIndex, badge: 2);
    expect(find.text('۲'), findsNothing);
    await pump(tester, badge: 250);
    expect(find.text('۹۹+'), findsOneWidget);
  });

  testWidgets('selected tab is exposed to accessibility', (tester) async {
    await pump(tester, index: 1);
    expect(
      tester.getSemantics(find.bySemanticsLabel('جدول')),
      matchesSemantics(
        label: 'جدول',
        isButton: true,
        isSelected: true,
        hasSelectedState: true,
        hasTapAction: true,
        hasEnabledState: false,
      ),
    );
  });

  testWidgets('pressed tab sinks and springs back', (tester) async {
    await pump(tester);
    final glyph = find.byType(SvgPicture).at(3); // «من», not selected
    final rest = tester.getTopLeft(glyph).dy;
    final gesture = await tester.startGesture(tester.getCenter(glyph));
    await tester.pump(const Duration(milliseconds: 200)); // press timeout
    await tester.pump(const Duration(milliseconds: 200)); // animation
    expect(tester.getTopLeft(glyph).dy, closeTo(rest + 2, .5));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(glyph).dy, closeTo(rest, .5));
  });

  testWidgets('tap targets are at least 44dp', (tester) async {
    await pump(tester);
    final nav = tester.getRect(find.byType(ZBottomNav));
    for (final label in ['خانه', 'جدول', 'دوستان', 'من']) {
      // The tab's tappable box is the full-height cell around its label.
      final cell = tester.getRect(
        find
            .ancestor(of: find.text(label), matching: find.byType(SizedBox))
            .first,
      );
      expect(cell.height, greaterThanOrEqualTo(44));
    }
    expect(nav.height, greaterThan(44));
  });

  for (final brightness in Brightness.values) {
    for (final w in [320.0, 360.0, 430.0]) {
      testWidgets('no overflow at ${w.toInt()}dp — ${brightness.name}', (
        tester,
      ) async {
        await pump(
          tester,
          index: 2,
          badge: 12,
          brightness: brightness,
          size: Size(w, 640),
        );
        expect(tester.takeException(), isNull);
        await pump(
          tester,
          index: 3,
          badge: 12,
          brightness: brightness,
          size: Size(w, 640),
        );
        expect(tester.takeException(), isNull);
      });
    }
  }
}
