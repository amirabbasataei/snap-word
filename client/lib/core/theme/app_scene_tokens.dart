import 'package:flutter/material.dart';

/// Scene / game-object tokens added for the ZHome v2 redesign (canvas turn 6,
/// `Zanjir.dc.html` frames 6a light / 6b dark). They sit next to [ZColors]
/// rather than inside it so the original token sheet is untouched; both are
/// registered on the theme and read the same way:
/// `context.zs.sky1`, `context.zs.outline`, ...
@immutable
class ZScene extends ThemeExtension<ZScene> {
  /// Chunky stroke around every game object (HUD, tiles, buttons).
  final Color outline;

  /// Top-half highlight laid over flat fills (white 30% / 22%).
  final Color hi;

  final Color sky1;
  final Color sky2;
  final Color sky3;
  final Color blobIndigo;
  final Color blobTeal;
  final Color ring;

  /// Far / near floating letters.
  final Color particle;
  final Color particleNear;
  final Color vignette;

  /// Word-tile face and its solid depth edge.
  final Color tile;
  final Color tileDeep;

  /// Accent-coloured linking letters on word tiles (≥ 4.3:1 on [tile]).
  final Color indigoInk;
  final Color tealInk;
  final Color coralInk;

  /// Amber linking letters (ZSolo chain tiles, canvas turn 7 `--amberInk`).
  final Color amberInk;

  /// Neutral chain link (peg → first word).
  final Color chain;
  final Color glow;
  final Color rays;

  /// Unfilled progress-path connector.
  final Color track;

  /// Bottom dock (canvas turn 7, `ZNav`): panel fill, its solid depth edge,
  /// and the label colours on it. The dock is a dark plum slab in both themes.
  final Color dock;
  final Color dockDeep;

  /// White 10% sheen over the dock's top half.
  final Color dockSheen;
  final Color onDock;
  final Color onDock60;

  /// Text on a small coral chip (nav badge) — `--onCoralSm`.
  final Color onCoralSm;

  /// Flat (no blur) backdrop behind dialogs and sheets — `--scrim`.
  final Color scrim;

  const ZScene({
    required this.outline,
    required this.hi,
    required this.sky1,
    required this.sky2,
    required this.sky3,
    required this.blobIndigo,
    required this.blobTeal,
    required this.ring,
    required this.particle,
    required this.particleNear,
    required this.vignette,
    required this.tile,
    required this.tileDeep,
    required this.indigoInk,
    required this.tealInk,
    required this.coralInk,
    required this.amberInk,
    required this.chain,
    required this.glow,
    required this.rays,
    required this.track,
    required this.dock,
    required this.dockDeep,
    required this.dockSheen,
    required this.onDock,
    required this.onDock60,
    required this.onCoralSm,
    required this.scrim,
  });

  static const light = ZScene(
    outline: Color(0xFF1E1B2E),
    hi: Color(0x4DFFFFFF),
    sky1: Color(0xFFFFE2B6),
    sky2: Color(0xFFFCCDAE),
    sky3: Color(0xFFF6EADB),
    blobIndigo: Color(0x294C5FE0),
    blobTeal: Color(0x2916A38F),
    ring: Color(0x38FFFFFF),
    particle: Color(0x381E1B2E),
    particleNear: Color(0x38EF4B3C),
    vignette: Color(0x4DC26E3C),
    tile: Color(0xFFFFFDF8),
    tileDeep: Color(0xFFE3D2B6),
    indigoInk: Color(0xFF3546B8),
    tealInk: Color(0xFF0E8071),
    coralInk: Color(0xFFC22E22),
    amberInk: Color(0xFF9A5C06),
    chain: Color(0xFF6B6780),
    glow: Color(0xF2FFECAA),
    rays: Color(0x73F5A524),
    track: Color(0x2E1E1B2E),
    dock: Color(0xFF2F2846),
    dockDeep: Color(0xFF1F1A30),
    dockSheen: Color(0x1AFFFFFF),
    onDock: Color(0xFFFFFFFF),
    onDock60: Color(0xFFCFC6E0),
    onCoralSm: Color(0xFF3A0B06),
    scrim: Color(0x731E1B2E),
  );

