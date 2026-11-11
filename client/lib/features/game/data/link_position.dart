import 'package:wordchain/core/utils/persian_digits.dart';

/// Copy for the letter position that links words (Daily variants: the next
/// word's 2nd or 3rd letter must be the previous word's last letter).

/// «اول» / «دوم» / «سوم».
String linkOrdinal(int position) => switch (position) {
  1 => 'اول',
  2 => 'دوم',
  3 => 'سوم',
  _ => toPersianDigits(position),
};

/// What the next word must have: «با «ن»» for the classic link, «حرف دومش
/// «ن»» for a harder variant.
String linkCue(String letter, int position) =>
    position <= 1 ? 'با «$letter»' : 'حرف ${linkOrdinal(position)}ش «$letter»';

/// The variant's name: «حرف اول» / «حرف دوم» / «حرف سوم».
String linkVariantName(int position) => 'حرف ${linkOrdinal(position)}';
