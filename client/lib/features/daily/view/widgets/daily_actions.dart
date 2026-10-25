import 'package:flutter/material.dart';
import 'package:wordchain/core/theme/app_tokens.dart';
import 'package:wordchain/core/utils/persian_digits.dart';
import 'package:wordchain/core/widgets/z_dialog.dart';
import 'package:wordchain/features/daily/view/widgets/daily_icons.dart';
import 'package:wordchain/features/game/data/game_constants.dart';

/// The pre-game buttons: the big pulsing «شروع چالش امروز» and «دیدن جدول
/// امروز» under it.
class DailyBeforeActions extends StatelessWidget {
  final VoidCallback onStart;
  final VoidCallback onBoard;

  const DailyBeforeActions({
    super.key,
    required this.onStart,
    required this.onBoard,
  });

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.3,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ZDialogButton.primary(
            label: 'شروع چالش امروز',
            onTap: onStart,
            height: 70,
            radius: 24,
            depth: 7,
            fontSize: 24,
          ),
          const SizedBox(height: 4),
          ZDialogButton.secondary(
            label: 'دیدن جدول امروز',
            onTap: onBoard,
            height: 44,
            radius: 14,
            depth: 3,
            icon: DailyIcons.podium(z.ink),
          ),
        ],
      ),
    );
  }
}

/// The result buttons: share, then today's board and a solo game, then — while
/// the paid second attempt is still unused — the retry (costs
/// [GameConstants.dailyRetryCostCoins]; the canvas draws no retry, but it is
/// real).
class DailyAfterActions extends StatelessWidget {
  final VoidCallback onShare;
  final VoidCallback onBoard;
  final VoidCallback onSolo;

  /// Null hides the retry button (already used).
  final VoidCallback? onRetry;
  final bool retrying;

  const DailyAfterActions({
    super.key,
    required this.onShare,
    required this.onBoard,
    required this.onSolo,
    required this.onRetry,
    required this.retrying,
  });

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    final scale = MediaQuery.textScalerOf(context).scale(1);
    final narrow = MediaQuery.sizeOf(context).width < 340 || scale > 1.15;
    final board = ZDialogButton.secondary(
      label: 'جدول امروز',
      onTap: onBoard,
      height: 50,
      radius: 18,
      depth: 5,
    );
    final solo = ZDialogButton.secondary(
      label: 'بازی تک‌نفره',
      onTap: onSolo,
      height: 50,
      radius: 18,
      depth: 5,
    );
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.3,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ZDialogButton.primary(
            label: 'هم‌رسانی نتیجه',
            onTap: onShare,
            height: 62,
            radius: 22,
            depth: 6,
            fontSize: 21,
            icon: DailyIcons.share(z.onTeal),
          ),
          const SizedBox(height: 6),
          if (narrow) ...[
            board,
            const SizedBox(height: 4),
            solo,
          ] else
            Row(
              children: [
                Expanded(child: board),
                const SizedBox(width: 10),
                Expanded(child: solo),
              ],
            ),
          if (onRetry != null) ...[
            const SizedBox(height: 4),
            ZDialogButton.secondary(
              label:
                  retrying
                      ? 'کمی صبر کن…'
                      : 'امتحان دوباره · ${toPersianDigits(GameConstants.dailyRetryCostCoins)} سکه',
              onTap: retrying ? null : onRetry,
              height: 50,
              radius: 18,
              depth: 5,
              labelColor: retrying ? z.ink60 : null,
            ),
          ],
        ],
      ),
    );
  }
}
