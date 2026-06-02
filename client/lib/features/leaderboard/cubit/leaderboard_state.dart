part of 'leaderboard_cubit.dart';

abstract class LeaderboardState extends Equatable {
  const LeaderboardState();

  @override
  List<Object?> get props => [];
}

class LeaderboardInitial extends LeaderboardState {
  const LeaderboardInitial();
}

class LeaderboardLoading extends LeaderboardState {
  const LeaderboardLoading();
}

class LeaderboardLoaded extends LeaderboardState {
  final LeaderboardResult global;
  final LeaderboardResult friends;
  final String currentUserId;

  const LeaderboardLoaded({
    required this.global,
    required this.friends,
    required this.currentUserId,
  });

  @override
  List<Object?> get props => [global, friends, currentUserId];
}

class LeaderboardError extends LeaderboardState {
  final String message;

  const LeaderboardError(this.message);

  @override
  List<Object?> get props => [message];
}
