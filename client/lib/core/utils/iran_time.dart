import 'package:wordchain/core/utils/persian_digits.dart';

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

/// Time left until the weekly leaderboard resets: Saturday 00:00 Iran time
/// (the end of Friday, the Iranian week — `scheduler` + `RunWeeklyReset`).
/// Exactly on Saturday 00:00 the next reset is a full week away.
Duration untilIranWeekReset([DateTime? now]) {
  final n = (now ?? DateTime.now()).toUtc().add(iranOffset);
  var ahead = (DateTime.saturday - n.weekday) % 7;
  if (ahead == 0) ahead = 7;
  final next = DateTime.utc(n.year, n.month, n.day + ahead);
  return next.difference(n);
}

/// «۳ روز و ۵ ساعت» · «۵ ساعت و ۲۰ دقیقه» · «۲۰ دقیقه» — the two largest
/// non-zero units of [d], rounded down to the minute (at least one minute).
String formatCountdownFa(Duration d) {
  final minutes = d.inMinutes < 1 ? 1 : d.inMinutes;
  final days = minutes ~/ (24 * 60);
  final hours = (minutes % (24 * 60)) ~/ 60;
  final mins = minutes % 60;
  String unit(int n, String word) => '${toPersianDigits(n)} $word';
  if (days > 0) {
    return hours == 0
        ? unit(days, 'روز')
        : '${unit(days, 'روز')} و ${unit(hours, 'ساعت')}';
  }
  if (hours > 0) {
    return mins == 0
        ? unit(hours, 'ساعت')
        : '${unit(hours, 'ساعت')} و ${unit(mins, 'دقیقه')}';
  }
  return unit(mins, 'دقیقه');
}
