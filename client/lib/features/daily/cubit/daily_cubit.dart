import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:wordchain/features/daily/data/daily_repository.dart';

part 'daily_state.dart';

class DailyCubit extends Cubit<DailyState> {
  final DailyRepository _repo;

  DailyCubit({required DailyRepository repository})
      : _repo = repository,
        super(const DailyInitial());

  Future<void> load() async {
    emit(const DailyLoading());
    try {
      final challenge = await _repo.getDailyChallenge();
      if (challenge.hasAttempted) {
        emit(DailyAttempted(challenge: challenge));
      } else {
        emit(DailyAvailable(challenge: challenge));
      }
    } on DailyException catch (e) {
      emit(DailyError(e.message));
    } catch (_) {
      emit(const DailyError('Failed to load daily challenge'));
    }
  }

  Future<void> retry() async {
    if (state is! DailyAttempted) return;
    final challenge = (state as DailyAttempted).challenge;
    emit(const DailyLoading());
    try {
      await _repo.retryChallenge();
      emit(DailyRetryAvailable(challenge: challenge));
    } on DailyException catch (e) {
      emit(DailyError(e.message));
    } catch (_) {
      emit(const DailyError('Could not start retry'));
    }
  }
}
