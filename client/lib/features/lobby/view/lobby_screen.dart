import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:wordchain/core/di/injection.dart';
import 'package:wordchain/core/theme/app_game_metrics.dart';
import 'package:wordchain/core/theme/app_scene_tokens.dart';
import 'package:wordchain/core/utils/avatar_initial.dart';
import 'package:wordchain/core/utils/error_messages.dart';
import 'package:wordchain/core/utils/persian_digits.dart';
import 'package:wordchain/core/widgets/insufficient_coins_dialog.dart';
import 'package:wordchain/core/widgets/z_hud_coin_pill.dart';
import 'package:wordchain/core/widgets/z_ribbon_title.dart';
import 'package:wordchain/core/widgets/z_toast.dart';
import 'package:wordchain/features/auth/cubit/auth_cubit.dart';
import 'package:wordchain/features/friends/data/friends_repository.dart';
import 'package:wordchain/features/game/view/game_screen.dart';
import 'package:wordchain/features/game/view/widgets/z_game_hud.dart';
import 'package:wordchain/features/home/view/widgets/home_scene_background.dart';
import 'package:wordchain/features/lobby/cubit/lobby_cubit.dart';
import 'package:wordchain/features/lobby/cubit/lobby_players_cubit.dart';
import 'package:wordchain/features/lobby/view/widgets/lobby_cta.dart';
import 'package:wordchain/features/lobby/view/widgets/lobby_friends.dart';
import 'package:wordchain/features/lobby/view/widgets/lobby_stage.dart';
import 'package:wordchain/features/lobby/view/widgets/lobby_stake.dart';
import 'package:wordchain/features/profile/data/profile_repository.dart';

/// «رویارویی آنلاین» — the 1v1 lobby, "A · mascot-led" (canvas `ZLobbyA`).
class LobbyScreen extends StatelessWidget {
  const LobbyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final guest = getIt<AuthCubit>().state is! AuthAuthenticated;
    return MultiBlocProvider(
      providers: [
        BlocProvider(
          create:
              (_) => LobbyCubit(
                repo: getIt(),
                syncService: getIt(),
                notificationService: getIt(),
              ),
        ),
        BlocProvider(
          create: (_) {
            final cubit = LobbyPlayersCubit(
              friends: getIt<FriendsRepository>(),
              profile: getIt<ProfileRepository>(),
            );
            // A guest has no friends or stats to load (both calls are 401).
            if (!guest) cubit.load();
            return cubit;
          },
        ),
      ],
      child: _LobbyView(guest: guest),
    );
  }
}

class _LobbyView extends StatelessWidget {
  final bool guest;

  const _LobbyView({required this.guest});

  static const _mode = 'classic';

