import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wordchain/core/utils/error_messages.dart';

void main() {
  test('every backend respondError code has a Persian translation', () {
    final handlerDir = Directory('../backend/internal/handler');
    final codeRe = RegExp(r'respondError\([^,]+,[^,]+,\s*"([a-z_]+)"');
    final codes = <String>{};
    for (final f in handlerDir.listSync().whereType<File>()) {
      if (!f.path.endsWith('.go') || f.path.endsWith('_test.go')) continue;
      codes.addAll(codeRe.allMatches(f.readAsStringSync()).map((m) => m[1]!));
    }
    expect(codes, isNotEmpty);
    final missing = codes.difference(translatedErrorCodes);
    expect(missing, isEmpty, reason: 'Add Persian text in error_messages.dart');
  });

  test('translations contain no Latin letters and unknown codes fall back', () {
    final latin = RegExp(r'[A-Za-z]');
    for (final c in translatedErrorCodes) {
      expect(latin.hasMatch(errorMessageFor(c)), isFalse, reason: c);
    }
    expect(errorMessageFor('nope'), genericErrorMessage);
    expect(errorMessageFor(null, fallback: 'x'), 'x');
  });
}
