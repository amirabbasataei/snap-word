import 'package:wordchain/core/utils/persian_digits.dart';
import 'package:wordchain/features/game/data/game_constants.dart';

/// What to tell the player after a report went through. A signed-in player
/// earns [GameConstants.wordSuggestionCoins] if the word is approved; a guest
/// is pointed at signing in (guests can report, but only accounts are paid).
String wordSentMessage({required bool signedIn, required bool already}) {
  if (already) return 'همین کلمه را قبلاً فرستاده بودی؛ منتظر بررسی است.';
  return signedIn
      ? 'ممنون! اگر تأیید شود ${toPersianDigits(GameConstants.wordSuggestionCoins)} سکه هدیه می‌گیری.'
      : 'ممنون! برای گرفتن جایزهٔ کلمه‌های تأییدشده، با حساب خودت وارد شو.';
}

/// Short line for a toast after a one-tap report.
String wordSentToast({required bool signedIn, required bool already}) =>
    already
        ? 'قبلاً گزارش داده بودی'
        : signedIn
        ? 'گزارش شد؛ بعد از بررسی خبرت می‌کنیم'
        : 'گزارش شد؛ با ورود به حساب جایزه هم می‌گیری';
