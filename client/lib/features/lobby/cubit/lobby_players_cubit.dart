import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:wordchain/core/utils/error_messages.dart';
import 'package:wordchain/features/friends/data/friends_repository.dart';
import 'package:wordchain/features/profile/data/profile_repository.dart';

enum LobbyFriendsStatus { loading, loaded, error }

/// How an invite attempt ended; the screen turns it into a toast or dialog.
sealed class LobbyInviteResult {
  const LobbyInviteResult();
}

class LobbyInviteSent extends LobbyInviteResult {
  const LobbyInviteSent();
}

class LobbyInviteNeedsCoins extends LobbyInviteResult {
  const LobbyInviteNeedsCoins();
}

class LobbyInviteFailed extends LobbyInviteResult {
  final String message;
  const LobbyInviteFailed(this.message);
}

class LobbyPlayersState extends Equatable {
  /// The player's own level and premium avatar — best effort, null until
  /// (and unless) the stats / perks calls succeed.
  final int? level;
  final String? avatarId;

  final LobbyFriendsStatus status;
  final List<FriendModel> friends;
  final String? error;

  /// Friends invited from this screen (the server has no "withdraw" call and
  /// no "my sent invites" list, so this is the only record of them) and the
  /// ones whose request is still in flight.
  final Set<String> invited;
  final Set<String> inviting;

  const LobbyPlayersState({
    this.level,
    this.avatarId,
    this.status = LobbyFriendsStatus.loading,
    this.friends = const [],
    this.error,
    this.invited = const {},
    this.inviting = const {},
  });

  LobbyPlayersState copyWith({
    int? level,
    String? avatarId,
    LobbyFriendsStatus? status,
    List<FriendModel>? friends,
    String? error,
    bool clearError = false,
    Set<String>? invited,
    Set<String>? inviting,
  }) => LobbyPlayersState(
    level: level ?? this.level,
    avatarId: avatarId ?? this.avatarId,
    status: status ?? this.status,
    friends: friends ?? this.friends,
    error: clearError ? null : (error ?? this.error),
    invited: invited ?? this.invited,
    inviting: inviting ?? this.inviting,
  );

  @override
  List<Object?> get props => [
    level,
    avatarId,
    status,
    friends.map((f) => f.userId).toList(),
    error,
    invited,
    inviting,
  ];
}

/// Everything the lobby shows besides the queue itself: the player's own
/// level/avatar, the friends list and the invite buttons.
class LobbyPlayersCubit extends Cubit<LobbyPlayersState> {
  final FriendsRepository _friends;
  final ProfileRepository _profile;

  LobbyPlayersCubit({
    required FriendsRepository friends,
    required ProfileRepository profile,
  }) : _friends = friends,
       _profile = profile,
       super(const LobbyPlayersState());

  Future<void> load() async {
    emit(
      state.copyWith(
        status: LobbyFriendsStatus.loading,
        friends: state.friends,
      ),
    );
    await Future.wait([_loadFriends(), _loadMe()]);
  }

  Future<void> _loadFriends() async {
    try {
      final friends = await _friends.fetchFriends();
      if (isClosed) return;
      emit(
        state.copyWith(
          status: LobbyFriendsStatus.loaded,
          friends: friends,
          clearError: true,
        ),
      );
    } on FriendsException catch (e) {
      if (isClosed) return;
      emit(state.copyWith(status: LobbyFriendsStatus.error, error: e.message));
    } catch (_) {
      if (isClosed) return;
      emit(
        state.copyWith(
          status: LobbyFriendsStatus.error,
          error: loadFriendsFailedMessage,
        ),
      );
    }
  }

  Future<void> _loadMe() async {
    int? level;
    String? avatarId;
    try {
      level = (await _profile.fetchStats()).level;
    } catch (_) {
      // Cosmetic — the name tag just has no level line.
    }
    try {
      avatarId = (await _profile.fetchPerks()).avatarId;
    } catch (_) {
      // Cosmetic — the disc keeps the initial.
    }
    if (isClosed) return;
    emit(state.copyWith(level: level, avatarId: avatarId));
  }

  /// Sends a Classic challenge. A friend who was already invited from this
  /// screen is not invited twice (the server would create a second pending
  /// challenge and push).
  Future<LobbyInviteResult> invite(FriendModel friend) async {
    final id = friend.userId;
    if (state.invited.contains(id) || state.inviting.contains(id)) {
      return const LobbyInviteSent();
    }
    emit(state.copyWith(inviting: {...state.inviting, id}));
    try {
      await _friends.sendChallenge(id, 'classic');
      if (!isClosed) {
        emit(
          state.copyWith(
            invited: {...state.invited, id},
            inviting: {...state.inviting}..remove(id),
          ),
        );
      }
      return const LobbyInviteSent();
    } on FriendsException catch (e) {
      _stopInviting(id);
      if (e.code == 'insufficient_coins') return const LobbyInviteNeedsCoins();
      return LobbyInviteFailed(e.message);
    } catch (_) {
      _stopInviting(id);
      return const LobbyInviteFailed(networkErrorMessage);
    }
  }

  void _stopInviting(String id) {
    if (isClosed) return;
    emit(state.copyWith(inviting: {...state.inviting}..remove(id)));
  }
}
