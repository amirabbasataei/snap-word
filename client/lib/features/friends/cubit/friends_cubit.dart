import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:wordchain/features/friends/data/friends_repository.dart';
import 'package:wordchain/core/utils/error_messages.dart';
import 'package:wordchain/features/game/data/game_constants.dart';

part 'friends_state.dart';

class FriendsCubit extends Cubit<FriendsState> {
  final FriendsRepository _repo;

  FriendsCubit({required FriendsRepository repository})
    : _repo = repository,
      super(const FriendsInitial());

  bool _hasLoaded = false;

  /// Friends invited a moment ago, each with the timer that clears the mark.
  final _invitedTimers = <String, Timer>{};

  /// [silent] reloads in the background: no spinner, and a failure keeps
  /// whatever is already on screen.
  Future<void> load({bool silent = false}) async {
    final quiet = silent && _hasLoaded;
    if (!quiet) emit(const FriendsLoading());
    try {
      final results = await Future.wait([
        _repo.fetchFriends(),
        _repo.fetchPendingRequests(),
        _repo.fetchPendingChallenges(),
      ]);
      final friends = results[0] as List<FriendModel>;
      final requests = results[1] as List<PendingRequest>;
      final rawChallenges = results[2] as List<PendingChallenge>;

      // Enrich challenge challenger names using the friends list.
      final friendMap = {for (final f in friends) f.userId: f.username};
      final challenges =
          rawChallenges.map((c) {
            final name = friendMap[c.challengerId];
            return name != null
                ? PendingChallenge(
                  id: c.id,
                  challengerId: c.challengerId,
                  challengerUsername: name,
                  mode: c.mode,
                  expiresAt: c.expiresAt,
                )
                : c;
          }).toList();

      emit(
        FriendsLoaded(
          friends: friends,
          pendingRequests: requests,
          pendingChallenges: challenges,
          invited: _invitedNow,
        ),
      );
      _hasLoaded = true;
    } on FriendsException catch (e) {
      if (!quiet) emit(FriendsError(e.message));
    } catch (_) {
      if (!quiet) emit(const FriendsError(loadFriendsFailedMessage));
    }
  }

  Set<String> get _invitedNow => Set.unmodifiable(_invitedTimers.keys);

  /// Keeps the loaded list on screen and surfaces the failure as a toast; a
  /// coin shortfall gets its own state so the screen can show the earn-coins
  /// dialog instead.
  void _emitActionError(FriendsException e) {
    if (e.code == 'insufficient_coins') {
      emit(const FriendsInsufficientCoins());
      load(silent: true);
      return;
    }
    final message = e.message;
    final current = state;
    if (current is FriendsLoaded) {
      // A repeat of the same failure must still be a state change, or the
      // listener never shows its toast a second time.
      if (current.actionError == message) emit(current.copyWith());
      emit(current.copyWith(actionError: message));
    } else {
      emit(FriendsError(message));
    }
  }

  Future<void> sendFriendRequest(String username) async {
    try {
      await _repo.sendFriendRequest(username);
      emit(FriendActionSuccess(friendRequestSentMessage(username)));
      await load(silent: true);
    } on FriendsException catch (e) {
      _emitActionError(e);
    }
  }

  Future<void> respondToRequest(String requesterId, bool accept) async {
    try {
      await _repo.respondToRequest(requesterId, accept);
      await load(silent: true);
    } on FriendsException catch (e) {
      _emitActionError(e);
    }
  }

  Future<void> respondToChallenge(
    String challengeId,
    bool accept,
    String mode, {
    String? opponentName,
  }) async {
    try {
      final roomId = await _repo.respondToChallenge(challengeId, accept);
      if (accept && roomId != null) {
        emit(
          ChallengAccepted(
            roomId: roomId,
            mode: mode,
            opponentName: opponentName,
          ),
        );
      }
      // ChallengAccepted is a one-shot navigation signal; restore the list
      // so the tab isn't blank when the player comes back (e.g. cancels).
      await load(silent: true);
    } on FriendsException catch (e) {
      _emitActionError(e);
    }
  }

  Future<void> removeFriend(String friendId) async {
    try {
      await _repo.removeFriend(friendId);
      _invitedTimers.remove(friendId)?.cancel();
      await load(silent: true);
    } on FriendsException catch (e) {
      _emitActionError(e);
    }
  }

  Future<void> sendChallenge(String friendId, String mode) async {
    try {
      await _repo.sendChallenge(friendId, mode);
      _markInvited(friendId);
      emit(const FriendActionSuccess(challengeSentMessage));
      await load(silent: true);
    } on FriendsException catch (e) {
      _emitActionError(e);
    }
  }

  void _markInvited(String friendId) {
    _invitedTimers[friendId]?.cancel();
    _invitedTimers[friendId] = Timer(
      const Duration(seconds: GameConstants.friendInviteSentSec),
      () {
        _invitedTimers.remove(friendId);
        final current = state;
        if (!isClosed && current is FriendsLoaded) {
          emit(current.copyWith(invited: _invitedNow));
        }
      },
    );
  }

  @override
  Future<void> close() {
    for (final t in _invitedTimers.values) {
      t.cancel();
    }
    _invitedTimers.clear();
    return super.close();
  }
}
