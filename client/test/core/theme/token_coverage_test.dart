import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Screens and shared widgets must read colours from `context.z` tokens
/// (CLAUDE.md § Visual system rules). Fails on hex literals, named
/// Material colours, or the removed legacy `AppColors` palette.
void main() {
  test('no hardcoded colours outside core/theme', () {
    final forbidden = RegExp(
      r'Color\(0x|AppColors\.|Colors\.(white|black|red|green|blue|grey|amber|orange|yellow|purple|pink|teal|indigo)',
    );
    final offenders = <String>[];
    for (final dir in ['lib/features', 'lib/core/widgets', 'lib/core/router']) {
      for (final file in Directory(dir).listSync(recursive: true).whereType<File>()) {
        if (!file.path.endsWith('.dart') || file.path.endsWith('.g.dart')) continue;
        final lines = file.readAsLinesSync();
        for (var i = 0; i < lines.length; i++) {
          final line = lines[i].trimLeft();
          if (line.startsWith('//')) continue;
          if (forbidden.hasMatch(line)) offenders.add('${file.path}:${i + 1}: $line');
        }
      }
    }
    expect(offenders, isEmpty, reason: offenders.join('\n'));
  });
}
