import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wordchain/features/home/view/widgets/home_level_dialog.dart';

import '../../helpers/z_test_app.dart';

/// A stand-in for the Home «حریف هوشمند» button; the chosen level is stored
/// in [picked].
class _Host extends StatefulWidget {
  final ValueChanged<String?> onResult;

  const _Host(this.onResult);

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: TextButton(
        onPressed: () async => widget.onResult(await showAiLevelDialog(context)),
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
  ValueChanged<String?> onResult, {
  Brightness brightness = Brightness.light,
}) async {
  await tester.pumpWidget(
    zTestApp(
      _Host(onResult),
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

  test('levels are the real ones, keyed by the opponent types the game takes', () {
    expect(aiLevels.map((l) => l.id), ['ai_easy', 'ai_medium', 'ai_hard']);
    expect(aiLevels.map((l) => l.title), ['آسان', 'متوسط', 'سخت']);
    expect(aiLevels.map((l) => l.name), ['خواب‌آلود', 'هوشیار', 'بدقلق']);
    expect(aiLevels.map((l) => l.speed), [1, 2, 3]);
    expect(aiDefaultLevel, 'ai_medium');
  });

  testWidgets('shows the canvas copy and no seconds', (tester) async {
    _size(tester, 396, 812);
    await _open(tester, (_) {});
    expect(find.text('سطح حریف را انتخاب کن'), findsOneWidget);
    expect(find.text('هرچه سخت‌تر، سریع‌تر و کم‌اشتباه‌تر'), findsOneWidget);
    for (final l in aiLevels) {
      expect(find.text(l.title), findsOneWidget);
      expect(find.text(l.name), findsOneWidget);
    }
    expect(find.text('سرعت'), findsNWidgets(3));
    expect(find.textContaining('ثانیه'), findsNothing);
    expect(find.text('شروع بازی'), findsOneWidget);
  });

  testWidgets('medium is preselected, and starting returns it', (tester) async {
    _size(tester, 396, 812);
    String? result = 'unset';
    await _open(tester, (r) => result = r);

    await tester.tap(find.text('شروع بازی'));
    await _settle(tester);

    expect(result, 'ai_medium');
    expect(find.text('شروع بازی'), findsNothing);
  });

  testWidgets('picking a card only selects; the CTA starts', (tester) async {
    _size(tester, 396, 812);
    String? result = 'unset';
    await _open(tester, (r) => result = r);

    await tester.tap(find.text('سخت'));
    await tester.pump();
    // Still open, nothing returned yet.
    expect(result, 'unset');
    expect(find.text('شروع بازی'), findsOneWidget);

    await tester.tap(find.text('شروع بازی'));
    await _settle(tester);
    expect(result, 'ai_hard');
  });

  testWidgets('selection is exposed to accessibility as a radio group', (
    tester,
  ) async {
    _size(tester, 396, 812);
    final handle = tester.ensureSemantics();
    await _open(tester, (_) {});

    Matcher checked(bool on) =>
        isSemantics(hasCheckedState: true, isChecked: on);
    Finder card(String label) => find.bySemanticsLabel(RegExp(label));
    expect(tester.getSemantics(card('متوسط، هوشیار')), checked(true));
    expect(tester.getSemantics(card('آسان، خواب‌آلود')), checked(false));

    await tester.tap(find.text('آسان'));
    await tester.pump();
    expect(tester.getSemantics(card('آسان، خواب‌آلود')), checked(true));
    expect(tester.getSemantics(card('متوسط، هوشیار')), checked(false));
    handle.dispose();
  });

  testWidgets('the close button returns null (no game starts)', (tester) async {
    _size(tester, 396, 812);
    String? result = 'unset';
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
    expect(find.text('شروع بازی'), findsNothing);
  });

  testWidgets('tapping the scrim closes it without starting', (tester) async {
    _size(tester, 396, 812);
    String? result = 'unset';
    await _open(tester, (r) => result = r);

    await tester.tapAt(const Offset(4, 4));
    await _settle(tester);
    expect(result, isNull);
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
          await _open(tester, (_) {}, brightness: b);
          expect(tester.takeException(), isNull);
          expect(find.text('شروع بازی'), findsOneWidget);
        },
      );
    }
  }

  for (final b in Brightness.values) {
    testWidgets('golden ${b.name}', (tester) async {
      _size(tester, 396, 812);
      await _open(tester, (_) {}, brightness: b);
      await expectLater(
        find.byType(View).first,
        matchesGoldenFile('goldens/ai_level_dialog_${b.name}.png'),
      );
    });
  }
}
