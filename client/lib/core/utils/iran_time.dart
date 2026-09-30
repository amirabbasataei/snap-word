/// Iran Standard Time is a fixed UTC+03:30 (no DST since 2022). The server
/// runs the Daily Challenge day, streak days and prize payouts on it.
const Duration iranOffset = Duration(hours: 3, minutes: 30);

/// Time left until the next Iran midnight (when the challenge day rolls over
/// and prizes are paid).
Duration untilIranMidnight([DateTime? now]) {
  final n = (now ?? DateTime.now()).toUtc().add(iranOffset);
  final next = DateTime.utc(n.year, n.month, n.day + 1);
  return next.difference(n);
}
