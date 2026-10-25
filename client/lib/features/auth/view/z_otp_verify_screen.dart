import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:wordchain/core/di/injection.dart';
import 'package:wordchain/core/theme/app_game_metrics.dart';
import 'package:wordchain/core/theme/app_scene_tokens.dart';
import 'package:wordchain/core/theme/app_tokens.dart';
import 'package:wordchain/core/theme/app_typography.dart';
import 'package:wordchain/core/utils/error_messages.dart';
import 'package:wordchain/core/utils/persian_digits.dart';
import 'package:wordchain/core/widgets/chunky.dart';
import 'package:wordchain/core/widgets/motion.dart';
import 'package:wordchain/core/widgets/z_dialog.dart';
import 'package:wordchain/core/widgets/z_mascot.dart';
import 'package:wordchain/core/widgets/z_ribbon_title.dart';
import 'package:wordchain/core/widgets/z_toast.dart';
import 'package:wordchain/features/auth/cubit/auth_cubit.dart';
import 'package:wordchain/features/auth/cubit/otp_flow_cubit.dart';
import 'package:wordchain/features/auth/data/auth_repository.dart';
import 'package:wordchain/features/auth/view/widgets/auth_button.dart';
import 'package:wordchain/features/auth/view/widgets/otp_box_row.dart';
import 'package:wordchain/features/auth/view/widgets/otp_parts.dart';
import 'package:wordchain/features/game/view/widgets/z_game_hud.dart';
import 'package:wordchain/features/game/view/widgets/z_over_hero.dart';
import 'package:wordchain/features/home/view/widgets/home_scene_background.dart';

/// Route args for `/login/otp`, carried via GoRouterState.extra (not query
/// params — a stashed referral code shouldn't round-trip through a URL).
class OtpVerifyArgs {
  final String phone;
  final String? returnPath;
  final String? referralCode;

  /// Seconds until a new code may be asked for (the server's resend cooldown,
  /// or what is left of it when the player came back to the same number).
  final int initialCooldownSeconds;

  /// Seconds the code on the phone stays valid; null when unknown.
  final int? initialExpiresSeconds;

  const OtpVerifyArgs({
    required this.phone,
    this.returnPath,
    this.referralCode,
    required this.initialCooldownSeconds,
    this.initialExpiresSeconds,
  });
}

/// ZOtpVerify — canvas `ZOtpA`. The code is typed on the phone's own number
/// keyboard (the canvas' hand-drawn keypad is not built); the fourth digit
/// submits at once.
class ZOtpVerifyScreen extends StatelessWidget {
  final OtpVerifyArgs args;

  /// Injected by tests; the app reads the device clock.
  final DateTime Function()? clock;

  const ZOtpVerifyScreen({super.key, required this.args, this.clock});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create:
          (_) => OtpFlowCubit(
            authCubit: getIt<AuthCubit>(),
            phone: args.phone,
            initialCooldownSeconds: args.initialCooldownSeconds,
            initialExpiresSeconds: args.initialExpiresSeconds,
            clock: clock,
          ),
      child: _ZOtpVerifyView(args: args),
    );
  }
}

class _ZOtpVerifyView extends StatefulWidget {
  final OtpVerifyArgs args;

  const _ZOtpVerifyView({required this.args});

  @override
  State<_ZOtpVerifyView> createState() => _ZOtpVerifyViewState();
}

