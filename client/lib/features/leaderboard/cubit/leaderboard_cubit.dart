import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:wordchain/core/utils/error_messages.dart';
import 'package:wordchain/features/leaderboard/data/leaderboard_repository.dart';

part 'leaderboard_state.dart';

class LeaderboardCubit extends Cubit<LeaderboardState> {
  final LeaderboardRepository _repo;

  LeaderboardCubit({
    required LeaderboardRepository repository,
    required String currentUserId,
  }) : _repo = repository,
       super(LeaderboardState(currentUserId: currentUserId));

  String get currentUserId => state.currentUserId;

  /// Request counter per tab: a slow answer for an older request must not
  /// overwrite a newer one.
  final _seq = <BoardTab, int>{};

  /// Shows [tab] and (re)loads it. A tab that already has a result keeps it on
  /// screen while the fresh one is fetched.
  Future<void> select(BoardTab tab) {
    emit(state.copyWith(tab: tab));
    return _fetch(tab, silent: true);
  }

  /// Reloads the visible tab. [silent] (a bottom-nav tab tap) never swaps the
  /// screen for a spinner, and a failure keeps whatever is already shown.
  Future<void> load({bool silent = false}) => _fetch(state.tab, silent: silent);

  Future<void> _fetch(BoardTab tab, {required bool silent}) async {
    final seq = (_seq[tab] ?? 0) + 1;
    _seq[tab] = seq;
    final hasData = state.boards.containsKey(tab);
    if (!hasData && !silent) {
      emit(
        state.copyWith(
          loading: {...state.loading, tab},
          errors: {...state.errors}..remove(tab),
        ),
      );
    } else if (!hasData && !state.errors.containsKey(tab)) {
      emit(state.copyWith(loading: {...state.loading, tab}));
    }
    try {
      final result = await _fetchTab(tab);
      if (isClosed || _seq[tab] != seq) return;
      emit(
        state.copyWith(
          boards: {...state.boards, tab: result},
          errors: {...state.errors}..remove(tab),
          loading: {...state.loading}..remove(tab),
        ),
      );
    } on LeaderboardException catch (e) {
      _failed(tab, seq, e.message);
    } catch (_) {
      _failed(tab, seq, loadLeaderboardFailedMessage);
    }
  }

  void _failed(BoardTab tab, int seq, String message) {
    if (isClosed || _seq[tab] != seq) return;
    emit(
      state.copyWith(
        loading: {...state.loading}..remove(tab),
        // With a result on screen the failure is swallowed.
        errors:
            state.boards.containsKey(tab)
                ? state.errors
                : {...state.errors, tab: message},
      ),
    );
  }

  Future<LeaderboardResult> _fetchTab(BoardTab tab) => switch (tab) {
    BoardTab.weekly => _repo.fetchGlobal(),
    BoardTab.daily => _repo.fetchDaily(currentUserId),
    BoardTab.allTime => _repo.fetchAllTime(),
    BoardTab.friends => _repo.fetchFriends(currentUserId),
  };
}