  static const dark = ZScene(
    outline: Color(0xFF120F17),
    hi: Color(0x38FFFFFF),
    sky1: Color(0xFF3B2752),
    sky2: Color(0xFF2E2142),
    sky3: Color(0xFF221C2A),
    blobIndigo: Color(0x337180EE),
    blobTeal: Color(0x292CBBA4),
    ring: Color(0x0DFFD6AA),
    particle: Color(0x33F2EDE3),
    particleNear: Color(0x4DF4685A),
    vignette: Color(0x8C08060C),
    tile: Color(0xFF3A3342),
    tileDeep: Color(0xFF1E1A24),
    indigoInk: Color(0xFF98A3F5),
    tealInk: Color(0xFF4FD3BC),
    coralInk: Color(0xFFFF8A7E),
    amberInk: Color(0xFFF7B44A),
    chain: Color(0xFF8E8799),
    glow: Color(0x8CF7B44A),
    rays: Color(0x4DF7B44A),
    track: Color(0x33F2EDE3),
    dock: Color(0xFF3A2B4D),
    dockDeep: Color(0xFF241A31),
    dockSheen: Color(0x1AFFFFFF),
    onDock: Color(0xFFF2EDE3),
    onDock60: Color(0xFFC5B9D4),
    onCoralSm: Color(0xFF2C0E09),
    scrim: Color(0x9908060C),
  );

  @override
  ZScene copyWith({
    Color? outline,
    Color? hi,
    Color? sky1,
    Color? sky2,
    Color? sky3,
    Color? blobIndigo,
    Color? blobTeal,
    Color? ring,
    Color? particle,
    Color? particleNear,
    Color? vignette,
    Color? tile,
    Color? tileDeep,
    Color? indigoInk,
    Color? tealInk,
    Color? coralInk,
    Color? amberInk,
    Color? chain,
    Color? glow,
    Color? rays,
    Color? track,
    Color? dock,
    Color? dockDeep,
    Color? dockSheen,
    Color? onDock,
    Color? onDock60,
    Color? onCoralSm,
    Color? scrim,
  }) {
    return ZScene(
      outline: outline ?? this.outline,
      hi: hi ?? this.hi,
      sky1: sky1 ?? this.sky1,
      sky2: sky2 ?? this.sky2,
      sky3: sky3 ?? this.sky3,
      blobIndigo: blobIndigo ?? this.blobIndigo,
      blobTeal: blobTeal ?? this.blobTeal,
      ring: ring ?? this.ring,
      particle: particle ?? this.particle,
      particleNear: particleNear ?? this.particleNear,
      vignette: vignette ?? this.vignette,
      tile: tile ?? this.tile,
      tileDeep: tileDeep ?? this.tileDeep,
      indigoInk: indigoInk ?? this.indigoInk,
      tealInk: tealInk ?? this.tealInk,
      coralInk: coralInk ?? this.coralInk,
      amberInk: amberInk ?? this.amberInk,
      chain: chain ?? this.chain,
      glow: glow ?? this.glow,
      rays: rays ?? this.rays,
      track: track ?? this.track,
      dock: dock ?? this.dock,
      dockDeep: dockDeep ?? this.dockDeep,
      dockSheen: dockSheen ?? this.dockSheen,
      onDock: onDock ?? this.onDock,
      onDock60: onDock60 ?? this.onDock60,
      onCoralSm: onCoralSm ?? this.onCoralSm,
      scrim: scrim ?? this.scrim,
    );
  }

  @override
  ZScene lerp(ThemeExtension<ZScene>? other, double t) {
    if (other is! ZScene) return this;
    Color c(Color a, Color b) => Color.lerp(a, b, t)!;
    return ZScene(
      outline: c(outline, other.outline),
      hi: c(hi, other.hi),
      sky1: c(sky1, other.sky1),
      sky2: c(sky2, other.sky2),
      sky3: c(sky3, other.sky3),
      blobIndigo: c(blobIndigo, other.blobIndigo),
      blobTeal: c(blobTeal, other.blobTeal),
      ring: c(ring, other.ring),
      particle: c(particle, other.particle),
      particleNear: c(particleNear, other.particleNear),
      vignette: c(vignette, other.vignette),
      tile: c(tile, other.tile),
      tileDeep: c(tileDeep, other.tileDeep),
      indigoInk: c(indigoInk, other.indigoInk),
      tealInk: c(tealInk, other.tealInk),
      coralInk: c(coralInk, other.coralInk),
      amberInk: c(amberInk, other.amberInk),
      chain: c(chain, other.chain),
      glow: c(glow, other.glow),
      rays: c(rays, other.rays),
      track: c(track, other.track),
      dock: c(dock, other.dock),
      dockDeep: c(dockDeep, other.dockDeep),
      dockSheen: c(dockSheen, other.dockSheen),
      onDock: c(onDock, other.onDock),
      onDock60: c(onDock60, other.onDock60),
      onCoralSm: c(onCoralSm, other.onCoralSm),
      scrim: c(scrim, other.scrim),
    );
  }
}

extension ZSceneContext on BuildContext {
  /// Scene / game-object token access: `context.zs.outline`, ...
  ZScene get zs => Theme.of(this).extension<ZScene>()!;
}
