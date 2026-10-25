import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:wordchain/core/theme/app_game_metrics.dart';
import 'package:wordchain/core/theme/app_scene_tokens.dart';
import 'package:wordchain/core/theme/app_tokens.dart';
import 'package:wordchain/core/theme/app_typography.dart';
import 'package:wordchain/core/utils/persian_digits.dart';
import 'package:wordchain/core/widgets/chunky.dart';

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
/// number ("09123456789", "+98 912 345 6789", "0098…") has its own leading 09
/// or country code dropped; typing is never stripped, because a local part can
/// legitimately start with 09 (0909…) or 98 (0998…).
String _localDigits(String input, {required bool pasted}) {
  var d = extractPhoneDigits(input);
  if (pasted) {
    if (d.startsWith('0098')) {
      d = '0${d.substring(4)}';
    } else if (d.startsWith('98') && d.length == 12) {
      d = '0${d.substring(2)}';
    }
    if (d.length > _localLength && d.startsWith(_prefix)) {
      d = d.substring(_prefix.length);
    }
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

/// Canvas `ZPhoneA` phone field: a 58dp sunken box (3dp outline, `wash` fill,
/// `track` band along the top) with a round check badge at the start that
/// turns teal once the number is complete, then a fixed ۰۹ prefix and the
/// remaining digits grouped and in Persian digits (always LTR). Reports the
/// full normalised ASCII number (09 + typed digits) via [onDigitsChanged] —
/// the network layer never sees the display string. [valid] only drives the
/// badge; the parent owns validation.
class PhoneInputField extends StatefulWidget {
  final ValueChanged<String> onDigitsChanged;
  final VoidCallback? onSubmitted;
  final bool valid;
  final bool enabled;
  final bool autofocus;

  const PhoneInputField({
    super.key,
    required this.onDigitsChanged,
    this.onSubmitted,
    this.valid = false,
    this.enabled = true,
    this.autofocus = false,
  });

  @override
  State<PhoneInputField> createState() => _PhoneInputFieldState();
}

class _PhoneInputFieldState extends State<PhoneInputField> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  TextStyle _style(ZColors z) => ZTypography.display.copyWith(
    color: z.ink,
    fontSize: 23,
    letterSpacing: .5,
    height: 1.0,
    leadingDistribution: TextLeadingDistribution.even,
  );

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    final zs = context.zs;
    final style = _style(z);
    final focused = _focusNode.hasFocus;
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.3,
      child: Semantics(
        label: 'شمارهٔ موبایل',
        textField: true,
        child: Container(
          height: 58,
          decoration: BoxDecoration(
            color: z.wash,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: zs.outline, width: ZGame.outline),
            // The focus ring sits outside the outline, like the active OTP box.
            boxShadow:
                focused ? [BoxShadow(color: z.amber, spreadRadius: 3)] : null,
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(13),
            child: Stack(
              children: [
                // Inset top shadow of the canvas (`inset 0 3px 0 track`).
                PositionedDirectional(
                  start: 0,
                  end: 0,
                  top: 0,
                  height: 3,
                  child: ColoredBox(color: zs.track),
                ),
                Positioned.fill(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    // LTR so the badge and prefix sit at the left, directly
                    // before the typed digits.
                    child: Row(
                      textDirection: TextDirection.ltr,
                      children: [
                        _Badge(valid: widget.valid),
                        const SizedBox(width: 10),
                        Text(toPersianDigits(_prefix), style: style),
                        Expanded(
                          child: Directionality(
                            textDirection: TextDirection.ltr,
                            child: TextField(
                              controller: _controller,
                              focusNode: _focusNode,
                              enabled: widget.enabled,
                              autofocus: widget.autofocus,
                              keyboardType: TextInputType.phone,
                              textInputAction: TextInputAction.done,
                              textDirection: TextDirection.ltr,
                              inputFormatters: [_PhoneGroupingFormatter()],
                              style: style,
                              cursorColor: z.ink,
                              textAlignVertical: TextAlignVertical.center,
                              decoration: InputDecoration(
                                border: InputBorder.none,
                                isDense: true,
                                contentPadding: EdgeInsets.zero,
                              ),
                              onChanged:
                                  (_) => widget.onDigitsChanged(
                                    '$_prefix${extractPhoneDigits(_controller.text)}',
                                  ),
                              onSubmitted: (_) => widget.onSubmitted?.call(),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The round badge at the start of the field: a ring while the number is
/// incomplete, a teal check once it is.
class _Badge extends StatelessWidget {
  final bool valid;

  const _Badge({required this.valid});

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    final zs = context.zs;
    return ExcludeSemantics(
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: valid ? z.teal : null,
          border: Border.all(
            color: valid ? zs.outline : z.line,
            width: ZGame.outlineInner,
          ),
        ),
        alignment: Alignment.center,
        child:
            valid
                ? SvgPicture.string(
                  '<svg viewBox="0 0 24 24" fill="none" stroke="${svgHex(z.onTeal)}" stroke-width="4" stroke-linecap="round" stroke-linejoin="round"><path d="M5 12.5l4.5 4.5L19 7"/></svg>',
                  width: 14,
                  height: 14,
                )
                : null,
      ),
    );
  }
}
