import 'package:flutter/material.dart';

/// زنجیر design-token colours. Values pulled verbatim from the design canvas
/// token sheet (`Zanjir.dc.html`, section 4a) — light and dark are the same
/// token identities with two value sets, never independently re-authored.
///
/// A screen never names a hex value; it reads `context.z.indigo` etc.
@immutable
class ZColors extends ThemeExtension<ZColors> {
  final Color paper;
  final Color surface;
  final Color line;
  final Color wash;
  final Color ink;
  final Color ink60;
  final Color ink40;

  final Color indigo;
  final Color indigoDeep;
  final Color teal;
  final Color tealDeep;
  final Color amber;
  final Color amberDeep;
  final Color coral;
  final Color coralDeep;

  final Color onIndigo;
  final Color onIndigoSoft;
  final Color onTeal;
  final Color onTealSoft;
  final Color onAmber;
  final Color onCoral;

  /// Player's own chain bubble & hero band — inverts between light/dark.
  final Color inkSurface;
  final Color inkSurfaceDeep;
  final Color onInkSurface;
  final Color onInkSurfaceSoft;

  final Color tintIndigo;
  final Color tintTeal;
  final Color tintCoral;

  const ZColors({
    required this.paper,
    required this.surface,
    required this.line,
    required this.wash,
    required this.ink,
    required this.ink60,
    required this.ink40,
    required this.indigo,
    required this.indigoDeep,
    required this.teal,
    required this.tealDeep,
    required this.amber,
    required this.amberDeep,
    required this.coral,
    required this.coralDeep,
    required this.onIndigo,
    required this.onIndigoSoft,
    required this.onTeal,
    required this.onTealSoft,
    required this.onAmber,
    required this.onCoral,
    required this.inkSurface,
    required this.inkSurfaceDeep,
    required this.onInkSurface,
    required this.onInkSurfaceSoft,
    required this.tintIndigo,
    required this.tintTeal,
    required this.tintCoral,
  });

  static const light = ZColors(
    paper: Color(0xFFF6F1E7),
    surface: Color(0xFFFFFFFF),
    line: Color(0xFFE3DCCC),
    wash: Color(0xFFF0EBE0),
    ink: Color(0xFF1E1B2E),
    ink60: Color(0xFF6B6780),
    ink40: Color(0xFF8B8798),
    indigo: Color(0xFF4C5FE0),
    indigoDeep: Color(0xFF3546B8),
    teal: Color(0xFF16A38F),
    tealDeep: Color(0xFF0E8071),
    amber: Color(0xFFF5A524),
    amberDeep: Color(0xFFC97F0C),
    coral: Color(0xFFEF4B3C),
    coralDeep: Color(0xFFC22E22),
    onIndigo: Color(0xFFFFFFFF),
    onIndigoSoft: Color(0xFFC9D0FA),
    onTeal: Color(0xFFFFFFFF),
    onTealSoft: Color(0xFFBFEDE5),
    onAmber: Color(0xFF3A2606),
    onCoral: Color(0xFFFFFFFF),
    inkSurface: Color(0xFF1E1B2E),
    inkSurfaceDeep: Color(0xFF0C0A16),
    onInkSurface: Color(0xFFFFFFFF),
    onInkSurfaceSoft: Color(0xFF9F9BB0),
    tintIndigo: Color(0xFFE7EAFD),
    tintTeal: Color(0xFFE1F4F0),
    tintCoral: Color(0xFFFDEAE7),
  );

  static const dark = ZColors(
    paper: Color(0xFF211D26),
    surface: Color(0xFF2B2632),
    line: Color(0xFF3B3543),
    wash: Color(0xFF38313F),
    ink: Color(0xFFF2EDE3),
    ink60: Color(0xFFB9B2C2),
    ink40: Color(0xFF8E8799),
    indigo: Color(0xFF7180EE),
    indigoDeep: Color(0xFF414FB6),
    teal: Color(0xFF2CBBA4),
    tealDeep: Color(0xFF178A79),
    amber: Color(0xFFF7B44A),
    amberDeep: Color(0xFFC1832A),
    coral: Color(0xFFF4685A),
    coralDeep: Color(0xFFBE4034),
    onIndigo: Color(0xFF14122B),
    onIndigoSoft: Color(0xFF221F4A),
    onTeal: Color(0xFF0C2A25),
    onTealSoft: Color(0xFF0F3B33),
    onAmber: Color(0xFF2A1A04),
    onCoral: Color(0xFF2C0E09),
    inkSurface: Color(0xFFF2EDE3),
    inkSurfaceDeep: Color(0xFFC8C0B2),
    onInkSurface: Color(0xFF211D26),
    onInkSurfaceSoft: Color(0xFF6A6273),
    tintIndigo: Color(0xFF2A2E52),
    tintTeal: Color(0xFF123A34),
    tintCoral: Color(0xFF452724),
  );

