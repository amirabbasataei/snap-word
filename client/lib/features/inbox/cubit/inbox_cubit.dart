import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:wordchain/features/auth/cubit/auth_cubit.dart';
import 'package:wordchain/features/inbox/data/inbox_repository.dart';

class InboxState {
  final List<InboxItem> items;
  final bool loading;

  const InboxState({this.items = const [], this.loading = false});

  int get unclaimedCount => items.where((i) => !i.claimed).length;
}

/// App-wide singleton so the home bell badge and the inbox screen share state.
class InboxCubit extends Cubit<InboxState> {
  final InboxRepository _repo;
  final AuthCubit _auth;

  InboxCubit({required InboxRepository repo, required AuthCubit auth})
      : _repo = repo,
        _auth = auth,
        super(const InboxState());

  /// Best-effort: on failure the previous list (and badge) is kept.
  Future<void> refresh() async {
    if (_auth.state is! AuthAuthenticated) {
      emit(const InboxState());
      return;
    }
    emit(InboxState(items: state.items, loading: true));
    try {
      final snapshot = await _repo.fetch();
      await _auth.setCoins(snapshot.coins);
      emit(InboxState(items: snapshot.items));
    } on InboxException {
      emit(InboxState(items: state.items));
    }
  }

  /// Claims one reward and credits the coins to the live balance.
  /// Returns the coins awarded; throws [InboxException] on failure.
  Future<int> claim(String id) async {
    final coins = await _repo.claim(id);
    await _auth.creditCoins(coins);
    emit(InboxState(
      items: [for (final i in state.items) i.id == id ? i.asClaimed() : i],
    ));
    return coins;
  }
}
