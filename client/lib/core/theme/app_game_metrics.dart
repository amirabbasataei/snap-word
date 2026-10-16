/// Sizes and motion timings for the "game-feel" chunky components introduced
/// by the ZHome v2 redesign (canvas turn 6; sizes from the 5c/6e token tables).
/// Kept apart from [ZSpacing] / [ZMotion] so the original sheet is untouched.
abstract final class ZGame {
  // Strokes.
  static const outline = 3.0;
  static const outlineInner = 2.5;

  // Solid depth edges (blur 0): HUD · tiles · mode buttons · Play.
  static const depthSm = 3.0;
  static const depthMd = 5.0;
  static const depthLg = 6.0;
  static const depthXl = 8.0;

  /// A pressed chunky button keeps this much edge and sinks by the rest.
  static const pressedDepth = 2.0;

  // HUD.
  static const hudPill = 36.0;
  static const hudLevel = 48.0;
  static const hudRowHeight = 48.0;

  /// Settings button — 44 (the canvas draws 40; bumped to the hit-target min).
  static const hudIconButton = 44.0;

  // Primary / secondary buttons.
  static const playHeight = 76.0;
  static const playRadius = 26.0;
  static const onlineHeight = 58.0;
  static const onlineRadius = 22.0;

  // Logo lockup.
  static const logoSize = 60.0;
  static const logoStroke = 7.0;
  static const logoShadow = 6.0;

  // Hero scene design canvas (everything inside is laid out at this size and
  // scaled to fit the screen).
  static const heroWidth = 396.0;
  static const heroHeight = 352.0;

  // Home nav: raised active tile.
  static const navTileWidth = 60.0;
  static const navTileHeight = 48.0;
  static const navLift = 30.0;

  /// Smallest label size on the home screen (the canvas has 10px labels).
  static const minLabel = 11.5;
}

/// Looping / one-shot motion periods for the home scene (canvas 5c/6e).
abstract final class ZGameMotion {
  static const press = Duration(milliseconds: 90);

  static const sway = 2400; // chain group ±1.2°
  static const wobble = 1200; // each tile ±2°, +300ms per tile
  static const hang = 1400; // mascot swing ±7°
  static const wave = 380; // mascot arm
  static const kick = 350; // mascot legs
  static const drop = 900; // next-word tile bob
  static const float = 5000; // background letters
  static const twinkle = 900; // each half of the 1.8s sparkle cycle
  static const pulse = 2200; // Play button idle pulse
  static const pulseDelay = 1000;
  static const wiggle = 3500; // chest
  static const wiggleDelay = 1400;
  static const blink = 4200;
  static const spin = 14000; // chest rays
  static const glow = 1600;
}
