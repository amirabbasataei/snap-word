/// Spacing, radius, tile-size and hit-target constants from the design
/// token sheet (`Zanjir.dc.html`, section 4b). Never hardcode these numbers
/// in a screen — read them from here so the whole app moves together.
abstract final class ZSpacing {
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 14.0;
  static const xl = 18.0;
  static const xxl = 22.0;
  static const xxxl = 26.0;

  /// Standard screen edge padding.
  static const screenGutter = 18.0;
}

abstract final class ZRadius {
  static const tileMin = 8.0;
  static const tileMax = 12.0;
  static const chip = 999.0;
  static const cardMin = 16.0;
  static const cardMax = 20.0;
  static const sheetMin = 24.0;
  static const sheetMax = 28.0;
}

/// Letter-tile side lengths for each context they appear in.
abstract final class ZTileSize {
  /// Inline within a running word chain.
  static const inline = 26.0;
  /// A single-letter prompt (e.g. required starting letter).
  static const prompt = 34.0;
  /// Hero contexts (game-over tumble, wordmark).
  static const heroMin = 42.0;
  static const heroMax = 56.0;
  /// Daily Challenge seed-letter hero.
  static const dailySeed = 96.0;
}

abstract final class ZHitTarget {
  static const min = 44.0;
  static const buttonMin = 48.0;
  static const buttonMax = 58.0;
}
