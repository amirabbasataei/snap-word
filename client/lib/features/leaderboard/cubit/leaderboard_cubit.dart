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

  bool _hasLoaded = false;

  /// [silent] reloads in the background: no spinner, and a failure keeps
  /// whatever is already on screen.
  Future<void> load({bool silent = false}) async {
    final quiet = silent && _hasLoaded;
    if (!quiet) emit(const LeaderboardLoading());
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
      _hasLoaded = true;
    } on LeaderboardException catch (e) {
      if (!quiet) emit(LeaderboardError(e.message));
    } catch (_) {
      if (!quiet) emit(const LeaderboardError('Failed to load leaderboard'));
    }
  }

  Future<void> refresh() => load();
}
