import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:wordchain/core/di/injection.dart';
import 'package:wordchain/core/theme/app_game_metrics.dart';
import 'package:wordchain/core/theme/app_scene_tokens.dart';
import 'package:wordchain/core/theme/app_tokens.dart';
import 'package:wordchain/core/theme/app_typography.dart';
import 'package:wordchain/core/utils/error_messages.dart';
import 'package:wordchain/core/widgets/chunky.dart';
import 'package:wordchain/features/auth/cubit/auth_cubit.dart';
import 'package:wordchain/features/auth/cubit/phone_entry_cubit.dart';
import 'package:wordchain/features/auth/view/widgets/auth_button.dart';
import 'package:wordchain/features/auth/view/widgets/login_cards.dart';
import 'package:wordchain/features/auth/view/widgets/login_hero.dart';
import 'package:wordchain/features/auth/view/widgets/otp_parts.dart'
    show AuthStatusLine;
import 'package:wordchain/features/auth/view/widgets/phone_input_field.dart';
import 'package:wordchain/features/auth/view/widgets/referral_bottom_sheet.dart';
import 'package:wordchain/features/game/view/widgets/z_over_hero.dart';
import 'package:wordchain/features/home/view/widgets/home_scene_background.dart';

/// ZLogin — phone-entry screen (canvas `ZPhoneA`, «A · mascot-led»). A pushed
/// route, never required: «فعلاً مهمان می‌مانم» goes straight to Home, and
/// [returnPath] (the `return=` query) is where a successful login ends up.
class ZLoginScreen extends StatelessWidget {
  final String? returnPath;

  /// Injected by tests; the app reads the device clock.
  final DateTime Function()? clock;

  const ZLoginScreen({super.key, this.returnPath, this.clock});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create:
          (_) => PhoneEntryCubit(
            authCubit: getIt<AuthCubit>(),
            returnPath: returnPath,
            clock: clock,
          ),
      child: const _LoginView(),
    );
  }
}

class _LoginView extends StatelessWidget {
  const _LoginView();

  Future<void> _submit(BuildContext context) async {
    final cubit = context.read<PhoneEntryCubit>();
    final router = GoRouter.of(context);
    final args = await cubit.submit();
    if (args == null) return;
    await router.push<void>('/login/otp', extra: args);
  }

  Future<void> _openReferral(BuildContext context) async {
    final cubit = context.read<PhoneEntryCubit>();
    final code = await ReferralBottomSheet.show(context);
    if (code != null) cubit.setReferralCode(code);
  }

  void _guest(BuildContext context) {
    getIt<AuthCubit>().continueAsGuest();
    context.go('/home');
  }

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    final state = context.watch<PhoneEntryCubit>().state;
    final cubit = context.read<PhoneEntryCubit>();
    final inset = MediaQuery.viewInsetsOf(context).bottom;

    return Scaffold(
      backgroundColor: z.paper,
      // The scene keeps its shape under the keyboard; the content makes room.
      resizeToAvoidBottomInset: false,
      body: Stack(
        fit: StackFit.expand,
        children: [
          const HomeSceneBackground(),
          Padding(
            padding: EdgeInsets.only(bottom: inset),
            child: SafeArea(
              bottom: inset == 0,
              child: CustomScrollView(
                slivers: [
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: Column(
                      children: [
                        const LoginHero(),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: ZOverEnter(
                            kind: ZOverEnterKind.up,
                            delayMs: 300,
                            child: _PhoneCard(
                              state: state,
                              onDigits: cubit.setDigits,
                              onSubmit: () => _submit(context),
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                          child: ZOverEnter(
                            kind: ZOverEnterKind.up,
                            delayMs: 450,
                            child: ReferralTeaser(
                              code: state.referralCode,
                              onTap: () => _openReferral(context),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        const Spacer(),
                        ZOverEnter(
                          kind: ZOverEnterKind.up,
                          delayMs: 550,
                          child: GuestOption(onTap: () => _guest(context)),
                        ),
                        const SizedBox(height: 22),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The surface card: headline, the phone field, what the server said about
/// it, the terms line and the send button.
class _PhoneCard extends StatelessWidget {
  final PhoneEntryState state;
  final ValueChanged<String> onDigits;
  final VoidCallback onSubmit;

  const _PhoneCard({
    required this.state,
    required this.onDigits,
    required this.onSubmit,
  });

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    return ChunkyBox(
      fill: z.surface,
      depth: ZGame.depthLg,
      radius: 24,
      highlight: false,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          MediaQuery.withClampedTextScaling(
            maxScaleFactor: 1.6,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Semantics(
                  header: true,
                  child: Text(
                    'با شماره‌ات بیا تو',
                    style: ZTypography.display.copyWith(
                      fontSize: 22,
                      height: 1.3,
                      color: z.ink,
                    ),
                  ),
                ),
                Text(
                  'یک کد چهاررقمی برایت می‌فرستیم. رمزی در کار نیست.',
                  style: ZTypography.metaLabel.copyWith(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    height: 1.6,
                    color: z.ink60,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'شمارهٔ موبایل',
                  style: ZTypography.metaLabel.copyWith(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: z.ink,
                  ),
                ),
                const SizedBox(height: 6),
              ],
            ),
          ),
          PhoneInputField(
            valid: state.phoneValid,
            enabled: !state.sending,
            onDigitsChanged: onDigits,
            onSubmitted: state.canSubmit ? onSubmit : null,
          ),
          const SizedBox(height: 6),
          ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 22),
            child:
                state.hasError
                    ? AuthStatusLine(errorMessageFor(state.errorCode))
                    : const SizedBox.shrink(),
          ),
          const SizedBox(height: 6),
          MediaQuery.withClampedTextScaling(
            maxScaleFactor: 1.6,
            child: Text.rich(
              TextSpan(
                style: ZTypography.metaLabel.copyWith(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  height: 1.6,
                  color: z.ink60,
                ),
                children: [
                  const TextSpan(text: 'با ورود، '),
                  TextSpan(
                    text: 'قوانین و حریم خصوصی',
                    style: TextStyle(
                      color: context.zs.indigoInk,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const TextSpan(text: ' زنجیر را می‌پذیرم.'),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          ZAuthButton(
            label: 'فرستادن کد',
            busyLabel: 'در حال فرستادن کد…',
            busy: state.sending,
            onTap: state.canSubmit ? onSubmit : null,
          ),
        ],
      ),
    );
  }
}

/// «شمارهٔ ایران»: shown once the number is complete. Every number the server
/// accepts is an Iran mobile, which is all this claims — no carrier is named
/// (the prefix cannot tell once numbers are portable, and the API sends none).
class _IranChip extends StatelessWidget {
  const _IranChip();

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.3,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: z.inkSurface,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          'شمارهٔ ایران',
          style: ZTypography.metaLabel.copyWith(
            fontSize: 12,
            fontWeight: FontWeight.w800,
            height: 1.4,
            color: z.onInkSurface,
          ),
        ),
      ),
    );
  }
}
