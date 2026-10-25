import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wordchain/core/theme/app_theme.dart';
import 'package:wordchain/features/auth/view/widgets/phone_input_field.dart';

String? reported;

Future<void> pumpField(WidgetTester tester) async {
  reported = null;
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          body: PhoneInputField(onDigitsChanged: (d) => reported = d),
        ),
      ),
    ),
  );
}

String shown(WidgetTester tester) =>
    tester.widget<TextField>(find.byType(TextField)).controller!.text;

void main() {
  group('extractPhoneDigits', () {
    test('folds Persian and Arabic-Indic digits and drops the rest', () {
      expect(extractPhoneDigits('۰۹۱۲ ۳۴۵-۶۷۸۹'), '09123456789');
      expect(extractPhoneDigits('٠٩١٢٣٤٥٦٧٨٩'), '09123456789');
      expect(extractPhoneDigits('+98 (912) 345 6789'), '989123456789');
      expect(extractPhoneDigits('abc'), '');
    });
  });

  group('typing', () {
    testWidgets('the fixed 09 is added; the display is grouped, Persian, LTR', (
      tester,
    ) async {
      await pumpField(tester);
      expect(find.text('۰۹'), findsOneWidget);
      await tester.enterText(find.byType(TextField), '936');
      expect(shown(tester), '۹۳ ۶');
      await tester.enterText(find.byType(TextField), '93644');
      expect(shown(tester), '۹۳ ۶۴۴');
      await tester.enterText(find.byType(TextField), '936441997');
      expect(shown(tester), '۹۳ ۶۴۴ ۱۹۹۷');
      expect(reported, '09936441997');
    });

    for (final input in ['364419970', '۳۶۴۴۱۹۹۷۰', '٣٦٤٤١٩٩٧٠']) {
      testWidgets('digits "$input" give the same number', (tester) async {
        await pumpField(tester);
        await tester.enterText(find.byType(TextField), input);
        expect(reported, '09364419970');
        expect(shown(tester), '۳۶ ۴۴۱ ۹۹۷۰');
      });
    }

    testWidgets('anything past nine digits is cut off', (tester) async {
      await pumpField(tester);
      await tester.enterText(find.byType(TextField), '3644199701234');
      expect(reported, '09364419970');
    });

    testWidgets('letters and symbols never get in', (tester) async {
      await pumpField(tester);
      await tester.enterText(find.byType(TextField), 'ab3-6 x');
      expect(reported, '0936');
    });
  });

  group('pasting a whole number', () {
    for (final (name, text) in [
      ('09…', '09364419970'),
      ('Persian 09…', '۰۹۳۶۴۴۱۹۹۷۰'),
      ('+98…', '+98 936 441 9970'),
      ('0098…', '00989364419970'),
      ('98…', '989364419970'),
      ('with dashes', '0936-441-9970'),
    ]) {
      testWidgets(name, (tester) async {
        await pumpField(tester);
        await tester.enterText(find.byType(TextField), text);
        expect(reported, '09364419970');
        expect(shown(tester), '۳۶ ۴۴۱ ۹۹۷۰');
      });
    }
  });

  testWidgets('an empty field reports the bare prefix', (tester) async {
    await pumpField(tester);
    await tester.enterText(find.byType(TextField), '3');
    await tester.enterText(find.byType(TextField), '');
    expect(reported, '09');
  });
}
