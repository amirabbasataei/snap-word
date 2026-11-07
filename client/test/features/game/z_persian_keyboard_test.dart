import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wordchain/core/services/dictionary_service.dart';
import 'package:wordchain/features/game/view/widgets/z_persian_keyboard.dart';

import '../../helpers/z_test_app.dart';

/// Every letter of the Persian alphabet (32) plus «آ» and the hamza forms the
/// game accepts, and the half-space.
const _alphabet = 'ابپتثجچحخدذرزژسشصضطظعغفقکگلمنوهی';
const _extras = 'آؤءأئ';

void main() {
  late TextEditingController c;

  setUp(() => c = TextEditingController());
  tearDown(() => c.dispose());

  Future<void> pump(
    WidgetTester tester, {
    bool enabled = true,
    Brightness brightness = Brightness.light,
    VoidCallback? onSend,
    double width = 393,
    double height = 852,
  }) async {
    tester.view
      ..physicalSize = Size(width, height)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await loadVazirmatn();
    await tester.pumpWidget(
      zTestApp(
        Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: ZPersianKeyboard(
              controller: c,
              enabled: enabled,
              onSend: onSend ?? () {},
            ),
          ),
        ),
        brightness: brightness,
      ),
    );
  }

  group('layout', () {
    test('has every Persian letter, the hamza forms and the half-space', () {
      final keys = ZKeyboardLayout.allKeys;
      for (final ch in '$_alphabet$_extras'.split('')) {
        expect(keys, contains(ch), reason: 'missing $ch');
      }
      expect(keys, contains(ZKeyboardLayout.zwnj));
      expect(keys.length, _alphabet.length + _extras.length + 1);
    });

    test('no key is typed twice and every key is allowed in a word', () {
      final all = [
        for (final r in ZKeyboardLayout.rows) ...r,
        ...ZKeyboardLayout.bottomRight,
        ...ZKeyboardLayout.bottomLeft,
        ZKeyboardLayout.zwnj,
      ];
      expect(all.toSet().length, all.length);
      for (final ch in all) {
        expect(
          DictionaryService.hasValidChars(ch),
          isTrue,
          reason: 'U+${ch.codeUnitAt(0).toRadixString(16)} is not allowed',
        );
      }
    });

    test('rows add up to 11 keys: 11 / 11 / 10 + backspace', () {
      expect([for (final r in ZKeyboardLayout.rows) r.length], [11, 11, 10]);
    });
  });

  group('editing', () {
    test('insert appends at the end when there is no caret', () {
      c.text = 'سی';
      ZKeyboardEditing.insert(c, 'ب');
      expect(c.text, 'سیب');
      expect(c.selection, const TextSelection.collapsed(offset: 3));
    });

    test('insert goes at the caret and replaces a selection', () {
      c.value = const TextEditingValue(
        text: 'سب',
        selection: TextSelection.collapsed(offset: 1),
      );
      ZKeyboardEditing.insert(c, 'ی');
      expect(c.text, 'سیب');
      c.selection = const TextSelection(baseOffset: 0, extentOffset: 3);
      ZKeyboardEditing.insert(c, 'آ');
      expect(c.text, 'آ');
    });

    test('half-space is ignored first and doubled, allowed inside', () {
      ZKeyboardEditing.insert(c, ZKeyboardLayout.zwnj);
      expect(c.text, '');
      ZKeyboardEditing.insert(c, 'می');
      ZKeyboardEditing.insert(c, ZKeyboardLayout.zwnj);
      ZKeyboardEditing.insert(c, ZKeyboardLayout.zwnj);
      ZKeyboardEditing.insert(c, 'رم');
      expect(c.text, 'می‌رم');
    });

    test('backspace removes one character, a selection, or nothing', () {
      c.text = 'سیب';
      ZKeyboardEditing.backspace(c);
      expect(c.text, 'سی');
      c.value = const TextEditingValue(
        text: 'سیب',
        selection: TextSelection(baseOffset: 1, extentOffset: 3),
      );
      ZKeyboardEditing.backspace(c);
      expect(c.text, 'س');
      c.value = const TextEditingValue(
        text: 'سیب',
        selection: TextSelection.collapsed(offset: 2),
      );
      ZKeyboardEditing.backspace(c);
      expect(c.text, 'سب');
      expect(c.selection.baseOffset, 1);
      c.value = const TextEditingValue(
        text: 'سب',
        selection: TextSelection.collapsed(offset: 0),
      );
      ZKeyboardEditing.backspace(c);
      expect(c.text, 'سب');
      c.clear();
      ZKeyboardEditing.backspace(c);
      expect(c.text, '');
    });
  });

  group('widget', () {
    testWidgets('shows every key and nothing else (no digits, no space)', (
      tester,
    ) async {
      await pump(tester);
      for (final ch in '$_alphabet$_extras'.split('')) {
        expect(find.bySemanticsLabel(ch), findsOneWidget, reason: ch);
      }
      expect(find.bySemanticsLabel('نیم‌فاصله'), findsOneWidget);
      expect(find.bySemanticsLabel('پاک کردن'), findsOneWidget);
      expect(find.bySemanticsLabel('بفرست'), findsOneWidget);
      // 33 letters + half-space + backspace + send.
      expect(find.byType(Listener).evaluate().length, greaterThanOrEqualTo(36));
      for (final d in '۰۱۲۳۴۵۶۷۸۹0123456789'.split('')) {
        expect(find.text(d), findsNothing);
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('send is bottom-right, backspace one key wide above it', (
      tester,
    ) async {
      await pump(tester);
      Rect r(String label) => tester.getRect(find.bySemanticsLabel(label));
      final send = r('بفرست');
      final back = r('پاک کردن');
      final letter = r('ب');
      final all = tester.getRect(find.byType(ZPersianKeyboard));
      // Send takes the bottom-right corner; backspace is directly above it,
      // flush with the right edge, and exactly one letter key wide.
      expect(send.right, greaterThan(all.right - 8));
      expect(back.right, closeTo(send.right, 2));
      expect(back.bottom, lessThanOrEqualTo(send.top));
      expect(back.width, closeTo(letter.width, 1));
      expect(send.width, greaterThan(back.width * 2));
      // «آ» lives on the bottom row, next to send; the half-space is the
      // widest key there (the space it freed went to it).
      expect(r('آ').center.dy, closeTo(send.center.dy, 1));
      expect(r('آ').right, lessThanOrEqualTo(send.left));
      final half = r('نیم‌فاصله');
      expect(half.center.dy, closeTo(send.center.dy, 1));
      expect(half.width, greaterThan(send.width));
      expect(half.width, greaterThan(letter.width * 3));
    });

    testWidgets('tapping keys types a word, backspace and half-space work', (
      tester,
    ) async {
      await pump(tester);
      for (final ch in ['م', 'ی']) {
        await tester.tap(find.bySemanticsLabel(ch));
      }
      await tester.tap(find.bySemanticsLabel('نیم‌فاصله'));
      await tester.tap(find.bySemanticsLabel('ر'));
      await tester.tap(find.bySemanticsLabel('ؤ'));
      await tester.pump();
      expect(c.text, 'می‌رؤ');
      await tester.tap(find.bySemanticsLabel('پاک کردن'));
      await tester.pump();
      expect(c.text, 'می‌ر');
    });

    testWidgets('holding backspace keeps deleting', (tester) async {
      await pump(tester);
      c.text = 'سرگرمی';
      final g = await tester.startGesture(
        tester.getCenter(find.bySemanticsLabel('پاک کردن')),
      );
      await tester.pump(const Duration(milliseconds: 380));
      await tester.pump(const Duration(milliseconds: 70 * 3));
      await g.up();
      await tester.pump();
      expect(c.text.length, lessThan(4));
      final left = c.text;
      await tester.pump(const Duration(seconds: 1));
      expect(c.text, left, reason: 'stops after release');
    });

    testWidgets('keyboard removed while a key is held: no error', (
      tester,
    ) async {
      await pump(tester);
      final g = await tester.startGesture(
        tester.getCenter(find.bySemanticsLabel('پاک کردن')),
      );
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 300));
      await g.up();
      await tester.pump();
      expect(tester.takeException(), isNull);
    });

    testWidgets('send fires on release, once', (tester) async {
      var sent = 0;
      await pump(tester, onSend: () => sent++);
      final g = await tester.startGesture(
        tester.getCenter(find.bySemanticsLabel('بفرست')),
      );
      await tester.pump();
      expect(sent, 0);
      await g.up();
      await tester.pump();
      expect(sent, 1);
    });

    testWidgets('disabled: touches do nothing', (tester) async {
      var sent = 0;
      await pump(tester, enabled: false, onSend: () => sent++);
      await tester.tap(find.bySemanticsLabel('ب'), warnIfMissed: false);
      await tester.tap(find.bySemanticsLabel('بفرست'), warnIfMissed: false);
      await tester.pump();
      expect(c.text, '');
      expect(sent, 0);
    });

    for (final brightness in Brightness.values) {
      for (final size in const [
        Size(320, 568),
        Size(360, 640),
        Size(430, 932),
      ]) {
        testWidgets(
          '${brightness.name} ${size.width.toInt()}×${size.height.toInt()}: '
          'no overflow, fixed height',
          (tester) async {
            await pump(
              tester,
              brightness: brightness,
              width: size.width,
              height: size.height,
            );
            expect(tester.takeException(), isNull);
            final box = tester.getRect(find.byType(ZPersianKeyboard));
            expect(box.width, size.width);
            // Four rows must stay a modest slice of the screen.
            expect(box.height / size.height, lessThan(.4));
            // Letter keys never get narrower than a finger-friendly 26dp.
            final key = tester.getRect(find.bySemanticsLabel('ب'));
            expect(key.width, greaterThanOrEqualTo(26));
          },
        );
      }
    }
  });
}
