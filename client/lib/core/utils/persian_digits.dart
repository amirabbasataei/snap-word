/// Renders every number in every screen with Persian digits (۰۱۲…) and the
/// Arabic thousands separator «٬», per the design token sheet. This is the
/// one formatter — never interpolate a raw `int`/`double` into UI text.
library;

const _persianDigits = ['۰', '۱', '۲', '۳', '۴', '۵', '۶', '۷', '۸', '۹'];
const _thousandsSeparator = '٬';

/// Converts every ASCII digit in [input] to its Persian equivalent.
/// Non-digit characters (signs, separators, ٫ decimal points) pass through.
String toPersianDigits(Object input) {
  final source = input.toString();
  final buffer = StringBuffer();
  for (final rune in source.runes) {
    if (rune >= 0x30 && rune <= 0x39) {
      buffer.write(_persianDigits[rune - 0x30]);
    } else {
      buffer.writeCharCode(rune);
    }
  }
  return buffer.toString();
}

/// Formats an integer with «٬» thousands separators, then converts to
/// Persian digits — e.g. `1240` → `۱٬۲۴۰`.
String formatPersianNumber(int value) {
  final negative = value < 0;
  final digits = value.abs().toString();
  final groups = <String>[];
  for (var i = digits.length; i > 0; i -= 3) {
    groups.insert(0, digits.substring(i - 3 < 0 ? 0 : i - 3, i));
  }
  final grouped = groups.join(_thousandsSeparator);
  return toPersianDigits(negative ? '-$grouped' : grouped);
}
