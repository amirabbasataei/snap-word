import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:wordchain/core/di/injection.dart';
import 'package:wordchain/core/services/ad_service.dart';
import 'package:wordchain/core/theme/app_scene_tokens.dart';
import 'package:wordchain/core/utils/error_messages.dart';
import 'package:wordchain/core/utils/persian_digits.dart';
import 'package:wordchain/core/widgets/z_empty_state.dart';
import 'package:wordchain/core/widgets/z_load_state.dart';
import 'package:wordchain/core/widgets/z_mascot.dart';
import 'package:wordchain/core/widgets/z_state_card.dart';
import 'package:wordchain/core/widgets/z_toast.dart';
import 'package:wordchain/features/auth/cubit/auth_cubit.dart';
import 'package:wordchain/features/game/data/game_constants.dart';
import 'package:wordchain/features/game/data/game_repository.dart';
import 'package:wordchain/features/game/view/widgets/z_over_hero.dart';
import 'package:wordchain/features/home/view/widgets/home_scene_background.dart';
import 'package:wordchain/features/rewards/cubit/rewards_cubit.dart';
import 'package:wordchain/features/rewards/data/rewards_repository.dart';
import 'package:wordchain/features/rewards/view/widgets/reward_format.dart';
import 'package:wordchain/features/rewards/view/widgets/reward_tile.dart';
import 'package:wordchain/features/rewards/view/widgets/rewards_free_coins.dart';
import 'package:wordchain/features/rewards/view/widgets/rewards_header.dart';
import 'package:wordchain/features/rewards/view/widgets/rewards_summary.dart';

/// «جایزه‌ها» — the claimable prizes behind the home gift icon (canvas
/// `ZAwards`, frame 11a): the header with the live coin balance, the amber
/// summary card and one card per prize. Claiming is `POST /rewards/:id/claim`
/// (through [RewardsCubit]); the balance is the server's, read with the list.
///
/// A pushed route, not a tab. Signed-out players have nothing to show (the
/// cubit reports an empty, loaded list). A claimed prize stays on the list,
/// greyed, until the server drops it a day later.
class RewardsScreen extends StatefulWidget {
  const RewardsScreen({super.key});

  @override
  State<RewardsScreen> createState() => _RewardsScreenState();
}

class _RewardsScreenState extends State<RewardsScreen> {
  final _claiming = <String>{};
  bool _watching = false;

  @override
  void initState() {
    super.initState();
    getIt<RewardsCubit>().refresh();
  }

  void _back() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/home');
    }
  }

  Future<void> _claim(RewardItem item) async {
    if (!_claiming.add(item.id)) return;
    setState(() {});
    final overlay = Overlay.of(context, rootOverlay: true);
    try {
      final coins = await getIt<RewardsCubit>().claim(item.id);
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
    _claiming.remove(item.id);
    if (mounted) setState(() {});
  }

  Future<void> _watchAd() async {
    setState(() => _watching = true);
    final overlay = Overlay.of(context, rootOverlay: true);
    try {
      final watched = await getIt<AdService>().showRewardedAd();
      if (!watched) {
        ZToast.showOn(overlay, adUnavailableMessage, kind: ZToastKind.error);
        return;
      }
      final coins = await getIt<GameRepository>().claimRewardedAd();
      await getIt<AuthCubit>().setCoins(coins);
      ZToast.showOn(
        overlay,
        coinsAwardedMessage(GameConstants.rewardedAdCoins),
        kind: ZToastKind.success,
      );
    } catch (_) {
      ZToast.showOn(overlay, networkErrorMessage, kind: ZToastKind.error);
    } finally {
      if (mounted) setState(() => _watching = false);
    }
  }

  bool get _adsOffered =>
      getIt<AdService>().rewardedEnabled && !getIt<AuthCubit>().isGuest;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.zs.sky3,
      body: Stack(
        fit: StackFit.expand,
        children: [
          const HomeSceneBackground(),
          SafeArea(
            child: BlocBuilder<RewardsCubit, RewardsState>(
              bloc: getIt<RewardsCubit>(),
              builder: (context, state) {
                return Column(
                  children: [
                    ZOverEnter(
                      kind: ZOverEnterKind.up,
                      delayMs: 0,
                      child: BlocBuilder<AuthCubit, AuthState>(
                        bloc: getIt<AuthCubit>(),
                        builder:
                            (context, auth) => RewardsHeader(
                              coins: auth is AuthAuthenticated ? auth.coins : 0,
                              onBack: _back,
                            ),
                      ),
                    ),
                    Expanded(child: _body(context, state)),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _body(BuildContext context, RewardsState state) {
    if (!state.loaded) {
      final error = state.error;
      return _stateCard(
        error == null
            ? const ZLoadState.loading()
            : ZLoadState.error(
              message: error,
              onRetry: () => getIt<RewardsCubit>().refresh(),
            ),
      );
    }
    final items = sortRewards(state.items);
    final ready = items.where((i) => !i.claimed).length;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
      children: [
        if (items.isNotEmpty)
          ZOverEnter(
            kind: ZOverEnterKind.up,
            delayMs: 120,
            child: RewardsSummary(
              ready: ready,
              coins: readyCoins(items),
              anyClaimed: ready < items.length,
            ),
          ),
        if (_adsOffered) ...[
          const SizedBox(height: 16),
          ZOverEnter(
            kind: ZOverEnterKind.up,
            delayMs: 160,
            child: RewardsFreeCoinsCard(
              body:
                  'با دیدن یک تبلیغ کوتاه ${toPersianDigits(GameConstants.rewardedAdCoins)} سکه هدیه بگیر.',
              busy: _watching,
              onWatch: _watchAd,
            ),
          ),
        ],
        if (items.isEmpty) ...[
          if (_adsOffered) const SizedBox(height: 16),
          const ZStateCard(
            child: ZEmptyState(
              title: 'هدیه‌ای نداری',
              body: 'چالش روزانه، بازی پیاپی و دعوت دوستان برایت هدیه می‌آورد.',
              mood: ZMascotMood.idle,
            ),
          ),
        ],
        for (var i = 0; i < items.length; i++) ...[
          SizedBox(height: i == 0 && !_adsOffered ? 16 : 12),
          ZOverEnter(
            kind: ZOverEnterKind.up,
            delayMs: 200 + 50 * (i < 6 ? i : 6),
            child: RewardTile(
              key: ValueKey(items[i].id),
              item: items[i],
              claiming: _claiming.contains(items[i].id),
              onClaim: () => _claim(items[i]),
            ),
          ),
        ],
      ],
    );
  }

  Widget _stateCard(Widget child) => SingleChildScrollView(
    padding: const EdgeInsets.fromLTRB(16, 14, 16, 18),
    child: ZStateCard(child: child),
  );
}
