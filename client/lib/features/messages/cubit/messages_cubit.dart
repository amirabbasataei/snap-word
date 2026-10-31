import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:wordchain/core/utils/error_messages.dart';
import 'package:wordchain/features/auth/cubit/auth_cubit.dart';
import 'package:wordchain/features/friends/data/friends_repository.dart';
import 'package:wordchain/features/messages/data/inbox_repository.dart';

/// A push that arrived during a game and was held back so no banner covers
/// the board; it waits on the messages screen until dismissed.
class MissedPush {
  final String title;
  final String body;

  const MissedPush({required this.title, required this.body});
}

class MessagesState {
  final List<PendingRequest> requests;
  final List<PendingChallenge> challenges;
  final List<MissedPush> missed;

  /// Unread messages an admin sent from the panel.
  final List<InboxMessage> announcements;
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
    this.missed = const [],
    this.announcements = const [],
    this.loading = false,
    this.loaded = false,
    this.error,
  });

  int get count =>
      requests.length +
      challenges.length +
      missed.length +
      announcements.length;

  /// Copy with some lists replaced. [loading] and [error] describe one
  /// refresh, so they are never carried over: a copy is idle and error-free
  /// unless told otherwise.
  MessagesState copyWith({
    List<PendingRequest>? requests,
    List<PendingChallenge>? challenges,
    List<MissedPush>? missed,
    List<InboxMessage>? announcements,
    bool? loading,
    bool? loaded,
    String? error,
  }) => MessagesState(
    requests: requests ?? this.requests,
    challenges: challenges ?? this.challenges,
    missed: missed ?? this.missed,
    announcements: announcements ?? this.announcements,
    loading: loading ?? false,
    loaded: loaded ?? this.loaded,
    error: error,
  );
}

/// App-wide singleton so the home inbox badge and the messages screen share state.
/// Messages are actionable invitations (friend requests and friend challenges)
/// plus the notices an admin sent from the panel.
class MessagesCubit extends Cubit<MessagesState> {
  final FriendsRepository _repo;
  final InboxRepository? _inbox;
  final AuthCubit _auth;
  final _friendsChanged = StreamController<void>.broadcast();

  /// Fires after a response here changes friends data, so the (kept-alive)
  /// Friends tab can reload instead of showing stale rows.
  Stream<void> get friendsChanged => _friendsChanged.stream;

  MessagesCubit({
    required FriendsRepository repo,
    required AuthCubit auth,
    InboxRepository? inbox,
  }) : _repo = repo,
       _inbox = inbox,
       _auth = auth,
       super(const MessagesState());

  /// Best-effort: on failure the previous list (and badge) is kept.
  Future<void> refresh() async {
    if (_auth.state is! AuthAuthenticated) {
      emit(const MessagesState(loaded: true));
      return;
    }
    emit(state.copyWith(loading: true));
    try {
      final results = await Future.wait([
        _repo.fetchPendingRequests(),
        _repo.fetchPendingChallenges(),
        _fetchAnnouncements(),
      ]);
      emit(
        state.copyWith(
          requests: results[0] as List<PendingRequest>,
          challenges: results[1] as List<PendingChallenge>,
          announcements: results[2] as List<InboxMessage>,
          loaded: true,
        ),
      );
    } on FriendsException catch (e) {
      emit(state.copyWith(error: errorMessageFor(e.code)));
    }
  }

  /// A failing notice list must not hide the invitations, so it falls back to
  /// what was already loaded.
  Future<List<InboxMessage>> _fetchAnnouncements() async {
    final inbox = _inbox;
    if (inbox == null) return state.announcements;
    try {
      return await inbox.fetchUnread();
    } on InboxException {
      return state.announcements;
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
      state.copyWith(requests: requests, challenges: challenges, loaded: true),
    );
  }

  /// Keeps a push that arrived mid-game so the bell badge counts it and the
  /// messages screen can show it. Invitation pushes also reload the real
  /// lists. Session-only: it is not stored anywhere.
  void addMissed(String title, String body) {
    if (_auth.state is! AuthAuthenticated) return;
    emit(
      state.copyWith(
        missed: [...state.missed, MissedPush(title: title, body: body)],
      ),
    );
    refresh();
  }

  void dismissMissed(MissedPush push) {
    emit(
      state.copyWith(
        missed: [
          for (final m in state.missed)
            if (!identical(m, push)) m,
        ],
      ),
    );
  }

  /// Hides an admin notice at once and tells the server it was read; if that
  /// call fails the notice simply comes back on the next refresh.
  Future<void> dismissAnnouncement(InboxMessage message) async {
    emit(
      state.copyWith(
        announcements: [
          for (final m in state.announcements)
            if (m.id != message.id) m,
        ],
      ),
    );
    try {
      await _inbox?.markRead(message.id);
    } on InboxException {
      // Best-effort; see above.
    }
  }

  Future<void> respondToRequest(String requesterId, bool accept) async {
    await _repo.respondToRequest(requesterId, accept);
    _friendsChanged.add(null);
    emit(
      state.copyWith(
        requests: [
          for (final r in state.requests)
            if (r.requesterId != requesterId) r,
        ],
        loaded: true,
      ),
    );
  }

  /// Returns the room id when an accepted challenge opens a match.
  Future<String?> respondToChallenge(String id, bool accept) async {
    final roomId = await _repo.respondToChallenge(id, accept);
    _friendsChanged.add(null);
    emit(
      state.copyWith(
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
