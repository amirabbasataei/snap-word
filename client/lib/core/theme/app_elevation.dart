import 'package:flutter/material.dart';

/// زنجیر has zero blur shadows anywhere — elevation is a solid offset edge
/// in the accent's "deep" token variant, per the token sheet (4b):
/// cards `0 3px 0 line`, tiles & primary buttons `0 4px 0 accent-deep`.
/// Pressed state removes the offset and translates Y +3 — see
/// `AccentButton`/`NeutralButton` in `core/widgets/`, which implement the
/// press animation directly rather than through a shadow.
abstract final class ZElevation {
  /// A solid, non-blurred bottom edge of [depth] under a card/tile resting
  /// on [edgeColor] (its own "deep" token, or `line` for neutral cards).
  static List<BoxShadow> solidEdge(Color edgeColor, {double depth = 3}) {
    return [
      BoxShadow(
        color: edgeColor,
        offset: Offset(0, depth),
        blurRadius: 0,
        spreadRadius: 0,
      ),
    ];
  }

  static const cardDepth = 3.0;
  static const tileDepth = 4.0;
  static const buttonDepth = 4.0;

  /// Y-translation applied to a pressed tile/button as its offset edge
  /// is removed.
  static const pressedTranslateY = 3.0;
}
