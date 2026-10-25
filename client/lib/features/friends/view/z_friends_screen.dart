import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:wordchain/core/di/injection.dart';
import 'package:wordchain/core/services/share_service.dart';
import 'package:wordchain/core/theme/app_game_metrics.dart';
import 'package:wordchain/core/theme/app_scene_tokens.dart';
import 'package:wordchain/core/theme/app_tokens.dart';
import 'package:wordchain/core/utils/tab_refresh.dart';
import 'package:wordchain/core/widgets/chunky.dart';
import 'package:wordchain/core/widgets/insufficient_coins_dialog.dart';
import 'package:wordchain/core/widgets/notification_permission_dialog.dart';
import 'package:wordchain/core/widgets/z_dialog.dart';
import 'package:wordchain/core/widgets/z_empty_state.dart';
import 'package:wordchain/core/widgets/z_load_state.dart';
import 'package:wordchain/core/widgets/z_ribbon_title.dart';
import 'package:wordchain/core/widgets/z_toast.dart';
import 'package:wordchain/features/auth/cubit/auth_cubit.dart';
import 'package:wordchain/features/friends/cubit/friends_cubit.dart';
import 'package:wordchain/features/friends/cubit/invite_code_cubit.dart';
import 'package:wordchain/features/friends/data/friends_repository.dart';
import 'package:wordchain/features/friends/view/friend_challenge_dialog.dart';
import 'package:wordchain/features/friends/view/widgets/friends_dialogs.dart';
import 'package:wordchain/features/friends/view/widgets/friends_invite_card.dart';
import 'package:wordchain/features/friends/view/widgets/friends_list_card.dart';
import 'package:wordchain/features/friends/view/widgets/friends_parts.dart';
import 'package:wordchain/features/friends/view/widgets/friends_requests_card.dart';
import 'package:wordchain/features/friends/view/widgets/friends_search_field.dart';
import 'package:wordchain/features/game/view/game_screen.dart';
import 'package:wordchain/features/home/view/widgets/home_scene_background.dart';
import 'package:wordchain/features/messages/cubit/messages_cubit.dart';

/// «دوستان» — the Friends tab, "A · mascot-led" (canvas `ZFriendsA`): a sky
/// scene, the ribbon title with an add-friend button, a search box, the
/// pending requests / challenges, the player's invite code and the friends
/// list with «دعوت به بازی».
///
/// The canvas also shows per-friend «با هم: ۴ برد · ۲ باخت» / «بهترین
/// زنجیر» lines and online state; the server sends neither (`GET /friends` is
/// `user_id`, `username`, `friend_since` — todo.md 2.6), so a friend's sub-line
/// is this week's score and there is no presence.
class ZFriendsScreen extends StatelessWidget {
  const ZFriendsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // This branch is kept alive by the shell's IndexedStack, so a one-time
    // `isGuest` read never picked up sign-out (or another account signing in).
    // `BlocBuilder<AuthCubit>` + a userId-derived `Key` forces fresh cubits on
    // every real auth transition.
    return BlocBuilder<AuthCubit, AuthState>(
      bloc: getIt<AuthCubit>(),
      builder: (context, authState) {
        if (authState is! AuthAuthenticated) {
          return const _FriendsFrame(onAdd: null, child: _GuestBody());
        }
        return MultiBlocProvider(
          key: ValueKey('friends-${authState.userId}'),
          providers: [
            BlocProvider(
              create:
                  (_) =>
                      FriendsCubit(repository: getIt<FriendsRepository>())
                        ..load(),
            ),
            BlocProvider(
              create:
                  (_) => InviteCodeCubit(
                    fetch: getIt<AuthCubit>().fetchMyReferralCode,
                  )..load(),
            ),
          ],
          child: TabRefreshListener(
            index: MainTab.friends,
            onRefresh: (ctx) {
              ctx.read<FriendsCubit>().load(silent: true);
              final code = ctx.read<InviteCodeCubit>();
              if (code.state.status != InviteCodeStatus.ready) code.load();
              maybeAskNotificationPermission(ctx);
            },
            child: const _FriendsView(),
          ),
        );
      },
    );
  }
}

/// Scene, header and a body slot; everything every state shares.
class _FriendsFrame extends StatelessWidget {
  final VoidCallback? onAdd;
  final Widget child;

  const _FriendsFrame({required this.onAdd, required this.child});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.zs.sky3,
      body: Stack(
        children: [
          const Positioned.fill(child: HomeSceneBackground()),
          SafeArea(
            child: Column(
              children: [_Header(onAdd: onAdd), Expanded(child: child)],
            ),
          ),
        ],
      ),
    );
  }
}

/// Ribbon title, with the add-friend button on the end side (canvas: a 44dp
/// spacer on the start side keeps the title centred).
class _Header extends StatelessWidget {
  final VoidCallback? onAdd;

  const _Header({required this.onAdd});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(14, 10, 14, 0),
      child: Row(
        children: [
          const SizedBox(width: ZGame.gameBackButton),
          const Expanded(
            child: Center(
              child: ZRibbonTitle(
                'دوستان',
                accent: ZDialogAccent.indigo,
                expand: false,
              ),
            ),
          ),
          if (onAdd != null)
            FriendsGlyphButton(
              glyph: FriendsGlyph.addFriend,
              semanticLabel: 'افزودن دوست',
              onTap: onAdd!,
            )
          else
            const SizedBox(width: ZGame.gameBackButton),
        ],
      ),
    );
  }
}

