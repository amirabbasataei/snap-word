import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:wordchain/core/theme/app_scene_tokens.dart';
import 'package:wordchain/core/theme/app_tokens.dart';
import 'package:wordchain/core/widgets/chunky.dart';

/// The home scene's inline glyphs, ported 1:1 from the canvas SVGs and
/// re-coloured from the theme tokens (they are filled/stroked in the object
/// palette, so they can't go through the monochrome `ZIcon`).
enum HomeGlyph { flame, gear, robot, chest, crown, play, clock }

class HomeSvg extends StatelessWidget {
  final HomeGlyph glyph;
  final double width;
  final double height;

  /// Stroke/fill colour for single-colour glyphs (gear, nav icons, clock).
  final Color? color;

  const HomeSvg(
    this.glyph, {
    super.key,
    required this.width,
    required this.height,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    final o = svgHex(context.zs.outline);
    final c = svgHex(color ?? z.ink);
    final svg = switch (glyph) {
      HomeGlyph.flame =>
        '<svg viewBox="0 0 20 24"><path d="M10 1C11 6 18 8 18 15a8 8 0 0 1-16 0c0-4 2-6 4-8 0 3 1 4 2 5 0-4 1-8 2-11z" fill="${svgHex(z.coral)}" stroke="$o" stroke-width="2.2" stroke-linejoin="round"/><path d="M10 13c1 2 3 3 3 5a3 3 0 0 1-6 0c0-2 2-3 3-5z" fill="${svgHex(z.amber)}"/></svg>',
      HomeGlyph.gear =>
        '<svg viewBox="0 0 24 24" fill="none" stroke="$c" stroke-width="2.8" stroke-linecap="round"><circle cx="12" cy="12" r="3.5"/><path d="M12 2.5v3M12 18.5v3M2.5 12h3M18.5 12h3M5.3 5.3l2.1 2.1M16.6 16.6l2.1 2.1M5.3 18.7l2.1-2.1M16.6 7.4l2.1-2.1"/></svg>',
      HomeGlyph.robot =>
        '<svg viewBox="0 0 42 40"><path d="M21 3v6" stroke="$o" stroke-width="3" stroke-linecap="round"/><circle cx="21" cy="4" r="3" fill="${svgHex(z.amber)}" stroke="$o" stroke-width="2.5"/><rect x="6" y="10" width="30" height="26" rx="8" fill="${svgHex(z.surface)}" stroke="$o" stroke-width="2.8"/><circle cx="15" cy="22" r="3.2" fill="$o"/><circle cx="27" cy="22" r="3.2" fill="$o"/><path d="M16 30h10" stroke="$o" stroke-width="2.8" stroke-linecap="round"/></svg>',
      HomeGlyph.chest =>
        '<svg viewBox="0 0 22 20"><rect x="2" y="7" width="18" height="11" rx="2.5" fill="${svgHex(z.surface)}" stroke="$o" stroke-width="2.4"/><rect x="1" y="2" width="20" height="7" rx="3" fill="${svgHex(z.surface)}" stroke="$o" stroke-width="2.4"/><rect x="9" y="2" width="4" height="16" fill="${svgHex(z.amber)}" stroke="$o" stroke-width="2"/></svg>',
      HomeGlyph.crown =>
        '<svg viewBox="0 0 22 18"><path d="M2 15L1 4l5.5 4L11 1l4.5 7L21 4l-1 11z" fill="${svgHex(z.surface)}" stroke="$o" stroke-width="2.4" stroke-linejoin="round"/></svg>',
      HomeGlyph.play =>
        '<svg viewBox="0 0 20 22"><path d="M16 3L4 11l12 8z" fill="${svgHex(z.teal)}" stroke="$o" stroke-width="2.6" stroke-linejoin="round"/></svg>',
      HomeGlyph.clock =>
        '<svg viewBox="0 0 12 12" fill="none" stroke="$c" stroke-width="2"><circle cx="6" cy="6.5" r="4.5"/><path d="M6 4v2.6l1.6 1"/></svg>',
    };
    return SvgPicture.string(svg, width: width, height: height);
  }
}
