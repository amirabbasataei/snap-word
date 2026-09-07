import 'package:flutter/material.dart';

/// Vazirmatn `TextTheme` — the 8 roles from the design token sheet
/// (`Zanjir.dc.html`, section 4b). Letter-spacing is 0 everywhere except
/// the wordmark (−0.5px, applied where the wordmark is built, not here).
/// Colour is applied by the caller via `context.z` — these styles carry
/// only size/weight/height/font so the same TextTheme works in both modes.
abstract final class ZTypography {
  static const _family = 'Vazirmatn';

  /// Score, seed letter.
  static const display = TextStyle(
    fontFamily: _family,
    fontSize: 48,
    fontWeight: FontWeight.w900,
    height: 1.0,
  );

  static const screenTitle = TextStyle(
    fontFamily: _family,
    fontSize: 20,
    fontWeight: FontWeight.w900,
    height: 1.25,
  );

  static const chainWordActive = TextStyle(
    fontFamily: _family,
    fontSize: 21,
    fontWeight: FontWeight.w900,
    height: 1.0,
  );

  static const chainWordHistory = TextStyle(
    fontFamily: _family,
    fontSize: 17,
    fontWeight: FontWeight.w800,
    height: 1.0,
  );

  static const cardTitle = TextStyle(
    fontFamily: _family,
    fontSize: 14,
    fontWeight: FontWeight.w800,
    height: 1.3,
  );

  static const body = TextStyle(
    fontFamily: _family,
    fontSize: 12.5,
    fontWeight: FontWeight.w500,
    height: 1.6,
  );

  static const metaLabel = TextStyle(
    fontFamily: _family,
    fontSize: 11.5,
    fontWeight: FontWeight.w600,
    height: 1.4,
  );

  static const button = TextStyle(
    fontFamily: _family,
    fontSize: 16,
    fontWeight: FontWeight.w900,
    height: 1.0,
  );

  /// The 5-tile wordmark is the one place with non-zero letter-spacing.
  static const wordmarkLetterSpacing = -0.5;

  /// Builds a Material [TextTheme] on top of [baseColor] /
  /// [secondaryColor] so `Theme.of(context).textTheme` stays usable for
  /// any widget that hasn't been ported to explicit `Z*` roles yet.
  static TextTheme textTheme({
    required Color baseColor,
    required Color secondaryColor,
  }) {
    return TextTheme(
      displayLarge: display.copyWith(color: baseColor),
      headlineLarge: screenTitle.copyWith(color: baseColor),
      headlineMedium: chainWordActive.copyWith(color: baseColor),
      titleLarge: cardTitle.copyWith(color: baseColor),
      titleMedium: chainWordHistory.copyWith(color: baseColor),
      bodyLarge: body.copyWith(color: baseColor),
      bodyMedium: body.copyWith(color: secondaryColor),
      bodySmall: metaLabel.copyWith(color: secondaryColor),
      labelLarge: button.copyWith(color: baseColor),
    );
  }
}
