import 'package:shamsi_date/shamsi_date.dart';
import 'package:wordchain/core/utils/iran_time.dart';
import 'package:wordchain/core/utils/persian_digits.dart';

// Dart's DateTime.weekday: Monday = 1 … Sunday = 7.
const _weekdayNames = [
  'دوشنبه',
  'سه‌شنبه',
  'چهارشنبه',
  'پنجشنبه',
  'جمعه',
  'شنبه',
  'یکشنبه',
];

/// «جمعه ۲۴ مهر» — weekday and Jalali day/month of the challenge day (the
/// server's Iran-time `yyyy-MM-dd`). A missing or unparsable date falls back
/// to today in Iran.
String dailyDateLabel(String? challengeDateIso, [DateTime? now]) {
  DateTime? date;
  if (challengeDateIso != null && challengeDateIso.isNotEmpty) {
    date = DateTime.tryParse(challengeDateIso);
  }
  if (date == null) {
    final iran = (now ?? DateTime.now()).toUtc().add(iranOffset);
    date = DateTime(iran.year, iran.month, iran.day);
  }
  final jalali = Jalali.fromDateTime(date);
  return '${_weekdayNames[date.weekday - 1]} '
      '${toPersianDigits(jalali.day)} ${jalali.formatter.mN}';
}

/// «۱۱:۴۲» — hours and minutes until the next Iran midnight, read once (the
/// screen computes it on build and does not tick).
String dailyClockLabel(Duration left) {
  final minutes = left.inMinutes < 0 ? 0 : left.inMinutes;
  String two(int v) => v.toString().padLeft(2, '0');
  return toPersianDigits('${two(minutes ~/ 60)}:${two(minutes % 60)}');
}
