import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:wordchain/core/di/injection.dart';
import 'package:wordchain/core/services/monetization_service.dart';
import 'package:wordchain/core/services/share_service.dart';
import 'package:wordchain/core/theme/app_game_metrics.dart';
import 'package:wordchain/core/theme/app_scene_tokens.dart';
import 'package:wordchain/core/theme/app_tokens.dart';
import 'package:wordchain/core/theme/theme_cubit.dart';
import 'package:wordchain/core/utils/tab_refresh.dart';
import 'package:wordchain/core/widgets/chunky.dart';
import 'package:wordchain/core/widgets/z_empty_state.dart';
import 'package:wordchain/core/widgets/z_load_state.dart';
import 'package:wordchain/core/widgets/z_toast.dart';
import 'package:wordchain/features/auth/cubit/auth_cubit.dart';
import 'package:wordchain/features/auth/view/widgets/edit_username_dialog.dart';
import 'package:wordchain/features/auth/view/widgets/referral_dialog.dart';
import 'package:wordchain/features/friends/cubit/invite_code_cubit.dart';
import 'package:wordchain/features/home/view/widgets/home_scene_background.dart';
import 'package:wordchain/features/profile/view/widgets/profile_word_card.dart';
import 'package:wordchain/features/words/view/my_word_reports_dialog.dart';
import 'package:wordchain/features/words/view/suggest_word_dialog.dart';
import 'package:wordchain/features/profile/cubit/profile_cubit.dart';
import 'package:wordchain/features/profile/data/profile_repository.dart';
import 'package:wordchain/features/profile/view/widgets/profile_header.dart';
import 'package:wordchain/features/profile/view/widgets/profile_invite_card.dart';
import 'package:wordchain/features/profile/view/widgets/profile_premium_card.dart';
import 'package:wordchain/features/profile/view/widgets/profile_settings.dart';
import 'package:wordchain/features/profile/view/widgets/profile_sheets.dart';
import 'package:wordchain/features/profile/view/widgets/profile_stats_grid.dart';
import 'package:wordchain/features/profile/view/widgets/profile_xp_bar.dart';
import 'package:wordchain/core/services/analytics_service.dart';

/// «پروفایل» — the profile tab, "A · mascot-led" (canvas `ZProfileA`): sky
/// scene, the player's disc in an XP ring, level bar, stat tiles, the invite
/// card and the settings controls.
///
/// Omitted because nothing backs them (see REDESIGN_PLAN.md § ZProfile): the
/// badges row, the join date, «برد آنلاین», accuracy % and unique-word count,
/// the invite counter / chest progress and the cosmetic sound / reminder
/// toggles. The canvas's gear has no screen behind it, so the coin balance
/// takes that corner.
class ZProfileScreen extends StatelessWidget {
  const ZProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // This screen lives inside `_MainShell`'s `StatefulShellRoute.indexedStack`
    // (`app_router.dart`), which keeps every branch's widget alive forever —
    // switching tabs never rebuilds it. Watching `AuthCubit` and keying the
    // providers by identity (guest vs. a specific userId) recreates
    // `ProfileCubit` — and re-runs `.load()` — on every real auth transition,
    // so sign-out, or signing in as someone else, never leaves the previous
    // account on screen.
    return BlocBuilder<AuthCubit, AuthState>(
      bloc: getIt<AuthCubit>(),
      buildWhen:
          (a, b) =>
              (a is AuthAuthenticated) != (b is AuthAuthenticated) ||
              (a is AuthAuthenticated &&
                  b is AuthAuthenticated &&
                  a.userId != b.userId),
      builder: (context, authState) {
        final isGuest = authState is! AuthAuthenticated;
        final identity =
            authState is AuthAuthenticated ? authState.userId : 'guest';
        return MultiBlocProvider(
          key: ValueKey('profile-$identity'),
          providers: [
            BlocProvider(
              create:
                  (_) => ProfileCubit(
                    repository: getIt<ProfileRepository>(),
                    statsDao: getIt(),
                    powerupCacheDao: getIt(),
                    isGuest: isGuest,
                  )..load(),
            ),
            if (!isGuest)
              BlocProvider(
                create:
                    (_) => InviteCodeCubit(
                      fetch: getIt<AuthCubit>().fetchMyReferralCode,
                    )..load(),
              ),
          ],
          child: TabRefreshListener(
            index: MainTab.profile,
            onRefresh: (ctx) {
              ctx.read<ProfileCubit>().load(silent: true);
              if (!isGuest) {
                final code = ctx.read<InviteCodeCubit>();
                if (code.state.status != InviteCodeStatus.ready) code.load();
              }
            },
            child: const _ProfileView(),
          ),
        );
      },
    );
  }
}

/// Scene and a body slot — what every state shares.
class _ProfileFrame extends StatelessWidget {
  final Widget child;

  const _ProfileFrame({required this.child});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.zs.sky3,
      body: Stack(
        // Without this a short body (the loading / failed card) would shrink
        // the Stack, and the scene would stop where the content does.
        fit: StackFit.expand,
        children: [
          const Positioned.fill(child: HomeSceneBackground()),
          SafeArea(child: child),
        ],
      ),
    );
  }
}

/// A full-width card for the states that have no profile to show.
class _StateCard extends StatelessWidget {
  final Widget child;

