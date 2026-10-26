import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wordchain/core/theme/app_scene_tokens.dart';
import 'package:wordchain/features/game/view/widgets/z_opp_deciding.dart';

import '../../helpers/z_test_app.dart';

/// Canvas `ZOppDeciding` (Zanjir turn 15: 15a in context, 15b card only) over
/// the sky at 396×812. Rendered at 2×, not 1×: Chrome floors a 2.5px border to
/// 2px at 1× (and draws thin dashes 3:2 instead of 2:1), so a 1× golden would
/// not show the values a phone gets.
class _Backdrop extends StatelessWidget {
  final Widget child;
  const _Backdrop({required this.child});

  @override
  Widget build(BuildContext context) {
    final zs = context.zs;
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [zs.sky1, zs.sky2, zs.sky3],
          ),
        ),
        child: Stack(children: [child]),
      ),
    );
  }
}

void main() {
  setUpAll(loadVazirmatn);

  Future<void> shoot(
    WidgetTester tester,
    String name, {
    required Brightness brightness,
    required int remaining,
    String? lossReason,
  }) async {
    tester.view.physicalSize = const Size(792, 1624);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      zTestApp(
        _Backdrop(
          child: ZOppDecidingOverlay(
            remaining: remaining,
            lossReason: lossReason,
          ),
        ),
        brightness: brightness,
        reduceMotion: true,
      ),
    );
    // The mascot loops forever, so settle by time, not pumpAndSettle.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/z_opp_deciding_$name.png'),
    );
  }

  testWidgets('15aL — rejected word, 11 s left, light', (tester) async {
    await shoot(tester, '15aL', brightness: Brightness.light, remaining: 11);
  });

  testWidgets('15aD — last seconds, dark', (tester) async {
    await shoot(tester, '15aD', brightness: Brightness.dark, remaining: 2);
  });
}
