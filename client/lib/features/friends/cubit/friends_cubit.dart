import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:wordchain/features/friends/data/friends_repository.dart';

part 'friends_state.dart';

class FriendsCubit extends Cubit<FriendsState> {
  final FriendsRepository _repo;

  FriendsCubit({required FriendsRepository repository})
      : _repo = repository,
        super(const FriendsInitial());

  bool _hasLoaded = false;

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
      final challenges = rawChallenges.map((c) {
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

      emit(FriendsLoaded(
        friends: friends,
        pendingRequests: requests,
        pendingChallenges: challenges,
      ));
      _hasLoaded = true;
    } on FriendsException catch (e) {
      if (!quiet) emit(FriendsError(e.message));
    } catch (_) {
      if (!quiet) emit(const FriendsError('Failed to load friends'));
    }
  }

  Future<void> sendFriendRequest(String username) async {
    try {
      await _repo.sendFriendRequest(username);
      emit(FriendActionSuccess('Friend request sent to $username'));
      await load();
    } on FriendsException catch (e) {
      final current = state;
      if (current is FriendsLoaded) {
        emit(FriendsLoaded(
          friends: current.friends,
          pendingRequests: current.pendingRequests,
          pendingChallenges: current.pendingChallenges,
          actionError: e.message,
        ));
      } else {
        emit(FriendsError(e.message));
      }
    }
  }

  Future<void> respondToRequest(String requesterId, bool accept) async {
    try {
      await _repo.respondToRequest(requesterId, accept);
      await load();
    } on FriendsException catch (e) {
      emit(FriendsError(e.message));
    }
  }

  Future<void> respondToChallenge(
    String challengeId,
    bool accept,
    String mode,
  ) async {
    try {
      final roomId = await _repo.respondToChallenge(challengeId, accept);
      if (accept && roomId != null) {
        emit(ChallengAccepted(roomId: roomId, mode: mode));
      } else {
        await load();
      }
    } on FriendsException catch (e) {
      emit(FriendsError(e.message));
    }
  }

  // The challenger has no other channel for the room id (push isn't wired),
  // so poll until the friend accepts, then enter the same room.
  Future<void> _joinRoomOnAccept(String challengeId, String mode) async {
    final roomId = await _repo.waitForChallengeRoom(
      challengeId,
      isCancelled: () => isClosed,
    );
    if (roomId != null && !isClosed) {
      emit(ChallengAccepted(roomId: roomId, mode: mode));
    }
  }

  Future<void> removeFriend(String friendId) async {
    try {
      await _repo.removeFriend(friendId);
      await load();
    } on FriendsException catch (e) {
      emit(FriendsError(e.message));
    }
  }

  Future<void> sendChallenge(String friendId, String mode) async {
    try {
      final challengeId = await _repo.sendChallenge(friendId, mode);
      emit(const FriendActionSuccess('Challenge sent!'));
      // Reload to get fresh state
      await load();
      if (challengeId != null) _joinRoomOnAccept(challengeId, mode);
    } on FriendsException catch (e) {
      final current = state;
      if (current is FriendsLoaded) {
        emit(FriendsLoaded(
          friends: current.friends,
          pendingRequests: current.pendingRequests,
          pendingChallenges: current.pendingChallenges,
          actionError: e.message,
        ));
      } else {
        emit(FriendsError(e.message));
      }
    }
  }
}