  const _StateCard({required this.child});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 18),
      child: ChunkyBox(
        width: double.infinity,
        fill: context.z.surface,
        depth: ZGame.depthMd,
        radius: 22,
        highlight: false,
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 18),
        child: child,
      ),
    );
  }
}

class _ProfileView extends StatelessWidget {
  const _ProfileView();

  @override
  Widget build(BuildContext context) {
    return _ProfileFrame(
      child: BlocBuilder<ProfileCubit, ProfileState>(
        builder: (context, state) {
          if (state is ProfileLoaded) return _LoadedView(state: state);
          if (state is ProfileError) {
            return _StateCard(
              child: ZLoadState.error(
                message: state.message,
                onRetry: () => context.read<ProfileCubit>().load(),
              ),
            );
          }
          return const _StateCard(child: ZLoadState.loading());
        },
      ),
    );
  }
}

class _LoadedView extends StatelessWidget {
  final ProfileLoaded state;

  const _LoadedView({required this.state});

  void _purchase(BuildContext context, String productId) async {
    trackEvent(AnalyticsEvent.purchaseTap, {'product': productId});
    final result = await getIt<MonetizationService>().purchase(productId);
    if (!context.mounted) return;
    final msg = switch (result.status) {
      PurchaseStatus.success => 'خرید با موفقیت انجام شد!',
      PurchaseStatus.cancelled => 'خرید لغو شد.',
      PurchaseStatus.failed => result.error ?? 'خرید ناموفق بود.',
    };
    ZToast.show(
      context,
      msg,
      kind:
          result.status == PurchaseStatus.success
              ? ZToastKind.success
              : ZToastKind.error,
    );
  }

  void _pickAvatar(BuildContext context) {
    final cubit = context.read<ProfileCubit>();
    showAvatarPicker(
      context,
      selected: state.perks.avatarId,
      onPick: (id) async {
        final error = await cubit.setAvatar(id);
        if (error != null && context.mounted) {
          ZToast.show(context, error, kind: ZToastKind.error);
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final stats = state.stats;
    final signedIn = !state.isGuest;
    return BlocBuilder<AuthCubit, AuthState>(
      bloc: getIt<AuthCubit>(),
      builder: (context, auth) {
        final username = auth is AuthAuthenticated ? auth.username : 'مهمان';
        final coins = auth is AuthAuthenticated ? auth.coins : 0;
        return ListView(
          padding: const EdgeInsets.only(bottom: 18),
          children: [
            ProfileHeader(
              username: username,
              signedIn: signedIn,
              level: stats.level,
              xpFraction: ProfileXpBar.fraction(
                stats.xpInLevel,
                stats.xpForNext,
              ),
              xpInLevel: stats.xpInLevel,
              xpForNext: stats.xpForNext,
              avatarId: state.perks.avatarId,
              isPremium: state.perks.isPremium,
              coins: coins,
              onCoinsTap:
                  () => showBuyCoinsSheet(
                    context,
                    onPurchase: (id) => _purchase(context, id),
                  ),
              onEdit: () => showEditUsernameDialog(context),
            ),
            if (signedIn)
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 10, 18, 0),
                child: ProfileXpBar(
                  level: stats.level,
                  xpInLevel: stats.xpInLevel,
                  xpForNext: stats.xpForNext,
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
              child: ProfileStatsGrid(stats: stats),
            ),
            if (signedIn) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                child: ProfilePremiumCard(
                  perks: state.perks,
                  onChangeAvatar: () => _pickAvatar(context),
                  onSubscribe: () => _purchase(context, 'premium_monthly'),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                child: BlocBuilder<InviteCodeCubit, InviteCodeState>(
                  builder:
                      (context, invite) => ProfileInviteCard(
                        state: invite,
                        onRetry: () => context.read<InviteCodeCubit>().load(),
                        onShare:
                            () => getIt<ShareService>().shareInvite(
                              code: invite.code!,
                            ),
                        onCopy: () async {
                          await Clipboard.setData(
                            ClipboardData(text: invite.code!),
                          );
                          if (!context.mounted) return;
                          ZToast.show(
                            context,
                            'کد دعوت کپی شد',
                            kind: ZToastKind.success,
                          );
                        },
                      ),
                ),
              ),
            ] else
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                child: ChunkyBox(
                  fill: context.z.surface,
                  depth: ZGame.depthMd,
                  radius: 20,
                  highlight: false,
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                  child: ZEmptyState(
                    mascotSize: 80,
                    title: 'پیشرفتت را ذخیره کن',
                    body:
                        'ثبت‌نام رایگان کن تا پیشرفتت ذخیره شود و قدرت‌های بیشتری باز شود.',
                    actionLabel: 'ثبت‌نام رایگان',
                    onAction: () => context.push('/login?return=/profile'),
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
              child: ProfileWordCard(
                signedIn: signedIn,
                onSuggest: () => showSuggestWordDialog(context),
                onMine: () => showMyWordReportsDialog(context),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
              child: BlocBuilder<ThemeCubit, ThemeMode>(
                bloc: getIt<ThemeCubit>(),
                builder: (context, _) {
                  // The brightness on screen, so ThemeMode.system shows
                  // correctly.
                  final brightness = Theme.of(context).brightness;
                  return ProfileSettings(
                    isDark: brightness == Brightness.dark,
                    onToggleTheme: () => getIt<ThemeCubit>().toggle(brightness),
                    signedIn: signedIn,
                    onRedeem: () => showReferralDialog(context),
                    onLogout: () => getIt<AuthCubit>().logout(),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}
