import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:wordchain/core/utils/error_messages.dart';
import 'package:wordchain/core/utils/iran_time.dart';
import 'package:wordchain/features/daily/data/daily_repository.dart';

part 'daily_state.dart';

class DailyCubit extends Cubit<DailyState> {
  final DailyRepository _repo;

  DailyCubit({required DailyRepository repository})
    : _repo = repository,
      super(const DailyInitial());

  /// Loads today's challenge. [silent] keeps the screen that is already up
  /// (no spinner) and swallows a failure — used when the app comes back to the
  /// foreground.
  Future<void> load({bool silent = false}) async {
    final keep = silent && (state is DailyAvailable || state is DailyAttempted);
    if (!keep) emit(const DailyLoading());
    try {
      final challenge = await _repo.getDailyChallenge();
      if (isClosed) return;
      emit(
        challenge.hasAttempted
            ? DailyAttempted(challenge: challenge)
            : DailyAvailable(challenge: challenge),
      );
    } on DailyException catch (e) {
      if (!keep && !isClosed) emit(DailyError(e.code, e.message));
    } catch (_) {
      if (!keep && !isClosed) {
        emit(const DailyError(unknownErrorCode, loadDailyFailedMessage));
      }
    }
  }

  /// The challenge on screen belongs to an earlier Iran day (the app sat in
  /// the background across midnight): reload it quietly.
  Future<void> refreshIfStale([DateTime? now]) {
    final current = switch (state) {
      DailyAvailable(:final challenge) => challenge,
      DailyAttempted(:final challenge) => challenge,
      _ => null,
    };
    if (current == null ||
        (state is DailyAttempted && (state as DailyAttempted).retrying) ||
        current.challengeDate == iranDateString(now)) {
      return Future.value();
    }
    return load(silent: true);
  }

  /// Buys the paid second attempt (25 coins) and, on success, tells the screen
  /// to start the game. Failures leave the result screen up: a coin shortfall
  /// emits [DailyInsufficientCoins], anything else [DailyRetryFailed] (both are
  /// one-shot — the cubit goes straight back to [DailyAttempted]).
  Future<void> retry() async {
    final current = state;
    if (current is! DailyAttempted || current.retrying) return;
    final challenge = current.challenge;
    emit(DailyAttempted(challenge: challenge, retrying: true));
    try {
      await _repo.retryChallenge();
      if (isClosed) return;
      emit(DailyRetryAvailable(challenge: challenge));
    } on DailyException catch (e) {
      if (isClosed) return;
      switch (e.code) {
        case 'insufficient_coins':
          emit(DailyInsufficientCoins(challenge: challenge));
        case 'already_retried':
          // The slot was bought earlier and never played (the app was closed
          // between paying and the game): the server will accept the attempt
          // without charging again, so go on to the game.
          emit(DailyRetryAvailable(challenge: challenge));
          return;
        default:
          emit(DailyRetryFailed(challenge: challenge, message: e.message));
      }
      // Reset so a second tap re-emits (equal states are dropped).
      emit(DailyAttempted(challenge: challenge));
    } catch (_) {
      if (isClosed) return;
      emit(
        DailyRetryFailed(
          challenge: challenge,
          message: dailyRetryFailedMessage,
        ),
      );
      emit(DailyAttempted(challenge: challenge));
    }
  }
}
