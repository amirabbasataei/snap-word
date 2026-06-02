part of 'friends_cubit.dart';

abstract class FriendsState extends Equatable {
  const FriendsState();

  @override
  List<Object?> get props => [];
}

class FriendsInitial extends FriendsState {
  const FriendsInitial();
}

class FriendsLoading extends FriendsState {
  const FriendsLoading();
}

class FriendsLoaded extends FriendsState {
  final List<FriendModel> friends;
  final List<PendingRequest> pendingRequests;
  final List<PendingChallenge> pendingChallenges;
  final String? actionError;

  const FriendsLoaded({
    required this.friends,
    required this.pendingRequests,
    required this.pendingChallenges,
    this.actionError,
  });

  @override
  List<Object?> get props =>
      [friends, pendingRequests, pendingChallenges, actionError];
}

class FriendActionSuccess extends FriendsState {
  final String message;

  const FriendActionSuccess(this.message);

  @override
  List<Object?> get props => [message];
}

class ChallengAccepted extends FriendsState {
  final String roomId;
  final String mode;

  const ChallengAccepted({required this.roomId, required this.mode});

  @override
  List<Object?> get props => [roomId, mode];
}

class FriendsError extends FriendsState {
  final String message;

  const FriendsError(this.message);

  @override
  List<Object?> get props => [message];
}
