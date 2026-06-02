import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:wordchain/features/leaderboard/data/leaderboard_repository.dart';

part 'leaderboard_state.dart';

class LeaderboardCubit extends Cubit<LeaderboardState> {
  final LeaderboardRepository _repo;
  final String currentUserId;

  LeaderboardCubit({
    required LeaderboardRepository repository,
    required this.currentUserId,
  })  : _repo = repository,
        super(const LeaderboardInitial());

  Future<void> load() async {
    emit(const LeaderboardLoading());
    try {
      final results = await Future.wait([
        _repo.fetchGlobal(),
        _repo.fetchFriends(),
      ]);
      emit(LeaderboardLoaded(
        global: results[0],
        friends: results[1],
        currentUserId: currentUserId,
      ));
    } on LeaderboardException catch (e) {
      emit(LeaderboardError(e.message));
    } catch (_) {
      emit(const LeaderboardError('Failed to load leaderboard'));
    }
  }

  Future<void> refresh() => load();
}
