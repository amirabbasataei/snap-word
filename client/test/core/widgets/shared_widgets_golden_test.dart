import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wordchain/core/theme/app_spacing.dart';
import 'package:wordchain/core/widgets/avatar_tile.dart';
import 'package:wordchain/core/widgets/coin_pill.dart';
import 'package:wordchain/core/widgets/letter_tile.dart';
import 'package:wordchain/core/widgets/section_header.dart';
import 'package:wordchain/core/widgets/solid_card.dart';
import 'package:wordchain/core/widgets/tint_chip.dart';
import 'package:wordchain/core/widgets/z_bottom_nav.dart';
import 'package:wordchain/core/widgets/z_buttons.dart';

import '../../helpers/z_test_app.dart';

// StreakStrip is excluded: it derives its day labels from DateTime.now(),
// which would make the golden change daily.
Widget _gallery() {
  return Scaffold(
    body: Padding(
      padding: const EdgeInsets.all(ZSpacing.screenGutter),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Row(
            children: [
              LetterTile(letter: 'ز', accent: ZAccent.indigo, size: 42),
              SizedBox(width: 8),
              LetterTile(letter: 'ن', accent: ZAccent.teal, size: 42, rotation: 0.08),
              SizedBox(width: 8),
              LetterTile(letter: 'ج', accent: ZAccent.amber, size: 42),
              SizedBox(width: 8),
              LetterTile(letter: 'ی', accent: ZAccent.coral, size: 42, rotation: -0.08),
              SizedBox(width: 8),
              LetterTile(letter: 'ر', accent: ZAccent.neutral, size: 42),
            ],
          ),
          const SizedBox(height: 14),
          const Row(
            children: [
              CoinPill(amount: 1240),
              SizedBox(width: 8),
              TintChip(label: 'ایندیگو'),
              SizedBox(width: 8),
              TintChip(label: 'فیروزه‌ای', tint: ZTint.teal),
              SizedBox(width: 8),
              TintChip(label: 'مرجانی', tint: ZTint.coral),
            ],
          ),
          const SizedBox(height: 14),
          const Row(
            children: [
              AvatarTile(name: 'مریم'),
              SizedBox(width: 8),
              AvatarTile(name: 'علی', size: 56),
            ],
          ),
          const SizedBox(height: 14),
          const SectionHeader(title: 'عنوان بخش'),
          const SizedBox(height: 8),
          const SolidCard(child: Text('کارت با لبهٔ سخت')),
          const SizedBox(height: 14),
          AccentButton(label: 'شروع بازی', onPressed: () {}),
          const SizedBox(height: 8),
          AccentButton(label: 'ادامه', accent: ZAccentColor.teal, onPressed: () {}),
          const SizedBox(height: 8),
          NeutralButton(label: 'انصراف', onPressed: () {}),
        ],
      ),
    ),
    bottomNavigationBar: ZBottomNav(currentIndex: 0, onTap: (_) {}),
  );
}

void main() {
  setUpAll(loadVazirmatn);

  for (final brightness in Brightness.values) {
    testWidgets('shared widgets — ${brightness.name}', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(zTestApp(_gallery(), brightness: brightness));
      await expectLater(
        find.byType(Scaffold),
        matchesGoldenFile('goldens/shared_widgets_${brightness.name}.png'),
      );
    });
  }
}
