import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:wordchain/features/auth/cubit/auth_cubit.dart';
import 'package:wordchain/features/rewards/data/rewards_repository.dart';

class RewardsState {
  final List<RewardItem> items;
  final bool loading;

  const RewardsState({this.items = const [], this.loading = false});

  int get unclaimedCount => items.where((i) => !i.claimed).length;
}

/// App-wide singleton so the home bell badge and the rewards screen share state.
class RewardsCubit extends Cubit<RewardsState> {
  final RewardsRepository _repo;
  final AuthCubit _auth;

  RewardsCubit({required RewardsRepository repo, required AuthCubit auth})
    : _repo = repo,
      _auth = auth,
      super(const RewardsState());

  /// Best-effort: on failure the previous list (and badge) is kept.
  Future<void> refresh() async {
    if (_auth.state is! AuthAuthenticated) {
      emit(const RewardsState());
      return;
    }
    emit(RewardsState(items: state.items, loading: true));
    try {
      final snapshot = await _repo.fetch();
      await _auth.setCoins(snapshot.coins);
      emit(RewardsState(items: snapshot.items));
    } on RewardsException {
      emit(RewardsState(items: state.items));
    }
  }

  /// Claims one reward and credits the coins to the live balance.
  /// Returns the coins awarded; throws [RewardsException] on failure.
  Future<int> claim(String id) async {
    final coins = await _repo.claim(id);
    await _auth.creditCoins(coins);
    emit(
      RewardsState(
        items: [for (final i in state.items) i.id == id ? i.asClaimed() : i],
      ),
    );
    return coins;
  }
}
