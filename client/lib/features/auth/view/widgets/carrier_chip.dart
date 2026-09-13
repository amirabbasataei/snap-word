import 'package:flutter/material.dart';
import 'package:wordchain/core/theme/app_spacing.dart';
import 'package:wordchain/core/theme/app_tokens.dart';
import 'package:wordchain/core/theme/app_typography.dart';

/// Iran mobile prefix → carrier name, for the "شمارهٔ ایران · ایرانسل"
/// auto-detect line. Approximate, common-range mapping — not sourced from an
/// authoritative MCC/MNC registry, so treat as best-effort display only,
/// never for validation (the server/normalizePhone rules on 09XXXXXXXXX
/// shape alone, not carrier).
const Map<String, String> _carrierPrefixes = {
  '0910': 'همراه اول', '0911': 'همراه اول', '0912': 'همراه اول',
  '0913': 'همراه اول', '0914': 'همراه اول', '0915': 'همراه اول',
  '0916': 'همراه اول', '0917': 'همراه اول', '0918': 'همراه اول',
  '0919': 'همراه اول', '0990': 'همراه اول', '0991': 'همراه اول',
  '0992': 'همراه اول', '0993': 'همراه اول', '0994': 'همراه اول',
  '0930': 'ایرانسل', '0933': 'ایرانسل', '0935': 'ایرانسل',
  '0936': 'ایرانسل', '0937': 'ایرانسل', '0938': 'ایرانسل',
  '0939': 'ایرانسل', '0900': 'ایرانسل', '0901': 'ایرانسل',
  '0902': 'ایرانسل', '0903': 'ایرانسل', '0905': 'ایرانسل',
  '0941': 'ایرانسل', '0999': 'ایرانسل',
  '0920': 'رایتل', '0921': 'رایتل', '0922': 'رایتل',
  '0904': 'تالیا', '0932': 'تالیا',
};

String? detectCarrier(String digits) {
  if (digits.length < 4 || !digits.startsWith('09')) return null;
  return _carrierPrefixes[digits.substring(0, 4)];
}

/// The teal-check + "شمارهٔ ایران · «carrier»" line under the phone field.
/// Renders nothing until the number is long enough to resolve a carrier.
class CarrierChip extends StatelessWidget {
  final String digits;

  const CarrierChip({super.key, required this.digits});

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    final carrier = digits.length == 11 ? detectCarrier(digits) : null;
    if (carrier == null) return const SizedBox.shrink();

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 18,
          height: 18,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: z.teal, borderRadius: BorderRadius.circular(6)),
          child: Icon(Icons.check, size: 12, color: z.onTeal),
        ),
        const SizedBox(width: ZSpacing.sm),
        Text(
          'شمارهٔ ایران · $carrier',
          style: ZTypography.metaLabel.copyWith(color: z.ink60, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}
