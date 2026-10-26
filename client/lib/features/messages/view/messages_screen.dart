import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:wordchain/core/di/injection.dart';
import 'package:wordchain/core/theme/app_scene_tokens.dart';
import 'package:wordchain/core/utils/error_messages.dart';
import 'package:wordchain/core/widgets/insufficient_coins_dialog.dart';
import 'package:wordchain/core/widgets/z_empty_state.dart';
import 'package:wordchain/core/widgets/z_load_state.dart';
import 'package:wordchain/core/widgets/z_mascot.dart';
import 'package:wordchain/core/widgets/z_state_card.dart';
import 'package:wordchain/core/widgets/z_toast.dart';
import 'package:wordchain/features/friends/data/friends_repository.dart';
import 'package:wordchain/features/game/view/game_screen.dart';
import 'package:wordchain/features/game/view/widgets/z_over_hero.dart';
import 'package:wordchain/features/home/view/widgets/home_scene_background.dart';
import 'package:wordchain/features/messages/cubit/messages_cubit.dart';
import 'package:wordchain/features/messages/view/widgets/message_format.dart';
import 'package:wordchain/features/messages/view/widgets/message_tile.dart';
import 'package:wordchain/features/messages/view/widgets/messages_header.dart';

/// «اعلان‌ها» — the actionable invitations (canvas `ZNotifs`, frame 12a):
/// pending friend requests and friend challenges, one card each, answered in
/// place. Accept / decline reuse the friends endpoints (through
/// [MessagesCubit]); accepting a challenge enters the room. Claimable coin
/// prizes live on the rewards screen.
///
/// A pushed route, not a tab. The canvas is a general notification feed (tabs,
/// read state, day groups); the product only has these two kinds of pending
/// invitation, so that is all the cards show (REDESIGN_PLAN.md § ZNotifs).
class MessagesScreen extends StatefulWidget {
  const MessagesScreen({super.key});

  @override
  State<MessagesScreen> createState() => _MessagesScreenState();
}

class _MessagesScreenState extends State<MessagesScreen> {
  /// Invitations with an answer in flight (`r:<requesterId>` / `c:<id>`), so a
  /// second tap is ignored.
  final _busy = <String>{};

  @override
  void initState() {
    super.initState();
    getIt<MessagesCubit>().refresh();
  }

  void _back() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/home');
    }
  }

  Future<void> _answer(String key, Future<void> Function() action) async {
    if (!_busy.add(key)) return;
    setState(() {});
    try {
      await action();
    } finally {
      _busy.remove(key);
      if (mounted) setState(() {});
    }
  }

  Future<void> _respondRequest(PendingRequest r, bool accept) {
    return _answer('r:${r.requesterId}', () async {
      final overlay = Overlay.of(context, rootOverlay: true);
      try {
        await getIt<MessagesCubit>().respondToRequest(r.requesterId, accept);
      } on FriendsException catch (e) {
        ZToast.showOn(overlay, errorMessageFor(e.code), kind: ZToastKind.error);
      }
    });
  }

  Future<void> _respondChallenge(PendingChallenge c, bool accept) {
    return _answer('c:${c.id}', () async {
      final overlay = Overlay.of(context, rootOverlay: true);
      try {
        final roomId = await getIt<MessagesCubit>().respondToChallenge(
          c.id,
          accept,
        );
        if (roomId != null && mounted) {
          context.push(
            '/game',
            extra: GameRouteArgs(
              mode: c.mode,
              opponentType: 'multiplayer',
              roomId: roomId,
              opponentName: c.challengerUsername,
            ),
          );
        }
      } on FriendsException catch (e) {
        if (e.code == 'insufficient_coins') {
          // The invite stays pending so it can be accepted once coins are earned.
          if (mounted) await showInsufficientCoinsDialog(context);
          return;
        }
        // Expired or answered elsewhere → resync instead of a dead-end error.
        await getIt<MessagesCubit>().refresh();
        ZToast.showOn(
          overlay,
          e.code == 'challenger_cannot_afford'
              ? errorMessageFor(e.code)
              : errorMessageFor('challenge_expired'),
          kind: ZToastKind.error,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.zs.sky3,
      body: Stack(
        fit: StackFit.expand,
        children: [
          const HomeSceneBackground(),
          SafeArea(
            child: Column(
              children: [
                ZOverEnter(
                  kind: ZOverEnterKind.up,
                  delayMs: 0,
                  child: MessagesHeader(onBack: _back),
                ),
                Expanded(
                  child: BlocBuilder<MessagesCubit, MessagesState>(
                    bloc: getIt<MessagesCubit>(),
                    builder: _body,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _body(BuildContext context, MessagesState state) {
    if (!state.loaded) {
      final error = state.error;
      return _stateCard(
        error == null
            ? const ZLoadState.loading()
            : ZLoadState.error(
              message: error,
              onRetry: () => getIt<MessagesCubit>().refresh(),
            ),
      );
    }
    if (state.count == 0) {
      return _stateCard(
        const ZEmptyState(
          title: 'اعلانی نداری',
          body: 'هر خبر تازه‌ای برسد، همین‌جا می‌بینی.',
          mood: ZMascotMood.idle,
        ),
      );
    }
    var i = 0;
    int delay() => 180 + 50 * (i++ < 6 ? i - 1 : 6);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
      children: [
        for (final r in state.requests)
          Padding(
            padding: EdgeInsets.only(top: i == 0 ? 0 : 10),
            child: ZOverEnter(
              key: ValueKey('r:${r.requesterId}'),
              kind: ZOverEnterKind.up,
              delayMs: delay(),
              child: MessageTile(
                face: requestFace(r),
                busy: _busy.contains('r:${r.requesterId}'),
                onAccept: () => _respondRequest(r, true),
                onDecline: () => _respondRequest(r, false),
              ),
            ),
          ),
        for (final c in state.challenges)
          Padding(
            padding: EdgeInsets.only(top: i == 0 ? 0 : 10),
            child: ZOverEnter(
              key: ValueKey('c:${c.id}'),
              kind: ZOverEnterKind.up,
              delayMs: delay(),
              child: MessageTile(
                face: challengeFace(c),
                busy: _busy.contains('c:${c.id}'),
                onAccept: () => _respondChallenge(c, true),
                onDecline: () => _respondChallenge(c, false),
              ),
            ),
          ),
      ],
    );
  }

  Widget _stateCard(Widget child) => SingleChildScrollView(
    padding: const EdgeInsets.fromLTRB(16, 14, 16, 18),
    child: ZStateCard(child: child),
  );
}
