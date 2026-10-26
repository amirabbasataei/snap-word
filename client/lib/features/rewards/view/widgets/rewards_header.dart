import 'package:flutter/material.dart';
import 'package:wordchain/core/theme/app_tokens.dart';
import 'package:wordchain/core/theme/app_typography.dart';
import 'package:wordchain/core/widgets/motion.dart';
import 'package:wordchain/core/widgets/z_hud_coin_pill.dart';
import 'package:wordchain/features/game/view/widgets/z_game_hud.dart';

/// Top of the screen (canvas `ZAwards`): the 44dp back button, the «جایزه‌ها»
/// title and the live coin balance at the end. The balance pops when it grows
/// (a claim), as the canvas's pill does.
class RewardsHeader extends StatelessWidget {
  final int coins;
  final VoidCallback onBack;

  const RewardsHeader({super.key, required this.coins, required this.onBack});

  @override
  Widget build(BuildContext context) {
    final z = context.z;
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
                  'جایزه‌ها',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: ZTypography.screenTitle.copyWith(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    height: 1.2,
                    color: z.ink,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          MediaQuery.withClampedTextScaling(
            maxScaleFactor: 1.3,
            child: RewardsCoinBump(coins: coins),
          ),
        ],
      ),
    );
  }
}

/// [ZHudCoinPill] that scales 1 → 1.35 → 1 over 380 ms whenever [coins] goes
/// up. Rests under reduced motion.
class RewardsCoinBump extends StatefulWidget {
  final int coins;

  const RewardsCoinBump({super.key, required this.coins});

  @override
  State<RewardsCoinBump> createState() => _RewardsCoinBumpState();
}

class _RewardsCoinBumpState extends State<RewardsCoinBump>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 380),
  );

  @override
  void didUpdateWidget(RewardsCoinBump old) {
    super.didUpdateWidget(old);
    if (widget.coins > old.coins && !homeReducedMotion(context)) {
      _c.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scale = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(
          begin: 1.0,
          end: 1.35,
        ).chain(CurveTween(curve: Curves.easeOut)),
        weight: 40,
      ),
      TweenSequenceItem(
        tween: Tween(
          begin: 1.35,
          end: 1.0,
        ).chain(CurveTween(curve: Curves.easeOutBack)),
        weight: 60,
      ),
    ]).animate(_c);
    return ScaleTransition(
      scale: scale,
      child: ZHudCoinPill(coins: widget.coins),
    );
  }
}
