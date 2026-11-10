import 'dart:convert';

/// The per-word record of a single-player run that the Daily Challenge
/// uploads (`word_times_ms`, `word_streaks`) so the server can recompute the
/// score with the same formula as [GameBloc.calculateScore] instead of
/// trusting it. One entry per chain word the player typed: how long the turn
/// took and the match streak *before* the word. The server cannot see the
/// mistakes that reset a streak, which is why the streak is stored.
///
/// Stored as JSON in `local_matches.score_trace`, appended in the same
/// transaction as the accepted word, so it survives an interrupted run.
class ScoreTrace {
  final List<int> timesMs;
  final List<int> streaks;

  const ScoreTrace({this.timesMs = const [], this.streaks = const []});

  static const ScoreTrace empty = ScoreTrace();

  /// Parses the stored column; anything malformed reads as [empty] (the run is
  /// then uploaded without a trace and only the server's upper bound applies).
  factory ScoreTrace.parse(String? json) {
    if (json == null || json.isEmpty) return empty;
    try {
      final map = jsonDecode(json) as Map<String, dynamic>;
      final t = (map['t'] as List<dynamic>).cast<int>();
      final s = (map['s'] as List<dynamic>).cast<int>();
      if (t.length != s.length) return empty;
      return ScoreTrace(timesMs: t, streaks: s);
    } catch (_) {
      return empty;
    }
  }

  String toJson() => jsonEncode({'t': timesMs, 's': streaks});

  ScoreTrace add(int ms, int streak) =>
      ScoreTrace(timesMs: [...timesMs, ms], streaks: [...streaks, streak]);

  /// Whether there is exactly one entry per chain word. A run resumed from
  /// before this existed, or one that was resumed mid-way, may not line up;
  /// such a trace must not be uploaded (the server would reject it).
  bool covers(List<String> chain) =>
      chain.isNotEmpty &&
      timesMs.length == chain.length &&
      streaks.length == chain.length;
}
