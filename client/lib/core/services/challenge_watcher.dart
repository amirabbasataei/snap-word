import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';
import 'package:wordchain/features/auth/cubit/auth_cubit.dart';
import 'package:wordchain/features/friends/data/friends_repository.dart';
import 'package:wordchain/features/game/view/game_screen.dart';

/// Sends the challenger into the private room as soon as the challenged friend
/// accepts, from whatever screen they are on. Push isn't wired, so this polls
/// while the app is in the foreground and the user is signed in.
class ChallengeWatcher with WidgetsBindingObserver {
  ChallengeWatcher({
    required FriendsRepository repository,
    required AuthCubit auth,
    required GoRouter router,
  }) : _repo = repository,
       _auth = auth,
       _router = router;

  static const _interval = Duration(seconds: 2);

  final FriendsRepository _repo;
  final AuthCubit _auth;
  final GoRouter _router;

  Timer? _timer;
  bool _checking = false;
  final Set<String> _handled = {};

  void start() {
    WidgetsBinding.instance.addObserver(this);
    _timer ??= Timer.periodic(_interval, (_) => _check());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _timer ??= Timer.periodic(_interval, (_) => _check());
      _check();
    } else {
      _timer?.cancel();
      _timer = null;
    }
  }

  Future<void> _check() async {
    if (_checking || _auth.state is! AuthAuthenticated) return;
    // Already in a match — never yank the player out of it.
    if (_router.routerDelegate.currentConfiguration.uri.path == '/game') return;
    _checking = true;
    try {
      final joinable = await _repo.fetchJoinableChallenges();
      for (final c in joinable) {
        if (!_handled.add(c.id)) continue;
        _router.push(
          '/game',
          extra: GameRouteArgs(
            mode: c.mode,
            opponentType: 'multiplayer',
            roomId: c.roomId,
            opponentName: c.opponent,
          ),
        );
        break;
      }
    } finally {
      _checking = false;
    }
  }
}
