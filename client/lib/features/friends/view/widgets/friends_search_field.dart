import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:wordchain/core/theme/app_game_metrics.dart';
import 'package:wordchain/core/theme/app_tokens.dart';
import 'package:wordchain/core/theme/app_typography.dart';
import 'package:wordchain/core/widgets/chunky.dart';

/// The search box under the header (canvas `ZFriendsA`: 48 tall, 3px outline,
/// r16, flat `0 3px 0` edge). Filters the friends already loaded by name — it
/// does not query the server. Fixed height, so the text ignores scale above
/// 1.3×.
class FriendsSearchField extends StatelessWidget {
  final TextEditingController controller;

  const FriendsSearchField({super.key, required this.controller});

  static const hint = 'جست‌وجوی نام دوستان';
  static const height = 48.0;

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    final style = ZTypography.body.copyWith(
      fontSize: 14,
      fontWeight: FontWeight.w700,
      color: z.ink,
    );
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.3,
      child: Padding(
        padding: const EdgeInsets.only(bottom: ZGame.depthSm + ZGame.outline),
        child: ChunkyBox(
          fill: z.surface,
          depth: ZGame.depthSm,
          radius: 16,
          highlight: false,
          height: height,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              ExcludeSemantics(
                child: SvgPicture.string(
                  '<svg viewBox="0 0 24 24" fill="none" stroke="${svgHex(z.ink60)}" stroke-width="3" stroke-linecap="round"><circle cx="11" cy="11" r="6.5"/><path d="M16 16l4.5 4.5"/></svg>',
                  width: 20,
                  height: 20,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: controller,
                  style: style,
                  textInputAction: TextInputAction.search,
                  cursorColor: z.indigo,
                  decoration: InputDecoration(
                    isDense: true,
                    filled: false,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    contentPadding: EdgeInsets.zero,
                    hintText: hint,
                    hintStyle: style.copyWith(color: z.ink60),
                  ),
                ),
              ),
              ValueListenableBuilder<TextEditingValue>(
                valueListenable: controller,
                builder:
                    (context, value, _) =>
                        value.text.isEmpty
                            ? const SizedBox.shrink()
                            : Semantics(
                              button: true,
                              label: 'پاک کردن جست‌وجو',
                              child: GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onTap: controller.clear,
                                child: SizedBox(
                                  width: 36,
                                  height: 36,
                                  child: Icon(
                                    Icons.close_rounded,
                                    size: 18,
                                    color: z.ink60,
                                  ),
                                ),
                              ),
                            ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