  @override
  Widget build(BuildContext context) {
    final zs = context.zs;
    final compact = MediaQuery.sizeOf(context).height < 640;

    return BlocListener<LobbyCubit, LobbyState>(
      listener: (context, state) {
        if (state is LobbyMatchFound) _navigateToGame(context, state);
        if (state is LobbyError && state.insufficientCoins) {
          context.read<LobbyCubit>().reset();
          showInsufficientCoinsDialog(context);
        }
      },
      child: Scaffold(
        backgroundColor: zs.sky3,
        body: Stack(
          children: [
            const Positioned.fill(child: HomeSceneBackground()),
            SafeArea(
              child: Column(
                children: [
                  const _Header(),
                  Expanded(
                    // The friends card takes whatever height is left on a tall
                    // phone; on a short one the page scrolls.
                    child: CustomScrollView(
                      slivers: [
                        SliverToBoxAdapter(
                          child: _Top(guest: guest, compact: compact),
                        ),
                        SliverFillRemaining(
                          hasScrollBody: false,
                          child: _Friends(guest: guest),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _navigateToGame(BuildContext context, LobbyMatchFound state) {
    final authState = getIt<AuthCubit>().state;
    final myPlayerId = authState is AuthAuthenticated ? authState.userId : '';

    context.pushReplacement(
      '/game',
      extra: GameRouteArgs(
        mode: state.mode,
        opponentType: 'multiplayer',
        roomId: state.roomId,
        myPlayerId: myPlayerId,
      ),
    );
  }
}

/// Back button, ribbon title and the live coin balance.
class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(14, 10, 14, 0),
      child: Row(
        children: [
          ZGameBackButton(
            onTap: () => context.canPop() ? context.pop() : context.go('/home'),
          ),
          const Expanded(child: Center(child: ZRibbonTitle('رویارویی آنلاین'))),
          // AuthCubit holds the live balance; fetchStats() never returns coins.
          // A guest has no balance, so the slot is just kept for symmetry.
          BlocBuilder<AuthCubit, AuthState>(
            bloc: getIt<AuthCubit>(),
            builder:
                (context, auth) =>
                    auth is AuthAuthenticated
                        ? MediaQuery.withClampedTextScaling(
                          maxScaleFactor: 1.3,
                          child: ZHudCoinPill(coins: auth.coins),
                        )
                        : const SizedBox(width: ZGame.gameBackButton),
          ),
        ],
      ),
    );
  }
}

/// Stage, match terms and the button — everything the queue itself drives.
class _Top extends StatelessWidget {
  final bool guest;
  final bool compact;

  const _Top({required this.guest, required this.compact});

  @override
  Widget build(BuildContext context) {
    final auth = getIt<AuthCubit>().state;
    final name = auth is AuthAuthenticated ? auth.username : 'تو';
    final me = context.select((LobbyPlayersCubit c) => c.state);

    return BlocBuilder<LobbyCubit, LobbyState>(
      builder: (context, state) {
        final searching = state is LobbySearching;
        final error = state is LobbyError ? state.message : null;
        final mode = switch (state) {
          LobbySearching() => LobbyStageMode.searching,
          LobbyMatchFound() => LobbyStageMode.found,
          LobbyError() => LobbyStageMode.error,
          _ => LobbyStageMode.idle,
        };
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            LobbyStage(
              mode: mode,
              myName: name,
              myInitial: avatarInitial(name),
              myAvatarId: me.avatarId,
              mySubtitle:
                  me.level == null ? null : 'سطح ${toPersianDigits(me.level!)}',
              elapsedSeconds:
                  state is LobbySearching ? state.elapsedSeconds : 0,
              compact: compact,
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
              child: LobbyStakeCard(error: error),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
              child: LobbyCta(
                label:
                    searching
                        ? 'لغو جست‌وجو'
                        : error != null
                        ? 'تلاش دوباره'
                        : 'پیدا کردن حریف',
                cancel: searching,
                onTap:
                    searching
                        ? () => context.read<LobbyCubit>().cancelSearch()
                        : () => _find(context),
              ),
            ),
          ],
        );
      },
    );
  }

  void _find(BuildContext context) {
    // Direct navigation only: Home sends a guest to /login?return=/lobby.
    if (guest) {
      context.push('/login?return=/lobby');
      return;
    }
    context.read<LobbyCubit>().startSearch(_LobbyView._mode);
  }
}

class _Friends extends StatelessWidget {
  final bool guest;

  const _Friends({required this.guest});

  Future<void> _invite(BuildContext context, FriendModel friend) async {
    final result = await context.read<LobbyPlayersCubit>().invite(friend);
    if (!context.mounted) return;
    // Joining the room on accept is handled app-wide by ChallengeWatcher.
    switch (result) {
      case LobbyInviteSent():
        ZToast.show(
          context,
          friendInviteSentMessage(friend.username),
          kind: ZToastKind.success,
        );
      case LobbyInviteNeedsCoins():
        showInsufficientCoinsDialog(context);
      case LobbyInviteFailed(:final message):
        ZToast.show(context, message, kind: ZToastKind.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.watch<LobbyPlayersCubit>().state;
    final notice =
        guest
            ? LobbyFriendsNotice.guest
            : switch (p.status) {
              LobbyFriendsStatus.loading => LobbyFriendsNotice.loading,
              LobbyFriendsStatus.error => LobbyFriendsNotice.error,
              LobbyFriendsStatus.loaded when p.friends.isEmpty =>
                LobbyFriendsNotice.empty,
              LobbyFriendsStatus.loaded => null,
            };
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 18),
      child: LobbyFriendsCard(
        notice: notice,
        friends: p.friends,
        invited: p.invited,
        inviting: p.inviting,
        errorMessage: p.error,
        onInvite: (f) => _invite(context, f),
        onNoticeAction: switch (notice) {
          LobbyFriendsNotice.error =>
            () => context.read<LobbyPlayersCubit>().load(),
          LobbyFriendsNotice.guest =>
            () => context.push('/login?return=/lobby'),
          _ => () => context.go('/friends'),
        },
      ),
    );
  }
}
