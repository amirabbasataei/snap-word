import 'package:flutter/material.dart';
import 'package:wordchain/core/theme/app_tokens.dart';
import 'package:wordchain/core/theme/app_typography.dart';
import 'package:wordchain/features/game/view/widgets/z_game_hud.dart';

/// Top of the screen (canvas `ZNotifs`): the 44dp back button and the
/// «اعلان‌ها» title. The canvas's «همه خوانده شد» pill is not drawn — nothing
/// here has a read state.
class MessagesHeader extends StatelessWidget {
  final VoidCallback onBack;

  const MessagesHeader({super.key, required this.onBack});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
      child: Row(
        children: [
          ZGameBackButton(onTap: onBack),
          const SizedBox(width: 10),
          Expanded(
            child: Semantics(
              header: true,
              child: MediaQuery.withClampedTextScaling(
                maxScaleFactor: 1.3,
                child: Text(
                  'اعلان‌ها',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: ZTypography.screenTitle.copyWith(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    height: 1.2,
                    color: context.z.ink,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
