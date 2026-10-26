import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:wordchain/core/utils/error_messages.dart';
import 'package:wordchain/features/auth/cubit/auth_cubit.dart';
import 'package:wordchain/features/friends/data/friends_repository.dart';

class MessagesState {
  final List<PendingRequest> requests;
  final List<PendingChallenge> challenges;
  final bool loading;

  /// A list (even an empty one) has been received at least once, or there is
  /// nothing to receive (guest, or the Friends tab handed over its own load).
  /// Before that the screen shows its loading / failed-load block instead of
  /// the empty state.
  final bool loaded;

  /// Persian message of the last failed [MessagesCubit.refresh]; the screen
  /// only shows it while nothing has loaded yet.
  final String? error;

  const MessagesState({
    this.requests = const [],
    this.challenges = const [],
    this.loading = false,
    this.loaded = false,
    this.error,
  });

  int get count => requests.length + challenges.length;
}

/// App-wide singleton so the home inbox badge and the messages screen share state.
/// Messages are actionable invitations: friend requests and friend challenges.
class MessagesCubit extends Cubit<MessagesState> {
  final FriendsRepository _repo;
  final AuthCubit _auth;
  final _friendsChanged = StreamController<void>.broadcast();

  /// Fires after a response here changes friends data, so the (kept-alive)
  /// Friends tab can reload instead of showing stale rows.
  Stream<void> get friendsChanged => _friendsChanged.stream;

  MessagesCubit({required FriendsRepository repo, required AuthCubit auth})
    : _repo = repo,
      _auth = auth,
      super(const MessagesState());

  /// Best-effort: on failure the previous list (and badge) is kept.
  Future<void> refresh() async {
    if (_auth.state is! AuthAuthenticated) {
      emit(const MessagesState(loaded: true));
      return;
    }
    emit(
      MessagesState(
        requests: state.requests,
        challenges: state.challenges,
        loading: true,
        loaded: state.loaded,
      ),
    );
    try {
      final results = await Future.wait([
        _repo.fetchPendingRequests(),
        _repo.fetchPendingChallenges(),
      ]);
      emit(
        MessagesState(
          requests: results[0] as List<PendingRequest>,
          challenges: results[1] as List<PendingChallenge>,
          loaded: true,
        ),
      );
    } on FriendsException catch (e) {
      emit(
        MessagesState(
          requests: state.requests,
          challenges: state.challenges,
          loaded: state.loaded,
          error: errorMessageFor(e.code),
        ),
      );
    }
  }

  /// Lets the Friends screen share what it just loaded so the home badge stays
  /// in step without another round trip.
  void setPending(
    List<PendingRequest> requests,
    List<PendingChallenge> challenges,
  ) {
    if (_auth.state is! AuthAuthenticated) return;
    emit(
      MessagesState(requests: requests, challenges: challenges, loaded: true),
    );
  }

  Future<void> respondToRequest(String requesterId, bool accept) async {
    await _repo.respondToRequest(requesterId, accept);
    _friendsChanged.add(null);
    emit(
      MessagesState(
        requests: [
          for (final r in state.requests)
            if (r.requesterId != requesterId) r,
        ],
        challenges: state.challenges,
        loaded: true,
      ),
    );
  }

  /// Returns the room id when an accepted challenge opens a match.
  Future<String?> respondToChallenge(String id, bool accept) async {
    final roomId = await _repo.respondToChallenge(id, accept);
    _friendsChanged.add(null);
    emit(
      MessagesState(
        requests: state.requests,
        challenges: [
          for (final c in state.challenges)
            if (c.id != id) c,
        ],
        loaded: true,
      ),
    );
    return accept ? roomId : null;
  }

  @override
  Future<void> close() {
    _friendsChanged.close();
    return super.close();
  }
}
