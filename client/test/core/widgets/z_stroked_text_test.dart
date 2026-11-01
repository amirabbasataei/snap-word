import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wordchain/core/theme/app_theme.dart';
import 'package:wordchain/core/widgets/z_stroked_text.dart';

void main() {
  testWidgets('outline and fill are the same size under a small OS font', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(0.85)),
          child: const Scaffold(
            body: Center(
              child: ZStrokedText(
                'زنجیر',
                fontSize: 40,
                fill: Colors.red,
                stroke: 6,
              ),
            ),
          ),
        ),
      ),
    );
    // Text builds a RichText of its own; both layers must be 0.85-scaled.
    final scalers =
        tester
            .widgetList<RichText>(find.byType(RichText))
            .map((r) => r.textScaler)
            .toList();
    expect(scalers.length, 2);
    expect(scalers.every((s) => s == const TextScaler.linear(0.85)), isTrue);
  });
}
