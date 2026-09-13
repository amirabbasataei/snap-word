import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:wordchain/core/theme/app_tokens.dart';
import 'package:wordchain/core/theme/app_typography.dart';
import 'package:wordchain/core/utils/persian_digits.dart';

/// Strips everything but digits from [input], converting Persian (۰-۹) and
/// Arabic-Indic (٠-٩) digits to ASCII, and caps the result at 11 digits
/// (the length of a normalized 09XXXXXXXXX Iran mobile number).
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
  final s = buffer.toString();
  return s.length > 11 ? s.substring(0, 11) : s;
}

String _groupAndPersianize(String digits) {
  final groups = <String>[];
  if (digits.isNotEmpty) groups.add(digits.substring(0, digits.length.clamp(0, 4)));
  if (digits.length > 4) groups.add(digits.substring(4, digits.length.clamp(4, 7)));
  if (digits.length > 7) groups.add(digits.substring(7, digits.length.clamp(7, 11)));
  return toPersianDigits(groups.join(' '));
}

class _PhoneGroupingFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final digits = extractPhoneDigits(newValue.text);
    final display = _groupAndPersianize(digits);
    return TextEditingValue(
      text: display,
      selection: TextSelection.collapsed(offset: display.length),
    );
  }
}

/// Matches ZPhone.dc.html's "شمارهٔ موبایل" field: a 2px-bordered box showing
/// the phone number grouped and in Persian digits (LTR), with a coral
/// cursor-bar cue while focused. Reports the normalized ASCII digit string
/// via [onDigitsChanged] — the network layer never sees the display string.
class PhoneInputField extends StatefulWidget {
  final ValueChanged<String> onDigitsChanged;

  const PhoneInputField({super.key, required this.onDigitsChanged});

  @override
  State<PhoneInputField> createState() => _PhoneInputFieldState();
}

class _PhoneInputFieldState extends State<PhoneInputField> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(() {
      setState(() => _focused = _focusNode.hasFocus);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

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
      child: Row(
        children: [
          Expanded(
            child: Directionality(
              textDirection: TextDirection.ltr,
              child: TextField(
                controller: _controller,
                focusNode: _focusNode,
                keyboardType: TextInputType.phone,
                textDirection: TextDirection.ltr,
                inputFormatters: [_PhoneGroupingFormatter()],
                style: ZTypography.cardTitle.copyWith(
                  color: z.ink,
                  fontSize: 21,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1,
                ),
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: EdgeInsets.zero,
                ),
                onChanged: (_) => widget.onDigitsChanged(extractPhoneDigits(_controller.text)),
              ),
            ),
          ),
          if (_focused)
            Container(width: 2, height: 24, color: z.coral),
        ],
      ),
    );
  }
}
