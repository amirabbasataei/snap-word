import 'package:flutter/material.dart';
import 'package:wordchain/core/theme/app_elevation.dart';
import 'package:wordchain/core/theme/app_spacing.dart';
import 'package:wordchain/core/theme/app_tokens.dart';
import 'package:wordchain/core/theme/app_typography.dart';

/// One of the four co-equal accents the design rotates through for tiles,
/// or [neutral] for a history/inactive tile on `surface`.
enum ZAccent { indigo, teal, amber, coral, neutral }

/// The atom of the whole زنجیر system — a single-letter square tile with a
/// solid offset edge (no blur), used inline in a word chain, as a prompt
/// tile, or scaled up as a hero (wordmark, game-over tumble, daily seed).
class LetterTile extends StatelessWidget {
  final String letter;
  final double size;
  final ZAccent accent;

  /// Rotation in radians — used for the wordmark's scattered-letter look.
  final double rotation;

  const LetterTile({
    super.key,
    required this.letter,
    this.size = ZTileSize.inline,
    this.accent = ZAccent.indigo,
    this.rotation = 0,
  });

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    final (bg, onColor, deep) = _colorsFor(z, accent);
    final t = ((size - ZTileSize.inline) /
            (ZTileSize.heroMax - ZTileSize.inline))
        .clamp(0.0, 1.0);
    final radius = ZRadius.tileMin + (ZRadius.tileMax - ZRadius.tileMin) * t;

    Widget tile = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(radius),
        boxShadow: ZElevation.solidEdge(deep, depth: ZElevation.tileDepth),
      ),
      child: Text(
        letter,
        style: ZTypography.chainWordActive.copyWith(
          color: onColor,
          fontSize: size * 0.55,
        ),
      ),
    );

    if (rotation != 0) {
      tile = Transform.rotate(angle: rotation, child: tile);
    }
    return tile;
  }

  static (Color, Color, Color) _colorsFor(ZColors z, ZAccent accent) {
    switch (accent) {
      case ZAccent.indigo:
        return (z.indigo, z.onIndigo, z.indigoDeep);
      case ZAccent.teal:
        return (z.teal, z.onTeal, z.tealDeep);
      case ZAccent.amber:
        return (z.amber, z.onAmber, z.amberDeep);
      case ZAccent.coral:
        return (z.coral, z.onCoral, z.coralDeep);
      case ZAccent.neutral:
        return (z.surface, z.ink, z.line);
    }
  }
}
