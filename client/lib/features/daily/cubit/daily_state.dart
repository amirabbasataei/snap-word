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

/// Today's challenge has not been attempted yet — show the play screen.
class DailyAvailable extends DailyState {
  final DailyChallenge challenge;

  const DailyAvailable({required this.challenge});

  @override
  List<Object?> get props => [challenge];
}

/// At least one attempt exists — show the result screen. [retrying] is true
/// while the paid retry is being bought (the button is busy, taps are ignored).
class DailyAttempted extends DailyState {
  final DailyChallenge challenge;
  final bool retrying;

  const DailyAttempted({required this.challenge, this.retrying = false});

  @override
  List<Object?> get props => [challenge, retrying];
}

/// [DailyCubit.retry] was blocked by a coin shortfall. Still renders as the
/// result screen; the view listens for it to show the earn-coins dialog.
class DailyInsufficientCoins extends DailyAttempted {
  const DailyInsufficientCoins({required super.challenge});
}

/// [DailyCubit.retry] failed for another reason; the view toasts [message]
/// (already Persian) on the result screen.
class DailyRetryFailed extends DailyAttempted {
  final String message;

  const DailyRetryFailed({required super.challenge, required this.message});

  @override
  List<Object?> get props => [challenge, retrying, message];
}

/// The retry slot is bought — the screen navigates to the game. It still
/// renders as the result screen, so backing out of the game lands on it.
class DailyRetryAvailable extends DailyState {
  final DailyChallenge challenge;

  const DailyRetryAvailable({required this.challenge});

  @override
  List<Object?> get props => [challenge];
}

class DailyError extends DailyState {
  final String code;
  final String message;

  const DailyError(this.code, this.message);

  @override
  List<Object?> get props => [code, message];
}