class _ZOtpVerifyViewState extends State<_ZOtpVerifyView> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();

  String get _code => _controller.text;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onChanged);
    _focusNode.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onChanged() {
    setState(() {});
    if (_code.isNotEmpty) context.read<OtpFlowCubit>().clearError();
    if (_code.length == 4) _submit();
  }

  Future<void> _submit() async {
    if (_code.length != 4) return;
    final cubit = context.read<OtpFlowCubit>();
    // Signing in makes the router leave this page at once, so what is needed
    // afterwards is taken before the await.
    final router = GoRouter.of(context);
    final overlay = Overlay.of(context, rootOverlay: true);
    final args = widget.args;
    final result = await cubit.submit(_code, referralCode: args.referralCode);
    if (result == null) {
      if (!mounted) return;
      // Failed — clear so the user can retype; the error renders from state.
      _controller.clear();
      _focusNode.requestFocus();
      return;
    }
    final notice = _signupNotice(result, args.referralCode);
    if (notice != null) {
      ZToast.showOn(overlay, notice.$1, kind: notice.$2);
    }
    router.go(args.returnPath ?? '/home');
  }

  /// What the player should hear about their sign-up gift, from the server's
  /// own answer: the gift (the new account's whole balance), a referral code
  /// that did not resolve, or a code an existing account cannot use.
  (String, ZToastKind)? _signupNotice(AuthResult result, String? referral) {
    if (!result.isNewUser) {
      return referral == null
          ? null
          : (referralNeedsNewAccountMessage, ZToastKind.info);
    }
    if (referral != null && result.referralWarning != null) {
      return (referralNotFoundAtSignupMessage, ZToastKind.info);
    }
    return (welcomeBonusMessage(result.coins), ZToastKind.success);
  }

  void _back() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/login');
    }
  }

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    final state = context.watch<OtpFlowCubit>().state;
    final inset = MediaQuery.viewInsetsOf(context).bottom;
    final String? status =
        state.hasError
            ? errorMessageFor(state.errorCode)
            : state.codeExpired
            ? errorMessageFor('code_expired')
            : null;

    return Scaffold(
      backgroundColor: z.paper,
      resizeToAvoidBottomInset: false,
      body: Stack(
        fit: StackFit.expand,
        children: [
          const HomeSceneBackground(calm: true),
          Padding(
            padding: EdgeInsets.only(bottom: inset),
            child: SafeArea(
              bottom: inset == 0,
              child: Column(
                children: [
                  ZOverEnter(
                    kind: ZOverEnterKind.up,
                    delayMs: 0,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
                      child: Row(
                        children: [
                          ZGameBackButton(onTap: _back),
                          const SizedBox(width: 10),
                          const Expanded(
                            child: Center(
                              child: ZRibbonTitle(
                                'تأیید شماره',
                                accent: ZDialogAccent.indigo,
                                expand: false,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          const SizedBox(width: ZGame.gameBackButton),
                        ],
                      ),
                    ),
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.only(bottom: 18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          ZOverEnter(
                            kind: ZOverEnterKind.up,
                            delayMs: 100,
                            child: _Heading(
                              phone: widget.args.phone,
                              onEdit: _back,
                            ),
                          ),
                          ZOverEnter(
                            kind: ZOverEnterKind.up,
                            delayMs: 200,
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(16, 22, 16, 0),
                              child: _CodeInput(
                                controller: _controller,
                                focusNode: _focusNode,
                                enabled: !state.submitting,
                              ),
                            ),
                          ),
                          if (status != null)
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                              child: _StatusChip(status),
                            ),
                          ZOverEnter(
                            kind: ZOverEnterKind.up,
                            delayMs: 260,
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                              child: Center(
                                child: ResendPill(
                                  secondsRemaining:
                                      state.cooldownSecondsRemaining,
                                  sending: state.sendingResend,
                                  onResend:
                                      () =>
                                          context.read<OtpFlowCubit>().resend(),
                                ),
                              ),
                            ),
                          ),
                          ZOverEnter(
                            kind: ZOverEnterKind.up,
                            delayMs: 320,
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                              child: WelcomeCard(
                                hasReferral: widget.args.referralCode != null,
                              ),
                            ),
                          ),
                          ZOverEnter(
                            kind: ZOverEnterKind.up,
                            delayMs: 380,
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
                              child: ZAuthButton(
                                label: 'تأیید و ورود',
                                busyLabel: 'در حال بررسی کد…',
                                busy: state.submitting,
                                height: 58,
                                radius: 20,
                                fontSize: 19,
                                depth: ZGame.depthMd,
                                onTap: _code.length == 4 ? _submit : null,
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
        ],
      ),
    );
  }
}

/// Mascot beside «کد چهاررقمی را بزن» and where the code was sent, with the
/// «ویرایش» chip that goes back to fix the number.
class _Heading extends StatelessWidget {
  final String phone;
  final VoidCallback onEdit;

  const _Heading({required this.phone, required this.onEdit});

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    final zs = context.zs;
    final animate = !homeReducedMotion(context);
    final meta = ZTypography.metaLabel.copyWith(
      fontSize: 12.5,
      fontWeight: FontWeight.w700,
      color: z.ink,
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          ZMascot(size: 62, shadow: false, animate: animate),
          const SizedBox(width: 12),
          Expanded(
            child: MediaQuery.withClampedTextScaling(
              maxScaleFactor: 1.6,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Semantics(
                    header: true,
                    child: Text(
                      'کد چهاررقمی را بزن',
                      style: ZTypography.display.copyWith(
                        fontSize: 22,
                        height: 1.2,
                        color: z.ink,
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 6,
                    children: [
                      Text('فرستاده شد به', style: meta),
                      Directionality(
                        textDirection: TextDirection.ltr,
                        child: Text(
                          toPersianDigits(phone),
                          style: meta.copyWith(fontWeight: FontWeight.w900),
                        ),
                      ),
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: onEdit,
                        child: Semantics(
                          button: true,
                          label: 'ویرایش شماره',
                          excludeSemantics: true,
                          child: Padding(
                            // The chip is 28dp; the tap target is taller.
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: Container(
                              height: 28,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                              ),
                              decoration: BoxDecoration(
                                color: z.surface,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: zs.outline,
                                  width: ZGame.outlineInner - .5,
                                ),
                              ),
                              // Not `alignment:` — in a Wrap that would stretch
                              // the chip across the whole line.
                              child: Center(
                                widthFactor: 1,
                                child: Text(
                                  'ویرایش',
                                  style: ZTypography.metaLabel.copyWith(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w900,
                                    height: 1,
                                    color: zs.indigoInk,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
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

/// The boxes plus the invisible TextField that feeds them. The field sits
/// over the boxes, so a tap on them (re)opens the keyboard; it stays in the
/// semantics tree so a screen reader can type into it.
class _CodeInput extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool enabled;

  const _CodeInput({
    required this.controller,
    required this.focusNode,
    required this.enabled,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        ListenableBuilder(
          listenable: controller,
          builder:
              (context, _) =>
                  OtpBoxRow(code: controller.text, active: focusNode.hasFocus),
        ),
        Positioned.fill(
          child: Opacity(
            opacity: 0,
            alwaysIncludeSemantics: true,
            child: Semantics(
              label: 'کد چهاررقمی',
              child: TextField(
                controller: controller,
                focusNode: focusNode,
                autofocus: true,
                enabled: enabled,
                keyboardType: TextInputType.number,
                autofillHints: const [AutofillHints.oneTimeCode],
                enableSuggestions: false,
                autocorrect: false,
                showCursor: false,
                enableInteractiveSelection: false,
                inputFormatters: [OtpDigitsFormatter()],
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  counterText: '',
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// A message on the sky: the status line on a surface chip so it reads on
/// both themes.
class _StatusChip extends StatelessWidget {
  final String message;

  const _StatusChip(this.message);

  @override
  Widget build(BuildContext context) {
    return ChunkyBox(
      fill: context.z.surface,
      depth: ZGame.depthSm,
      radius: 14,
      highlight: false,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: AuthStatusLine(message),
    );
  }
}

/// Keeps up to 4 digits, folding Persian/Arabic-Indic digits to ASCII.
class OtpDigitsFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final buffer = StringBuffer();
    for (final rune in newValue.text.runes) {
      if (rune >= 0x30 && rune <= 0x39) {
        buffer.writeCharCode(rune);
      } else if (rune >= 0x6F0 && rune <= 0x6F9) {
        buffer.writeCharCode(0x30 + (rune - 0x6F0));
      } else if (rune >= 0x660 && rune <= 0x669) {
        buffer.writeCharCode(0x30 + (rune - 0x660));
      }
    }
    final digits = buffer.toString();
    final text = digits.length > 4 ? digits.substring(0, 4) : digits;
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}
