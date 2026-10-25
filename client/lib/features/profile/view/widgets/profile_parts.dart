import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:wordchain/core/theme/app_game_metrics.dart';
import 'package:wordchain/core/theme/app_tokens.dart';
import 'package:wordchain/core/theme/app_typography.dart';
import 'package:wordchain/core/widgets/chunky.dart';
import 'package:wordchain/core/widgets/chunky_pressable.dart';

/// Letters in a word: ZWNJ is a joiner, not a letter, and a rune is one
/// letter whatever its UTF-16 length.
int letterCount(String word) => word.runes.where((r) => r != 0x200C).length;

/// The surface card every profile section sits on (canvas: 3px outline, solid
/// edge, no blur).
class ProfileCard extends StatelessWidget {
  final EdgeInsetsGeometry padding;
  final Widget child;

  const ProfileCard({
    super.key,
    this.padding = const EdgeInsets.fromLTRB(14, 12, 14, 12),
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return ChunkyBox(
      fill: context.z.surface,
      depth: ZGame.depthMd,
      radius: 20,
      highlight: false,
      padding: padding,
      child: child,
    );
  }
}

/// A 44dp chunky button of the profile: [primary] is the amber action, the
/// default the neutral surface button. The label ignores text scale above 1.3×
/// (fixed height) and shrinks rather than wraps.
class ProfileChunkButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final bool primary;
  final Color? labelColor;
  final String? semanticLabel;

  const ProfileChunkButton({
    super.key,
    required this.label,
    required this.onTap,
    this.primary = false,
    this.labelColor,
    this.semanticLabel,
  });

  static const height = 44.0;

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.3,
      child: ChunkyPressable(
        depth: ZGame.depthSm,
        onTap: onTap,
        semanticLabel: semanticLabel ?? label,
        builder:
            (context, depth, _) => ChunkyBox(
              fill: primary ? z.amber : z.surface,
              deep: primary ? z.amberDeep : null,
              depth: depth,
              radius: 14,
              highlight: primary,
              height: height,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              alignment: Alignment.center,
              child: ExcludeSemantics(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    label,
                    maxLines: 1,
                    style: ZTypography.button.copyWith(
                      fontSize: 12.5,
                      color: labelColor ?? (primary ? z.onAmber : z.ink),
                    ),
                  ),
                ),
              ),
            ),
      ),
    );
  }
}

/// A 44dp square chunky button holding one drawn glyph (the header's rename
/// pencil, the invite card's share).
class ProfileGlyphButton extends StatelessWidget {
  final String semanticLabel;
  final VoidCallback onTap;
  final String Function(String ink) svg;
  final double glyph;
  final Color? fill;

  const ProfileGlyphButton({
    super.key,
    required this.semanticLabel,
    required this.onTap,
    required this.svg,
    this.glyph = 20,
    this.fill,
  });

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    return ChunkyPressable(
      depth: ZGame.depthSm,
      onTap: onTap,
      semanticLabel: semanticLabel,
      builder:
          (context, depth, _) => ChunkyBox(
            fill: fill ?? z.surface,
            depth: depth,
            radius: 14,
            highlight: false,
            width: 44,
            height: 44,
            alignment: Alignment.center,
            child: ExcludeSemantics(
              child: SvgPicture.string(
                svg(svgHex(z.ink)),
                width: glyph,
                height: glyph,
              ),
            ),
          ),
    );
  }
}

String pencilSvg(String ink) =>
    '<svg viewBox="0 0 24 24" fill="none" stroke="$ink" stroke-width="2.8" stroke-linecap="round" stroke-linejoin="round"><path d="M16 4l4 4-11 11H5v-4z"/></svg>';

String shareSvg(String ink) =>
    '<svg viewBox="0 0 24 24" fill="none" stroke="$ink" stroke-width="3" stroke-linecap="round"><circle cx="18" cy="5" r="2.5"/><circle cx="6" cy="12" r="2.5"/><circle cx="18" cy="19" r="2.5"/><path d="M8.2 10.8l7.6-4.4M8.2 13.2l7.6 4.4"/></svg>';

/// The premium crown, drawn (the Material glyph needs the icon font, which
/// the app bundles but golden tests do not load). [fill] / [stroke] are token
/// colours chosen by the caller.
class ProfileCrown extends StatelessWidget {
  final double size;
  final Color fill;
  final Color stroke;
  final String? semanticLabel;

  const ProfileCrown({
    super.key,
    required this.size,
    required this.fill,
    required this.stroke,
    this.semanticLabel,
  });

  @override
  Widget build(BuildContext context) {
    final icon = SvgPicture.string(
      '<svg viewBox="0 0 24 24" fill="${svgHex(fill)}" stroke="${svgHex(stroke)}" stroke-width="2" stroke-linejoin="round" stroke-linecap="round"><path d="M3 8l4.5 4L12 5l4.5 7L21 8l-2 11H5z"/></svg>',
      width: size,
      height: size,
    );
    final label = semanticLabel;
    return label == null
        ? ExcludeSemantics(child: icon)
        : Semantics(label: label, child: icon);
  }
}