  @override
  ZColors copyWith({
    Color? paper,
    Color? surface,
    Color? line,
    Color? wash,
    Color? ink,
    Color? ink60,
    Color? ink40,
    Color? indigo,
    Color? indigoDeep,
    Color? teal,
    Color? tealDeep,
    Color? amber,
    Color? amberDeep,
    Color? coral,
    Color? coralDeep,
    Color? onIndigo,
    Color? onIndigoSoft,
    Color? onTeal,
    Color? onTealSoft,
    Color? onAmber,
    Color? onCoral,
    Color? inkSurface,
    Color? inkSurfaceDeep,
    Color? onInkSurface,
    Color? onInkSurfaceSoft,
    Color? tintIndigo,
    Color? tintTeal,
    Color? tintCoral,
  }) {
    return ZColors(
      paper: paper ?? this.paper,
      surface: surface ?? this.surface,
      line: line ?? this.line,
      wash: wash ?? this.wash,
      ink: ink ?? this.ink,
      ink60: ink60 ?? this.ink60,
      ink40: ink40 ?? this.ink40,
      indigo: indigo ?? this.indigo,
      indigoDeep: indigoDeep ?? this.indigoDeep,
      teal: teal ?? this.teal,
      tealDeep: tealDeep ?? this.tealDeep,
      amber: amber ?? this.amber,
      amberDeep: amberDeep ?? this.amberDeep,
      coral: coral ?? this.coral,
      coralDeep: coralDeep ?? this.coralDeep,
      onIndigo: onIndigo ?? this.onIndigo,
      onIndigoSoft: onIndigoSoft ?? this.onIndigoSoft,
      onTeal: onTeal ?? this.onTeal,
      onTealSoft: onTealSoft ?? this.onTealSoft,
      onAmber: onAmber ?? this.onAmber,
      onCoral: onCoral ?? this.onCoral,
      inkSurface: inkSurface ?? this.inkSurface,
      inkSurfaceDeep: inkSurfaceDeep ?? this.inkSurfaceDeep,
      onInkSurface: onInkSurface ?? this.onInkSurface,
      onInkSurfaceSoft: onInkSurfaceSoft ?? this.onInkSurfaceSoft,
      tintIndigo: tintIndigo ?? this.tintIndigo,
      tintTeal: tintTeal ?? this.tintTeal,
      tintCoral: tintCoral ?? this.tintCoral,
    );
  }

  @override
  ZColors lerp(ThemeExtension<ZColors>? other, double t) {
    if (other is! ZColors) return this;
    Color c(Color a, Color b) => Color.lerp(a, b, t)!;
    return ZColors(
      paper: c(paper, other.paper),
      surface: c(surface, other.surface),
      line: c(line, other.line),
      wash: c(wash, other.wash),
      ink: c(ink, other.ink),
      ink60: c(ink60, other.ink60),
      ink40: c(ink40, other.ink40),
      indigo: c(indigo, other.indigo),
      indigoDeep: c(indigoDeep, other.indigoDeep),
      teal: c(teal, other.teal),
      tealDeep: c(tealDeep, other.tealDeep),
      amber: c(amber, other.amber),
      amberDeep: c(amberDeep, other.amberDeep),
      coral: c(coral, other.coral),
      coralDeep: c(coralDeep, other.coralDeep),
      onIndigo: c(onIndigo, other.onIndigo),
      onIndigoSoft: c(onIndigoSoft, other.onIndigoSoft),
      onTeal: c(onTeal, other.onTeal),
      onTealSoft: c(onTealSoft, other.onTealSoft),
      onAmber: c(onAmber, other.onAmber),
      onCoral: c(onCoral, other.onCoral),
      inkSurface: c(inkSurface, other.inkSurface),
      inkSurfaceDeep: c(inkSurfaceDeep, other.inkSurfaceDeep),
      onInkSurface: c(onInkSurface, other.onInkSurface),
      onInkSurfaceSoft: c(onInkSurfaceSoft, other.onInkSurfaceSoft),
      tintIndigo: c(tintIndigo, other.tintIndigo),
      tintTeal: c(tintTeal, other.tintTeal),
      tintCoral: c(tintCoral, other.tintCoral),
    );
  }
}

extension ZColorsContext on BuildContext {
  /// Token access point: `context.z.indigo`, `context.z.onIndigo`, ...
  ZColors get z => Theme.of(this).extension<ZColors>()!;
}
