import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:wordchain/core/theme/app_tokens.dart';
import 'package:wordchain/core/theme/app_typography.dart';
import 'package:wordchain/core/utils/persian_digits.dart';

/// Iran mobile numbers always start with this; the field shows it as a fixed
/// prefix, so the user only types the remaining [_localLength] digits.
const _prefix = '09';
const _localLength = 9;

/// Strips everything but digits from [input], converting Persian (۰-۹) and
/// Arabic-Indic (٠-٩) digits to ASCII.
String extractPhoneDigits(String input) {
  final buffer = StringBuffer();
  for (final rune in input.runes) {
    if (rune >= 0x30 && rune <= 0x39) {
      buffer.writeCharCode(rune);
    } else if (rune >= 0x6F0 && rune <= 0x6F9) {
      buffer.writeCharCode(0x30 + (rune - 0x6F0));
    } else if (rune >= 0x660 && rune <= 0x669) {
      buffer.writeCharCode(0x30 + (rune - 0x660));
    }
  }
  return buffer.toString();
}

/// The digits after the fixed prefix, capped at [_localLength]. A pasted full
/// number ("09123456789") has its own leading 09 dropped; typing is never
/// stripped, because a local part can legitimately start with 09 (0909…).
String _localDigits(String input, {required bool pasted}) {
  var d = extractPhoneDigits(input);
  if (pasted && d.length > _localLength && d.startsWith(_prefix)) {
    d = d.substring(_prefix.length);
  }
  return d.length > _localLength ? d.substring(0, _localLength) : d;
}

String _groupAndPersianize(String digits) {
  final groups = <String>[];
  if (digits.isNotEmpty) {
    groups.add(digits.substring(0, digits.length.clamp(0, 2)));
  }
  if (digits.length > 2) {
    groups.add(digits.substring(2, digits.length.clamp(2, 5)));
  }
  if (digits.length > 5) {
    groups.add(digits.substring(5, digits.length.clamp(5, 9)));
  }
  return toPersianDigits(groups.join(' '));
}

class _PhoneGroupingFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final pasted = newValue.text.length - oldValue.text.length > 1;
    final display = _groupAndPersianize(
      _localDigits(newValue.text, pasted: pasted),
    );
    return TextEditingValue(
      text: display,
      selection: TextSelection.collapsed(offset: display.length),
    );
  }
}

/// Matches ZPhone.dc.html's "شمارهٔ موبایل" field: a 2px-bordered box showing
/// a fixed ۰۹ prefix at the left followed by the remaining digits grouped
/// and in Persian digits (LTR). Reports the full normalized ASCII number
/// (09 + typed digits) via [onDigitsChanged] — the network layer never sees
/// the display string.
class PhoneInputField extends StatefulWidget {
  final ValueChanged<String> onDigitsChanged;

  const PhoneInputField({super.key, required this.onDigitsChanged});

  @override
  State<PhoneInputField> createState() => _PhoneInputFieldState();
}

class _PhoneInputFieldState extends State<PhoneInputField> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  TextStyle _style(ZColors z) => ZTypography.cardTitle.copyWith(
    color: z.ink,
    fontSize: 21,
    fontWeight: FontWeight.w800,
    letterSpacing: 1,
    height: 1.0,
    leadingDistribution: TextLeadingDistribution.even,
  );

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    return Container(
      height: 58,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: z.paper,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: z.ink, width: 2),
      ),
      // LTR so the prefix sits at the left, directly before the typed digits.
      child: Row(
        textDirection: TextDirection.ltr,
        children: [
          Text(toPersianDigits(_prefix), style: _style(z)),
          Expanded(
            child: Directionality(
              textDirection: TextDirection.ltr,
              child: TextField(
                controller: _controller,
                focusNode: _focusNode,
                keyboardType: TextInputType.phone,
                textDirection: TextDirection.ltr,
                inputFormatters: [_PhoneGroupingFormatter()],
                style: _style(z),
                textAlignVertical: TextAlignVertical.center,
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: EdgeInsets.zero,
                ),
                onChanged:
                    (_) => widget.onDigitsChanged(
                      '$_prefix${extractPhoneDigits(_controller.text)}',
                    ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
