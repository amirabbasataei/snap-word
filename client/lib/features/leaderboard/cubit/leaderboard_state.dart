part of 'leaderboard_cubit.dart';

/// The board's tabs, in canvas order (this week · today · all time · friends).
enum BoardTab { weekly, daily, allTime, friends }

/// What the board shows. Tabs load on their own: [boards] holds every result
/// fetched so far, [errors] the tabs whose first load failed (nothing to keep
/// on screen), [loading] the tabs waiting on their first result.
class LeaderboardState extends Equatable {
  final BoardTab tab;
  final Map<BoardTab, LeaderboardResult> boards;
  final Map<BoardTab, String> errors;
  final Set<BoardTab> loading;
  final String currentUserId;

  const LeaderboardState({
    required this.currentUserId,
    this.tab = BoardTab.weekly,
    this.boards = const {},
    this.errors = const {},
    this.loading = const {},
  });

  LeaderboardResult? get current => boards[tab];

  /// The player's premium avatar, from whichever board reported it (the daily
  /// board does not).
  String? get selfAvatarId {
    for (final b in boards.values) {
      if (b.playerAvatarId != null) return b.playerAvatarId;
    }
    return null;
  }

  LeaderboardState copyWith({
    BoardTab? tab,
    Map<BoardTab, LeaderboardResult>? boards,
    Map<BoardTab, String>? errors,
    Set<BoardTab>? loading,
  }) => LeaderboardState(
    currentUserId: currentUserId,
    tab: tab ?? this.tab,
    boards: boards ?? this.boards,
    errors: errors ?? this.errors,
    loading: loading ?? this.loading,
  );

  @override
  List<Object?> get props => [tab, boards, errors, loading, currentUserId];
}
