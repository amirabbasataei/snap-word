import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:wordchain/core/theme/app_game_metrics.dart';
import 'package:wordchain/core/theme/app_scene_tokens.dart';
import 'package:wordchain/core/theme/app_tokens.dart';
import 'package:wordchain/core/widgets/chunky.dart';

/// Round chunky player marker of the "A · mascot-led" game screens: a coloured
/// disc with either the player's initial or the robot (the AI opponent).
/// Canvas `ZPlayA`: 3px outline, no depth edge; the header disc (36) carries
/// the top highlight, the in-chain one (34) is flat.
class ZDiscAvatar extends StatelessWidget {
  final Color fill;

  /// Initial shown on the disc; null → the robot glyph.
  final String? letter;
  final Color? onFill;
  final double size;
  final bool highlight;

  const ZDiscAvatar({
    super.key,
    required this.fill,
    this.letter,
    this.onFill,
    this.size = ZGame.gameDisc,
    this.highlight = true,
  });

  /// The signed-in / guest player: indigo with the initial.
  factory ZDiscAvatar.me(
    BuildContext context, {
    required String letter,
    double size = ZGame.gameDisc,
    bool highlight = true,
  }) => ZDiscAvatar(
    fill: context.z.indigo,
    onFill: context.z.onIndigo,
    letter: letter,
    size: size,
    highlight: highlight,
  );

  /// The AI opponent: amber with the robot face.
  factory ZDiscAvatar.robot(
    BuildContext context, {
    double size = ZGame.gameDisc,
    bool highlight = true,
  }) => ZDiscAvatar(fill: context.z.amber, size: size, highlight: highlight);

  @override
  Widget build(BuildContext context) {
    final o = svgHex(context.zs.outline);
    final s = svgHex(context.z.surface);
    final letter = this.letter;
    return ChunkyBox(
      fill: fill,
      depth: 0,
      circle: true,
      highlight: highlight,
      width: size,
      height: size,
      alignment: Alignment.center,
      child:
          letter != null
              ? Text(
                letter,
                style: TextStyle(
                  color: onFill,
                  fontWeight: FontWeight.w900,
                  fontSize: size * .42,
                  height: 1,
                ),
              )
              : SvgPicture.string(
                '<svg viewBox="0 0 42 40"><rect x="6" y="8" width="30" height="26" rx="8" fill="$s" stroke="$o" stroke-width="3.5"/><circle cx="15" cy="20" r="3.5" fill="$o"/><circle cx="27" cy="20" r="3.5" fill="$o"/>${size >= ZGame.gameDisc ? '<path d="M16 28h10" stroke="$o" stroke-width="3.5" stroke-linecap="round"/>' : ''}</svg>',
                width: size * .6,
                height: size * .55,
              ),
    );
  }
}
