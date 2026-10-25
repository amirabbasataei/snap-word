import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:wordchain/core/widgets/chunky.dart';

/// Glyphs of the daily screens, drawn in token colours (the Material icon
/// font is not available everywhere, and the canvas draws these itself).
abstract final class DailyIcons {
  static Widget flame({
    required Color body,
    required Color core,
    required Color outline,
    double width = 26,
    double height = 30,
  }) => SvgPicture.string(
    '<svg viewBox="0 0 20 24"><path d="M10 1C11 6 18 8 18 15a8 8 0 0 1-16 0c0-4 2-6 4-8 0 3 1 4 2 5 0-4 1-8 2-11z" fill="${svgHex(body)}" stroke="${svgHex(outline)}" stroke-width="2.2" stroke-linejoin="round"/><path d="M10 13c1 2 3 3 3 5a3 3 0 0 1-6 0c0-2 2-3 3-5z" fill="${svgHex(core)}"/></svg>',
    width: width,
    height: height,
  );

  static Widget heart({
    required Color fill,
    required Color outline,
  }) => SvgPicture.string(
    '<svg viewBox="0 0 24 22"><path d="M12 20S2 14 2 7.5A5 5 0 0 1 12 5a5 5 0 0 1 10 2.5C22 14 12 20 12 20z" fill="${svgHex(fill)}" stroke="${svgHex(outline)}" stroke-width="2.4" stroke-linejoin="round"/></svg>',
    width: 22,
    height: 20,
  );

  static Widget share(Color stroke) => SvgPicture.string(
    '<svg viewBox="0 0 24 24" fill="none" stroke="${svgHex(stroke)}" stroke-width="3" stroke-linecap="round"><circle cx="18" cy="5" r="2.5"/><circle cx="6" cy="12" r="2.5"/><circle cx="18" cy="19" r="2.5"/><path d="M8.2 10.8l7.6-4.4M8.2 13.2l7.6 4.4"/></svg>',
    width: 22,
    height: 22,
  );

  static Widget podium(Color stroke) => SvgPicture.string(
    '<svg viewBox="0 0 24 24" fill="none" stroke="${svgHex(stroke)}" stroke-width="2.8" stroke-linejoin="round"><path d="M9 21V9h6v12M3 21v-7h6M15 21v-9h6v9M2 21h20"/></svg>',
    width: 18,
    height: 18,
  );
}
