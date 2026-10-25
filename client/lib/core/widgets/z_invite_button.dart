import 'package:flutter/material.dart';
import 'package:wordchain/core/theme/app_game_metrics.dart';
import 'package:wordchain/core/theme/app_tokens.dart';
import 'package:wordchain/core/theme/app_typography.dart';
import 'package:wordchain/core/widgets/chunky.dart';
import 'package:wordchain/core/widgets/chunky_pressable.dart';

/// «دعوت به بازی» → «دعوت شد» (canvas `ZLobbyA` / `ZFriendsA` amber button),
/// shared by the lobby and the Friends tab. An invite can't be withdrawn (no
/// endpoint — todo.md 2.1), so the sent state is inert rather than a toggle.
/// 44dp tall; the label ignores text scale above 1.3×.
class ZInviteButton extends StatelessWidget {
  final String name;
  final bool invited;
  final bool busy;
  final VoidCallback onTap;

  const ZInviteButton({
    super.key,
    required this.name,
    required this.invited,
    required this.busy,
    required this.onTap,
  });

  static const _depth = 3.0;

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    final inert = invited || busy;
    final label = invited ? 'دعوت شد' : 'دعوت به بازی';
    final text = Text(
      label,
      maxLines: 1,
      style: ZTypography.button.copyWith(
        fontSize: 12.5,
        height: 1,
        color: inert ? z.ink60 : z.onAmber,
      ),
    );
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.3,
      child:
          inert
              ? Semantics(
                button: true,
                enabled: false,
                label: '$label؛ $name',
                excludeSemantics: true,
                child: Padding(
                  padding: const EdgeInsets.only(
                    bottom: _depth + ZGame.outline,
                  ),
                  child: Opacity(
                    opacity: busy ? .6 : 1,
                    child: ChunkyBox(
                      fill: z.wash,
                      depth: 0,
                      radius: 13,
                      highlight: false,
                      height: 44,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      alignment: Alignment.center,
                      child: text,
                    ),
                  ),
                ),
              )
              : ChunkyPressable(
                depth: _depth,
                onTap: onTap,
                semanticLabel: '$label؛ $name',
                builder:
                    (context, edge, _) => ChunkyBox(
                      fill: z.amber,
                      deep: z.amberDeep,
                      depth: edge,
                      radius: 13,
                      height: 44,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      alignment: Alignment.center,
                      child: text,
                    ),
              ),
    );
  }
}
