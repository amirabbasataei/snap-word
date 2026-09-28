import 'package:flutter/material.dart';
import 'package:wordchain/core/theme/app_tokens.dart';
import 'package:wordchain/core/theme/app_typography.dart';

/// زنجیر light/dark themes. Both are built from the same `ZColors` token
/// set, so light and dark are the same widgets with different values —
/// screens read `context.z.*`, never `Theme.of(context)` colours directly.
abstract final class AppTheme {
  static ThemeData get light => _build(ZColors.light, Brightness.light);
  static ThemeData get dark => _build(ZColors.dark, Brightness.dark);

  static ThemeData _build(ZColors z, Brightness brightness) => ThemeData(
        useMaterial3: true,
        brightness: brightness,
        fontFamily: 'Vazirmatn',
        extensions: [z],
        scaffoldBackgroundColor: z.paper,
        colorScheme: ColorScheme(
          brightness: brightness,
          primary: z.indigo,
          onPrimary: z.onIndigo,
          secondary: z.teal,
          onSecondary: z.onTeal,
          surface: z.surface,
          onSurface: z.ink,
          error: z.coral,
          onError: z.onCoral,
        ),
        textTheme: ZTypography.textTheme(
          baseColor: z.ink,
          secondaryColor: z.ink60,
        ),
        dialogTheme: DialogThemeData(backgroundColor: z.surface),
        snackBarTheme: SnackBarThemeData(
          backgroundColor: z.inkSurface,
          contentTextStyle: ZTypography.body.copyWith(color: z.onInkSurface),
          behavior: SnackBarBehavior.floating,
        ),
        progressIndicatorTheme: ProgressIndicatorThemeData(color: z.indigo),
        dividerTheme: DividerThemeData(
          color: z.line,
          thickness: 1,
          space: 1,
        ),
        iconTheme: IconThemeData(color: z.ink60),
      );
}
