import 'package:flutter/material.dart';
import 'package:wordchain/core/theme/app_game_metrics.dart';
import 'package:wordchain/core/theme/app_scene_tokens.dart';
import 'package:wordchain/core/theme/app_tokens.dart';
import 'package:wordchain/core/theme/app_typography.dart';
import 'package:wordchain/core/widgets/chunky.dart';
import 'package:wordchain/core/widgets/chunky_pressable.dart';
import 'package:wordchain/core/widgets/motion.dart';
import 'package:wordchain/features/profile/view/widgets/profile_parts.dart';

/// The row of chunky controls at the bottom of the profile (canvas: «حالت شب»,
/// «صدا و لرزش», «یادآور»). Only controls that do something are drawn:
///  * «حالت شب» — the theme switch (`ThemeCubit`), also for guests;
///  * «کد دعوت داری؟» — redeem someone else's code, once (signed in);
///  * «خروج از حساب» (signed in), on its own row.
/// «صدا و لرزش» and «یادآور چالش روزانه» are not drawn: no setting is stored
/// and no reminder is scheduled, so a toggle would only pretend.
class ProfileSettings extends StatelessWidget {
  final bool isDark;
  final VoidCallback onToggleTheme;
  final bool signedIn;
  final VoidCallback onRedeem;
  final VoidCallback onLogout;

  const ProfileSettings({
    super.key,
    required this.isDark,
    required this.onToggleTheme,
    required this.signedIn,
    required this.onRedeem,
    required this.onLogout,
  });

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: ProfileThemeSwitch(isDark: isDark, onTap: onToggleTheme),
            ),
            if (signedIn) ...[
              const SizedBox(width: 8),
              Expanded(
                child: ProfileChunkButton(
                  label: 'کد دعوت داری؟',
                  onTap: onRedeem,
                ),
              ),
            ],
          ],
        ),
        if (signedIn) ...[
          const SizedBox(height: 4),
          ProfileChunkButton(
            label: 'خروج از حساب',
            labelColor: z.coral,
            onTap: onLogout,
          ),
        ],
      ],
    );
  }
}

/// «حالت شب» with its mini switch (canvas: 30×18 track, 12 thumb). The thumb
/// sits at the start edge when off and the end edge when on; the track is
/// teal when on.
class ProfileThemeSwitch extends StatelessWidget {
  final bool isDark;
  final VoidCallback onTap;

  const ProfileThemeSwitch({
    super.key,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    final reduced = homeReducedMotion(context);
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.3,
      child: Semantics(
        toggled: isDark,
        child: ChunkyPressable(
          depth: ZGame.depthSm,
          onTap: onTap,
          semanticLabel: 'حالت شب',
          builder:
              (context, depth, _) => ChunkyBox(
                fill: z.surface,
                depth: depth,
                radius: 14,
                highlight: false,
                height: ProfileChunkButton.height,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                alignment: Alignment.center,
                child: ExcludeSemantics(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Flexible(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            'حالت شب',
                            maxLines: 1,
                            style: ZTypography.button.copyWith(
                              fontSize: 12.5,
                              color: z.ink,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      ExcludeSemantics(
                        child: AnimatedContainer(
                          duration:
                              reduced
                                  ? Duration.zero
                                  : const Duration(milliseconds: 160),
                          width: 30,
                          height: 18,
                          padding: const EdgeInsets.all(1),
                          alignment:
                              isDark
                                  ? AlignmentDirectional.centerEnd
                                  : AlignmentDirectional.centerStart,
                          decoration: BoxDecoration(
                            color: isDark ? z.teal : z.wash,
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(
                              color: context.zs.outline,
                              width: 2,
                            ),
                          ),
                          child: Container(
                            width: 12,
                            height: 12,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: isDark ? z.surface : z.ink,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
        ),
      ),
    );
  }
}
