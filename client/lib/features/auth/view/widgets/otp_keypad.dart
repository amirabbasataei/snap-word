import 'package:flutter/material.dart';
import 'package:wordchain/core/theme/app_elevation.dart';
import 'package:wordchain/core/theme/app_tokens.dart';
import 'package:wordchain/core/theme/app_typography.dart';
import 'package:wordchain/core/utils/persian_digits.dart';

/// Fully custom 3×4 numeric keypad matching ZOtp.dc.html's footer — the
/// canvas draws its own keypad rather than relying on the system keyboard,
/// so this stays pixel-close instead of falling back to a stock TextField.
/// Real OS-level SMS auto-read is out of scope; this is manual entry only.
class OtpKeypad extends StatelessWidget {
  final ValueChanged<String> onDigit;
  final VoidCallback onBackspace;

  const OtpKeypad({super.key, required this.onDigit, required this.onBackspace});

  static const _rows = [
    ['1', '2', '3'],
    ['4', '5', '6'],
    ['7', '8', '9'],
    ['', '0', '⌫'],
  ];

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Column(
        children: [
          for (var r = 0; r < _rows.length; r++) ...[
            if (r > 0) const SizedBox(height: 8),
            Row(
              children: [
                for (var c = 0; c < _rows[r].length; c++) ...[
                  if (c > 0) const SizedBox(width: 8),
                  Expanded(child: _key(z, _rows[r][c])),
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _key(ZColors z, String key) {
    if (key.isEmpty) return const SizedBox(height: 48);
    final isBackspace = key == '⌫';

    return GestureDetector(
      onTap: isBackspace ? onBackspace : () => onDigit(key),
      child: Container(
        height: 48,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: isBackspace ? z.wash : z.paper,
          borderRadius: BorderRadius.circular(12),
          border: isBackspace ? null : Border.all(color: z.line),
          boxShadow: isBackspace ? null : ZElevation.solidEdge(z.line, depth: 2),
        ),
        child: isBackspace
            ? Icon(Icons.backspace_outlined, size: 17, color: z.ink60)
            : Text(
                toPersianDigits(key),
                style: ZTypography.cardTitle.copyWith(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: z.ink,
                ),
              ),
      ),
    );
  }
}
