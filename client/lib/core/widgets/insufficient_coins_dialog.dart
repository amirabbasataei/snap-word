import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:wordchain/core/widgets/z_coin.dart';
import 'package:wordchain/core/di/injection.dart';
import 'package:wordchain/core/services/ad_service.dart';
import 'package:wordchain/core/theme/app_spacing.dart';
import 'package:wordchain/core/theme/app_tokens.dart';
import 'package:wordchain/core/theme/app_typography.dart';
import 'package:wordchain/core/utils/persian_digits.dart';
import 'package:wordchain/core/widgets/z_buttons.dart';
import 'package:wordchain/core/widgets/z_icon.dart';
import 'package:wordchain/features/auth/cubit/auth_cubit.dart';
import 'package:wordchain/features/game/data/game_constants.dart';

/// Shown wherever an action is blocked by a coin shortfall (entry fee, daily
/// retry, continue…). Explains the shortfall and lists the real ways to earn
/// coins, each linking to the screen where that happens.
///
/// [cost] is the price of the blocked action; defaults to the 1v1 entry fee.
Future<void> showInsufficientCoinsDialog(BuildContext context, {int? cost}) {
  final amount = cost ?? GameConstants.entryFeeCoins;
  return showDialog<void>(
    context: context,
    builder:
        (dialogContext) => _InsufficientCoinsDialog(
          cost: amount,
          onNavigate: (route, {bool tab = false}) {
            Navigator.of(dialogContext).pop();
            tab ? context.go(route) : context.push(route);
          },
        ),
  );
}

class _InsufficientCoinsDialog extends StatelessWidget {
  final int cost;
  final void Function(String route, {bool tab}) onNavigate;

  const _InsufficientCoinsDialog({
    required this.cost,
    required this.onNavigate,
  });

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    final isGuest = getIt<AuthCubit>().isGuest;
    final adsEnabled = getIt<AdService>().rewardedEnabled && !isGuest;
    final dailyMax =
        GameConstants.dailyCompletePrize + GameConstants.dailyRankPrizes.first;

    return Dialog(
      backgroundColor: z.surface,
      insetPadding: const EdgeInsets.symmetric(
        horizontal: ZSpacing.screenGutter,
        vertical: ZSpacing.xl,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(ZRadius.cardMax),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(ZSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: z.amber.withValues(alpha: 0.2),
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: const ZCoin(size: 44),
              ),
            ),
            const SizedBox(height: ZSpacing.lg),
            Text(
              'سکهٔ کافی نداری',
              textAlign: TextAlign.center,
              style: ZTypography.screenTitle.copyWith(
                color: z.ink,
                fontSize: 18,
              ),
            ),
            const SizedBox(height: ZSpacing.sm),
            Text(
              'برای این کار ${toPersianDigits(cost)} سکه لازم است. با این راه‌ها سکه جمع کن:',
              textAlign: TextAlign.center,
              style: ZTypography.body.copyWith(color: z.ink60),
            ),
            const SizedBox(height: ZSpacing.lg),
            if (adsEnabled)
              _EarnRow(
                icon: 'gift',
                title: 'تماشای تبلیغ',
                reward: '+${toPersianDigits(GameConstants.rewardedAdCoins)}',
                onTap: () => onNavigate('/rewards'),
              ),
            _EarnRow(
              icon: 'target',
              title: 'چالش روزانه',
              reward: 'تا ${toPersianDigits(dailyMax)}',
              onTap: () => onNavigate('/daily'),
            ),
            _EarnRow(
              icon: 'users',
              title: 'دعوت دوستان',
              reward: '+${toPersianDigits(50)} هر نفر',
              onTap: () => onNavigate('/profile', tab: true),
            ),
            _EarnRow(
              icon: 'timer-reset',
              title: 'جایزهٔ ورود روزانه و روزهای پیاپی',
              reward: '+${toPersianDigits(10)}',
              onTap: () => onNavigate('/rewards'),
            ),
            _EarnRow(
              icon: 'trophy',
              title: 'برنده شدن در بازی آنلاین',
              reward: 'جایزهٔ ${toPersianDigits(GameConstants.entryFeePot)}',
            ),
            const SizedBox(height: ZSpacing.lg),
            NeutralButton(
              label: 'متوجه شدم',
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        ),
      ),
    );
  }
}

class _EarnRow extends StatelessWidget {
  final String icon;
  final String title;
  final String reward;
  final VoidCallback? onTap;

  const _EarnRow({
    required this.icon,
    required this.title,
    required this.reward,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    return Padding(
      padding: const EdgeInsets.only(bottom: ZSpacing.sm),
      child: Material(
        color: z.tintIndigo,
        borderRadius: BorderRadius.circular(ZRadius.tileMin + 2),
        child: InkWell(
          borderRadius: BorderRadius.circular(ZRadius.tileMin + 2),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: ZSpacing.md,
              vertical: ZSpacing.md,
            ),
            child: Row(
              children: [
                ZIcon(icon, size: 20, color: z.indigo),
                const SizedBox(width: ZSpacing.md),
                Expanded(
                  child: Text(
                    title,
                    style: ZTypography.cardTitle.copyWith(
                      color: z.ink,
                      fontSize: 13.5,
                    ),
                  ),
                ),
                const SizedBox(width: ZSpacing.sm),
                Text(
                  reward,
                  style: ZTypography.metaLabel.copyWith(
                    color: z.teal,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (onTap != null) ...[
                  const SizedBox(width: ZSpacing.xs),
                  Icon(Icons.chevron_right_rounded, size: 18, color: z.ink60),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
