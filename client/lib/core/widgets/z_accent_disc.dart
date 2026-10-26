import 'package:flutter/material.dart';
import 'package:wordchain/core/theme/app_tokens.dart';
import 'package:wordchain/core/theme/app_typography.dart';
import 'package:wordchain/core/widgets/chunky.dart';
import 'package:wordchain/core/widgets/z_dialog.dart';

/// The 52dp accent square at the start of a prize or message card (canvas
/// `ZAwards` / `ZNotifs`): a number or a letter on the accent colour. A [dim]
/// one loses its colour (wash fill, no edge) — a claimed prize.
///
/// Decorative: the card carries the words, so it is hidden from screen readers
/// and ignores text scale.
class ZAccentDisc extends StatelessWidget {
  final String glyph;
  final ZDialogAccent accent;
  final bool dim;

  const ZAccentDisc({
    super.key,
    required this.glyph,
    required this.accent,
    this.dim = false,
  });

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    final (fill, deep, on) = switch (accent) {
      ZDialogAccent.teal => (z.teal, z.tealDeep, z.onTeal),
      ZDialogAccent.indigo => (z.indigo, z.indigoDeep, z.onIndigo),
      ZDialogAccent.amber => (z.amber, z.amberDeep, z.onAmber),
      ZDialogAccent.coral => (z.coral, z.coralDeep, z.onCoral),
    };
    return ExcludeSemantics(
      child: MediaQuery.withNoTextScaling(
        child: ChunkyBox(
          fill: dim ? z.wash : fill,
          deep: dim ? null : deep,
          depth: dim ? 0 : 4,
          radius: 16,
          highlight: !dim,
          width: 52,
          height: 52,
          alignment: Alignment.center,
          child: Text(
            glyph,
            maxLines: 1,
            style: ZTypography.button.copyWith(
              fontSize: glyph.runes.length > 1 ? 18 : 24,
              height: 1,
              color: dim ? z.ink60 : on,
            ),
          ),
        ),
      ),
    );
  }
}
