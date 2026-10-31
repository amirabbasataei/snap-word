import 'package:flutter/material.dart';
import 'package:wordchain/core/theme/app_game_metrics.dart';
import 'package:wordchain/core/theme/app_scene_tokens.dart';
import 'package:wordchain/core/theme/app_tokens.dart';
import 'package:wordchain/core/theme/app_typography.dart';
import 'package:wordchain/core/widgets/chunky.dart';
import 'package:wordchain/core/widgets/chunky_pressable.dart';
import 'package:wordchain/core/widgets/motion.dart';
import 'package:wordchain/features/profile/view/widgets/profile_notifications_switch.dart';
import 'package:wordchain/features/profile/view/widgets/profile_parts.dart';

/// The row of chunky controls at the bottom of the profile (canvas: «حالت شب»,
/// «صدا و لرزش», «یادآور»). Only controls that do something are drawn:
///  * «حالت شب» — the theme switch (`ThemeCubit`), also for guests;
///  * «کد دعوت داری؟» — redeem someone else's code, once (signed in);
///  * «اعلان‌ها» — the push on/off switch beside it (signed in; it also asks
///    for the OS permission, after the explainer, when switching on);
///  * «خروج از حساب» (signed in), full width in solid coral;
///  * «قوانین و مقررات» / «حریم خصوصی» — the public pages, opened in the browser.
/// «صدا و لرزش» and «یادآور چالش روزانه» are not drawn: no setting is stored
/// and no reminder is scheduled, so a toggle would only pretend.
class ProfileSettings extends StatelessWidget {
  final bool isDark;
  final VoidCallback onToggleTheme;
  final bool signedIn;
  final VoidCallback onRedeem;
  final VoidCallback onLogout;
  final VoidCallback onTerms;
  final VoidCallback onPrivacy;

  const ProfileSettings({
    super.key,
    required this.isDark,
    required this.onToggleTheme,
    required this.signedIn,
    required this.onRedeem,
    required this.onLogout,
    required this.onTerms,
    required this.onPrivacy,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: ProfileThemeSwitch(isDark: isDark, onTap: onToggleTheme)),
            if (signedIn) ...[const SizedBox(width: 8), const Expanded(child: ProfileNotificationsSwitch())],
          ],
        ),
        if (signedIn) ...[const SizedBox(height: 4), ProfileChunkButton(label: 'کد دعوت داری؟', onTap: onRedeem)],
        const SizedBox(height: 4),
        Row(
          children: [
            Expanded(
              child: ProfileChunkButton(
                label: 'قوانین و مقررات',
                semanticLabel: 'قوانین و مقررات، باز کردن در مرورگر',
                onTap: onTerms,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: ProfileChunkButton(
                label: 'حریم خصوصی',
                semanticLabel: 'حریم خصوصی، باز کردن در مرورگر',
                onTap: onPrivacy,
              ),
            ),
          ],
        ),
        if (signedIn) ...[
          const SizedBox(height: 4),
          ProfileChunkButton(label: 'خروج از حساب', destructive: true, onTap: onLogout),
        ],
        const SizedBox(height: 4),
      ],
    );
  }
}

/// «حالت شب» — [ProfileSwitchButton] bound to the theme.
class ProfileThemeSwitch extends StatelessWidget {
  final bool isDark;
  final VoidCallback onTap;

  const ProfileThemeSwitch({super.key, required this.isDark, required this.onTap});

  @override
  Widget build(BuildContext context) => ProfileSwitchButton(label: 'حالت شب', value: isDark, onTap: onTap);
}

/// A chunky button with a label and a mini switch (canvas: 30×18 track, 12
/// thumb). The thumb sits at the start edge when off and the end edge when on;
/// the track is teal when on. While [busy] the thumb is a small spinner, so a
/// slow change (a permission prompt, a network call) reads as "working" rather
/// than as an ignored tap; the caller ignores taps meanwhile.
class ProfileSwitchButton extends StatelessWidget {
  final String label;
  final bool value;
  final bool busy;
  final VoidCallback onTap;

  const ProfileSwitchButton({
    super.key,
    required this.label,
    required this.value,
    required this.onTap,
    this.busy = false,
  });

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    final reduced = homeReducedMotion(context);
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.3,
      child: Semantics(
        toggled: value,
        value: busy ? 'در حال انجام' : null,
        child: ChunkyPressable(
          depth: ZGame.depthSm,
          onTap: onTap,
          semanticLabel: label,
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
                            label,
                            maxLines: 1,
                            style: ZTypography.button.copyWith(fontSize: 12.5, color: z.ink),
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      ExcludeSemantics(
                        child: AnimatedContainer(
                          duration: reduced ? Duration.zero : const Duration(milliseconds: 160),
                          width: 30,
                          height: 18,
                          padding: const EdgeInsets.all(1),
                          alignment: value ? AlignmentDirectional.centerEnd : AlignmentDirectional.centerStart,
                          decoration: BoxDecoration(
                            color: value ? z.teal : z.wash,
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(color: context.zs.outline, width: 2),
                          ),
                          child:
                              busy
                                  ? SizedBox(
                                    // Square, like the thumb: unconstrained it
                                    // would stretch to the track and go oval.
                                    width: 12,
                                    height: 12,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: value ? z.surface : z.ink,
                                    ),
                                  )
                                  : Container(
                                    width: 12,
                                    height: 12,
                                    decoration: BoxDecoration(shape: BoxShape.circle, color: value ? z.surface : z.ink),
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
