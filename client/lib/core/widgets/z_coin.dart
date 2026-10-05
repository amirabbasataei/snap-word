import 'package:flutter/widgets.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Full-colour gold coin (`assets/icons/coin_gold.svg`). Not tinted — it reads
/// the same on light and dark surfaces. Use wherever a coin amount is shown.
class ZCoin extends StatelessWidget {
  final double size;

  const ZCoin({super.key, this.size = 18});

  @override
  Widget build(BuildContext context) {
    return SvgPicture.asset('assets/icons/coin_gold.svg', width: size, height: size);
  }
}
