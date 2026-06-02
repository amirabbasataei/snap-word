part of 'daily_cubit.dart';

abstract class DailyState extends Equatable {
  const DailyState();

  @override
  List<Object?> get props => [];
}

class DailyInitial extends DailyState {
  const DailyInitial();
}

class DailyLoading extends DailyState {
  const DailyLoading();
}

/// Today's challenge has not been attempted yet — show play screen.
class DailyAvailable extends DailyState {
  final DailyChallenge challenge;

  const DailyAvailable({required this.challenge});

  @override
  List<Object?> get props => [challenge];
}

/// At least one attempt exists — show result screen.
class DailyAttempted extends DailyState {
  final DailyChallenge challenge;

  const DailyAttempted({required this.challenge});

  @override
  List<Object?> get props => [challenge];
}

/// [retry()] succeeded — retry slot purchased; screen navigates to game.
class DailyRetryAvailable extends DailyState {
  final DailyChallenge challenge;

  const DailyRetryAvailable({required this.challenge});

  @override
  List<Object?> get props => [challenge];
}

class DailyError extends DailyState {
  final String message;

  const DailyError(this.message);

  @override
  List<Object?> get props => [message];
}
