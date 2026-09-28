import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wordchain/core/theme/app_theme.dart';

bool _fontsLoaded = false;

/// Loads the vendored Vazirmatn weights so goldens render real Persian
/// glyphs instead of the test-default Ahem boxes.
Future<void> loadVazirmatn() async {
  if (_fontsLoaded) return;
  final loader = FontLoader('Vazirmatn');
  for (final weight in ['Regular', 'Medium', 'SemiBold', 'Bold', 'ExtraBold', 'Black']) {
    final bytes = File('assets/fonts/Vazirmatn-$weight.ttf').readAsBytesSync();
    loader.addFont(Future.value(ByteData.view(bytes.buffer)));
  }
  await loader.load();
  _fontsLoaded = true;
}

/// Wraps [child] the way `main.dart` does: زنجیر theme + RTL.
Widget zTestApp(Widget child, {Brightness brightness = Brightness.light}) {
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: brightness == Brightness.light ? AppTheme.light : AppTheme.dark,
    home: Directionality(textDirection: TextDirection.rtl, child: child),
  );
}
