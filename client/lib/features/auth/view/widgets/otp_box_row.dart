import 'package:flutter/material.dart';
import 'package:wordchain/core/theme/app_elevation.dart';
import 'package:wordchain/core/theme/app_tokens.dart';
import 'package:wordchain/core/theme/app_typography.dart';
import 'package:wordchain/core/utils/persian_digits.dart';

/// The 4 OTP digit boxes from ZOtp.dc.html. Explicitly LTR (matching the
/// canvas's `direction:ltr` row) even though the page around it is RTL, so
/// digits fill left-to-right in typing order. Driven entirely by [code]
/// (0-4 ASCII digits) — no system TextField/keyboard, since input comes from
/// the custom OtpKeypad below it, matching the canvas pixel-for-pixel.
class OtpBoxRow extends StatelessWidget {
  final String code;

  const OtpBoxRow({super.key, required this.code});

  static const _boxCount = 4;

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Row(
        children: [
          for (var i = 0; i < _boxCount; i++) ...[
            if (i > 0) const SizedBox(width: 10),
            Expanded(child: _box(z, i)),
          ],
        ],
      ),
    );
  }

  Widget _box(ZColors z, int index) {
    final filled = index < code.length;
    final active = index == code.length;

    return Container(
      height: 72,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: active ? z.paper : z.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: active ? z.ink : z.line, width: active ? 2 : 1),
        boxShadow: filled ? ZElevation.solidEdge(z.line, depth: ZElevation.cardDepth) : null,
      ),
      child: filled
          ? Text(
              toPersianDigits(code[index]),
              style: ZTypography.display.copyWith(fontSize: 30, color: z.ink),
            )
          : active
              ? Container(width: 2, height: 30, color: z.coral)
              : Container(
                  width: 14,
                  height: 3,
                  decoration: BoxDecoration(color: z.line, borderRadius: BorderRadius.circular(2)),
                ),
    );
  }
}