/// A full-width card for the states that have no list (loading, failed, guest).
class _StateCard extends StatelessWidget {
  final Widget child;

  const _StateCard({required this.child});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 18),
      child: ChunkyBox(
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

class _GuestBody extends StatelessWidget {
  const _GuestBody();

  @override
  Widget build(BuildContext context) {
    return _StateCard(
      child: ZEmptyState(
        title: 'دوستانت را پیدا کن',
        body: 'ثبت‌نام کن تا دوست اضافه کنی، چالش بفرستی و رقابت کنی!',
        actionLabel: 'ثبت‌نام رایگان',
        onAction: () => context.push('/login?return=/friends'),
      ),
    );
  }
}

class _FriendsView extends StatefulWidget {
  const _FriendsView();

  @override
  State<_FriendsView> createState() => _FriendsViewState();
}

class _FriendsViewState extends State<_FriendsView> {
  final _search = TextEditingController();
  StreamSubscription<void>? _messagesSub;

  @override
  void initState() {
    super.initState();
    _search.addListener(() => setState(() {}));
    _messagesSub = getIt<MessagesCubit>().friendsChanged.listen((_) {
      if (mounted) context.read<FriendsCubit>().load(silent: true);
    });
  }

  @override
  void dispose() {
    _messagesSub?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    final cubit = context.read<FriendsCubit>();
    final username = await showAddFriendDialog(context);
    if (username != null) await cubit.sendFriendRequest(username);
  }

  Future<void> _challenge(FriendModel friend) async {
    final cubit = context.read<FriendsCubit>();
    final send = await showFriendChallengeDialog(
      context,
      friendUsername: friend.username,
    );
    if (send) await cubit.sendChallenge(friend.userId, 'classic');
  }

  Future<void> _remove(FriendModel friend) async {
    final cubit = context.read<FriendsCubit>();
    final remove = await showRemoveFriendDialog(
      context,
      friendUsername: friend.username,
    );
    if (remove) await cubit.removeFriend(friend.userId);
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<FriendsCubit, FriendsState>(
      listener: (context, state) {
        if (state is ChallengAccepted) {
          context.push(
            '/game',
            extra: GameRouteArgs(
              mode: state.mode,
              opponentType: 'multiplayer',
              roomId: state.roomId,
              opponentName: state.opponentName,
            ),
          );
        }
        if (state is FriendsInsufficientCoins) {
          showInsufficientCoinsDialog(context);
        }
        if (state is FriendActionSuccess) {
          ZToast.show(context, state.message, kind: ZToastKind.success);
        }
        if (state is FriendsLoaded) {
          getIt<MessagesCubit>().setPending(
            state.pendingRequests,
            state.pendingChallenges,
          );
        }
        if (state is FriendsLoaded && state.actionError != null) {
          ZToast.show(context, state.actionError!, kind: ZToastKind.error);
        }
      },
      child: _FriendsFrame(
        onAdd: _add,
        child: BlocBuilder<FriendsCubit, FriendsState>(
          // One-shot signals (toast, navigation, coins dialog) must not blank
          // the list they were raised from.
          buildWhen:
              (_, s) =>
                  s is FriendsLoaded ||
                  s is FriendsLoading ||
                  s is FriendsInitial ||
                  s is FriendsError,
          builder: (context, state) {
            if (state is FriendsLoaded) return _loaded(context, state);
            if (state is FriendsError) {
              return _StateCard(
                child: ZLoadState.error(
                  message: state.message,
                  onRetry: () => context.read<FriendsCubit>().load(),
                ),
              );
            }
            return const _StateCard(child: ZLoadState.loading());
          },
        ),
      ),
    );
  }

  Widget _loaded(BuildContext context, FriendsLoaded state) {
    final cubit = context.read<FriendsCubit>();
    final query = _search.text.trim().toLowerCase();
    final shown =
        query.isEmpty
            ? state.friends
            : state.friends
                .where((f) => f.username.toLowerCase().contains(query))
                .toList();
    final hasPending =
        state.pendingRequests.isNotEmpty || state.pendingChallenges.isNotEmpty;
    return ListView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 18),
      children: [
        if (state.friends.isNotEmpty) ...[
          FriendsSearchField(controller: _search),
          const SizedBox(height: 11),
        ],
        if (hasPending) ...[
          FriendsRequestsCard(
            requests: state.pendingRequests,
            challenges: state.pendingChallenges,
            onAcceptRequest: (r) => cubit.respondToRequest(r.requesterId, true),
            onDeclineRequest:
                (r) => cubit.respondToRequest(r.requesterId, false),
            onAcceptChallenge:
                (c) => cubit.respondToChallenge(
                  c.id,
                  true,
                  c.mode,
                  opponentName: c.challengerUsername,
                ),
            onDeclineChallenge:
                (c) => cubit.respondToChallenge(c.id, false, c.mode),
          ),
          const SizedBox(height: 16),
        ],
        BlocBuilder<InviteCodeCubit, InviteCodeState>(
          builder:
              (context, invite) => FriendsInviteCard(
                state: invite,
                onRetry: () => context.read<InviteCodeCubit>().load(),
                onShare:
                    () => getIt<ShareService>().shareInvite(code: invite.code!),
              ),
        ),
        const SizedBox(height: 16),
        FriendsListCard(
          friends: shown,
          totalFriends: state.friends.length,
          invited: state.invited,
          onInvite: _challenge,
          onRemove: _remove,
          onAddFriend: _add,
        ),
      ],
    );
  }
}
