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

  // Bottom dock (canvas `ZNav`). Panel: 3px outline, r24, 5px depth edge.
  static const dockRadius = 24.0;
  static const dockMarginH = 12.0;
  static const dockMarginBottom = 14.0;
  static const dockPaddingTop = 8.0;
  static const dockPaddingH = 4.0;
  static const dockPaddingBottom = 8.0;
  static const dockDepth = 5.0;

  /// Each tab's box (the raised tile pokes out of the top of it).
  static const dockTabHeight = 58.0;
  static const dockGlyph = 32.0;
  static const dockGlyphSelected = 30.0;
  static const dockGlyphTop = 4.0;
  static const dockLabelHeight = 18.0;
  static const dockLabelSize = 14.0;
  static const dockTileWidth = 62.0;
  static const dockTileHeight = 50.0;
  static const dockTileRadius = 17.0;

  /// Tile top relative to the tab box (flex-end layout, `margin-top:-30`).
  static const dockTileTop = -15.0;
  static const dockBadge = 22.0;

  // ZSolo / game screens (canvas turn 7, `ZSoloA`).
  static const gameBackButton = 44.0;
  static const gameScorePillHeight = 50.0;
  static const gameTimerRing = 60.0;
  static const gameTimerCore = 42.0;
  static const gameChipHeight = 36.0;
  static const gameHeartWidth = 22.0;
  static const gameHeartHeight = 20.0;
  static const gameRowTile = 44.0;
  static const gameRowTileLast = 56.0;
  static const gameRowIndex = 30.0;
  static const gamePointsWidth = 44.0;
  static const gameLinkWidth = 14.0;
  static const gameLinkHeight = 28.0;
  static const gameInputHeight = 66.0;
  static const gameInputRadius = 22.0;
  static const gameSendWidth = 52.0;
  static const gameSendHeight = 50.0;
  static const gamePowerTile = 66.0;
  static const gamePowerDisc = 32.0;
  static const gamePowerBadge = 24.0;

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
