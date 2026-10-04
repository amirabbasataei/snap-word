import 'package:flutter/widgets.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Monochrome SVG icon from `assets/icons/` (Lucide), tinted via [color].
class ZIcon extends StatelessWidget {
  final String name;
  final double size;
  final Color color;

  const ZIcon(this.name, {super.key, this.size = 20, required this.color});

  @override
  Widget build(BuildContext context) {
    return SvgPicture.asset(
      'assets/icons/$name.svg',
      width: size,
      height: size,
      colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
    );
  }
}
