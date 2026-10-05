import 'package:wordchain/core/widgets/z_toast.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:wordchain/core/di/injection.dart';
import 'package:wordchain/core/services/ad_service.dart';
import 'package:wordchain/core/theme/app_spacing.dart';
import 'package:wordchain/features/auth/cubit/auth_cubit.dart';
import 'package:wordchain/features/game/data/game_constants.dart';
import 'package:wordchain/features/game/data/game_repository.dart';
import 'package:wordchain/core/theme/app_tokens.dart';
import 'package:wordchain/core/theme/app_typography.dart';
import 'package:wordchain/core/utils/persian_digits.dart';
import 'package:wordchain/core/widgets/solid_card.dart';
import 'package:wordchain/core/widgets/z_buttons.dart';
import 'package:wordchain/features/rewards/cubit/rewards_cubit.dart';
import 'package:wordchain/features/rewards/data/rewards_repository.dart';
import 'package:wordchain/core/utils/error_messages.dart';

/// Claimable prizes (referral, streak, rank, daily) behind the home gift icon.
class RewardsScreen extends StatefulWidget {
  const RewardsScreen({super.key});

  @override
  State<RewardsScreen> createState() => _RewardsScreenState();
}

class _RewardsScreenState extends State<RewardsScreen> {
  @override
  void initState() {
    super.initState();
    getIt<RewardsCubit>().refresh();
  }

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    return Scaffold(
      backgroundColor: z.paper,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                ZSpacing.screenGutter,
                ZSpacing.lg,
                ZSpacing.screenGutter,
                ZSpacing.md,
              ),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => context.pop(),
                    icon: Icon(Icons.arrow_back_rounded, color: z.ink),
                  ),
                  const SizedBox(width: ZSpacing.sm),
                  Text(
                    'هدیه‌ها',
                    style: ZTypography.screenTitle.copyWith(color: z.ink),
                  ),
                ],
              ),
            ),
            const _FreeCoinsCard(),
            Expanded(
              child: BlocBuilder<RewardsCubit, RewardsState>(
                bloc: getIt<RewardsCubit>(),
                builder: (context, state) {
                  if (state.items.isEmpty) {
                    return Center(
                      child:
                          state.loading
                              ? CircularProgressIndicator(color: z.indigo)
                              : Text(
                                'هدیه‌ای نداری',
                                style: ZTypography.body.copyWith(
                                  color: z.ink40,
                                ),
                              ),
                    );
                  }
                  return ListView.separated(
                    padding: const EdgeInsets.fromLTRB(
                      ZSpacing.screenGutter,
                      0,
                      ZSpacing.screenGutter,
                      ZSpacing.xl,
                    ),
                    itemCount: state.items.length,
                    separatorBuilder:
                        (_, _) => const SizedBox(height: ZSpacing.md),
                    itemBuilder: (_, i) => _RewardTile(item: state.items[i]),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Opt-in "watch an ad, get coins" row; authenticated players only because the
/// coins are credited server-side.
class _FreeCoinsCard extends StatefulWidget {
  const _FreeCoinsCard();

  @override
  State<_FreeCoinsCard> createState() => _FreeCoinsCardState();
}

class _FreeCoinsCardState extends State<_FreeCoinsCard> {
  bool _busy = false;

  Future<void> _watch() async {
    setState(() => _busy = true);
    final overlay = Overlay.of(context, rootOverlay: true);
    try {
      final watched = await getIt<AdService>().showRewardedAd();
      if (!watched) {
        ZToast.showOn(
          overlay,
          'تبلیغی در دسترس نیست؛ بعداً دوباره تلاش کن',
          kind: ZToastKind.error,
        );
        return;
      }
      final coins = await getIt<GameRepository>().claimRewardedAd();
      await getIt<AuthCubit>().setCoins(coins);
      ZToast.showOn(
        overlay,
        '${toPersianDigits(GameConstants.rewardedAdCoins)} سکه به حسابت اضافه شد!',
        kind: ZToastKind.success,
      );
    } catch (_) {
      ZToast.showOn(
        overlay,
        'اتصال برقرار نشد؛ دوباره تلاش کن',
        kind: ZToastKind.error,
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ads = getIt<AdService>();
    if (!ads.rewardedEnabled || getIt<AuthCubit>().isGuest) {
      return const SizedBox.shrink();
    }
    final z = context.z;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        ZSpacing.screenGutter,
        0,
        ZSpacing.screenGutter,
        ZSpacing.md,
      ),
      child: SolidCard(
        padding: const EdgeInsets.all(ZSpacing.lg),
        radius: ZRadius.cardMax,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'سکهٔ رایگان',
              style: ZTypography.cardTitle.copyWith(color: z.ink),
            ),
            const SizedBox(height: ZSpacing.xs),
            Text(
              'با دیدن یک تبلیغ کوتاه ${toPersianDigits(GameConstants.rewardedAdCoins)} سکه هدیه بگیر.',
              style: ZTypography.body.copyWith(color: z.ink60),
            ),
            const SizedBox(height: ZSpacing.md),
            AccentButton(
              label: _busy ? 'کمی صبر کن…' : 'دیدن تبلیغ',
              onPressed: _busy ? null : _watch,
            ),
          ],
        ),
      ),
    );
  }
}

(String, String) _messageFor(RewardItem item) {
  final coins = toPersianDigits(item.coins);
  switch (item.kind) {
    case 'streak':
      return (
        'پاداش روزهای پیاپی',
        '${toPersianDigits(item.detail)} روز پیاپی بازی کردی! $coins سکه هدیه بگیر.',
      );
    case 'weekly_rank':
      return (
        'پاداش جدول هفتگی',
        'در جدول هفتگی رتبهٔ ${toPersianDigits(item.detail)} شدی! $coins سکه هدیه بگیر.',
      );
    case 'daily_rank':
      return (
        'جایزهٔ چالش روزانه',
        'در چالش دیروز رتبهٔ ${toPersianDigits(item.detail)} شدی! $coins سکه هدیه بگیر.',
      );
    case 'daily_done':
      return (
        'پاداش چالش روزانه',
        'برای شرکت در چالش دیروز $coins سکه هدیه بگیر.',
      );
    case 'daily_login':
      return ('پاداش ورود روزانه', 'برای سر زدن امروز $coins سکه هدیه بگیر.');
    default:
      final name = item.detail.isEmpty ? 'دوستت' : item.detail;
      return (
        'هدیهٔ دعوت',
        '$name با کد دعوت تو وارد بازی شد. $coins سکه هدیه بگیر!',
      );
  }
}

class _RewardTile extends StatefulWidget {
  final RewardItem item;

  const _RewardTile({required this.item});

  @override
  State<_RewardTile> createState() => _RewardTileState();
}

class _RewardTileState extends State<_RewardTile> {
  bool _claiming = false;

  Future<void> _claim() async {
    setState(() => _claiming = true);
    final overlay = Overlay.of(context, rootOverlay: true);
    try {
      final coins = await getIt<RewardsCubit>().claim(widget.item.id);
      ZToast.showOn(
        overlay,
        coinsAwardedMessage(coins),
        kind: ZToastKind.success,
      );
    } on RewardsException catch (e) {
      // Already claimed elsewhere → resync the list instead of showing an error.
      if (e.code == 'reward_not_found') {
        await getIt<RewardsCubit>().refresh();
      } else {
        ZToast.showOn(overlay, errorMessageFor(e.code), kind: ZToastKind.error);
      }
    }
    if (mounted) setState(() => _claiming = false);
  }

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    final item = widget.item;
    final (title, body) = _messageFor(item);
    return SolidCard(
      padding: const EdgeInsets.all(ZSpacing.lg),
      radius: ZRadius.cardMax,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: ZTypography.cardTitle.copyWith(
              color: item.claimed ? z.ink40 : z.ink,
            ),
          ),
          const SizedBox(height: 4),
          Text(body, style: ZTypography.body.copyWith(color: z.ink60)),
          const SizedBox(height: ZSpacing.md),
          if (item.claimed)
            Text(
              'دریافت شد ✓',
              style: ZTypography.metaLabel.copyWith(color: z.teal),
            )
          else
            AccentButton(
              label:
                  _claiming
                      ? '...'
                      : 'دریافت ${toPersianDigits(item.coins)} سکه',
              accent: ZAccentColor.amber,
              onPressed: _claiming ? null : _claim,
            ),
        ],
      ),
    );
  }
}
