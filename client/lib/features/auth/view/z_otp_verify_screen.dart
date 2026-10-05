import 'package:wordchain/core/widgets/z_toast.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:wordchain/core/di/injection.dart';
import 'package:wordchain/core/theme/app_spacing.dart';
import 'package:wordchain/core/theme/app_tokens.dart';
import 'package:wordchain/core/theme/app_typography.dart';
import 'package:wordchain/core/utils/persian_digits.dart';
import 'package:wordchain/core/widgets/z_buttons.dart';
import 'package:wordchain/features/auth/cubit/auth_cubit.dart';
import 'package:wordchain/features/auth/cubit/otp_flow_cubit.dart';
import 'package:wordchain/features/auth/view/widgets/otp_box_row.dart';
import 'package:wordchain/features/auth/view/widgets/resend_countdown_pill.dart';
import 'package:wordchain/core/utils/error_messages.dart';

/// Route args for `/login/otp`, carried via GoRouterState.extra (not query
/// params — a stashed referral code shouldn't round-trip through a URL).
class OtpVerifyArgs {
  final String phone;
  final String? returnPath;
  final String? referralCode;
  final int initialCooldownSeconds;

  const OtpVerifyArgs({
    required this.phone,
    this.returnPath,
    this.referralCode,
    required this.initialCooldownSeconds,
  });
}

class ZOtpVerifyScreen extends StatelessWidget {
  final OtpVerifyArgs args;

  const ZOtpVerifyScreen({super.key, required this.args});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create:
          (_) => OtpFlowCubit(
            authCubit: getIt<AuthCubit>(),
            phone: args.phone,
            initialCooldownSeconds: args.initialCooldownSeconds,
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
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onChanged() {
    setState(() {});
    if (_code.length == 4) _submit();
  }

  Future<void> _submit() async {
    final cubit = context.read<OtpFlowCubit>();
    final result = await cubit.submit(
      _code,
      referralCode: widget.args.referralCode,
    );
    if (!mounted) return;
    if (result == null) {
      // Failed — clear so the user can retype; error text renders from state.
      _controller.clear();
      return;
    }
    if (result.isNewUser &&
        widget.args.referralCode != null &&
        result.referralWarning == null) {
      ZToast.show(context, '۱۰۰ سکهٔ خوش‌آمد گرفتی!', kind: ZToastKind.success);
    }
    context.go(widget.args.returnPath ?? '/home');
  }

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    final state = context.watch<OtpFlowCubit>().state;

    return Scaffold(
      backgroundColor: z.paper,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                ZSpacing.xxl,
                ZSpacing.lg,
                ZSpacing.xxl,
                0,
              ),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => context.pop(),
                    child: Container(
                      width: 34,
                      height: 34,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: z.surface,
                        borderRadius: BorderRadius.circular(11),
                        border: Border.all(color: z.line),
                      ),
                      child: Icon(Icons.arrow_back, size: 16, color: z.ink60),
                    ),
                  ),
                  const SizedBox(width: ZSpacing.md),
                  Text(
                    'تأیید شماره',
                    style: ZTypography.cardTitle.copyWith(color: z.ink),
                  ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(
                  ZSpacing.xxl,
                  ZSpacing.xl,
                  ZSpacing.xxl,
                  ZSpacing.xl,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'کد چهاررقمی را بزن',
                      style: ZTypography.display.copyWith(
                        fontSize: 24,
                        color: z.ink,
                      ),
                    ),
                    const SizedBox(height: 7),
                    Row(
                      children: [
                        Text(
                          'فرستاده شد به',
                          style: ZTypography.body.copyWith(
                            color: z.ink60,
                            fontSize: 12.5,
                          ),
                        ),
                        const SizedBox(width: ZSpacing.sm),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 11,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: z.surface,
                            border: Border.all(color: z.line),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            toPersianDigits(widget.args.phone),
                            textDirection: TextDirection.ltr,
                            style: ZTypography.cardTitle.copyWith(
                              color: z.ink,
                              fontSize: 13,
                            ),
                          ),
                        ),
                        const SizedBox(width: ZSpacing.sm),
                        GestureDetector(
                          onTap: () => context.pop(),
                          child: Text(
                            'ویرایش',
                            style: ZTypography.metaLabel.copyWith(
                              color: z.indigo,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: ZSpacing.xxl),
                    // The boxes are display-only; a transparent TextField on top
                    // drives them with the phone's own number keyboard.
                    Stack(
                      children: [
                        OtpBoxRow(code: _code),
                        Positioned.fill(
                          child: Opacity(
                            opacity: 0,
                            child: TextField(
                              controller: _controller,
                              focusNode: _focusNode,
                              autofocus: true,
                              enabled: !state.submitting,
                              keyboardType: TextInputType.number,
                              autofillHints: const [AutofillHints.oneTimeCode],
                              enableSuggestions: false,
                              autocorrect: false,
                              showCursor: false,
                              enableInteractiveSelection: false,
                              inputFormatters: [_OtpDigitsFormatter()],
                              decoration: const InputDecoration(
                                border: InputBorder.none,
                                counterText: '',
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (state.errorMessage != null) ...[
                      const SizedBox(height: ZSpacing.md),
                      Text(
                        errorMessageFor(state.errorCode),
                        style: ZTypography.metaLabel.copyWith(color: z.coral),
                      ),
                    ],
                    const SizedBox(height: ZSpacing.lg),
                    ResendCountdownRow(
                      secondsRemaining: state.cooldownSecondsRemaining,
                      sending: state.sendingResend,
                      onResend: () => context.read<OtpFlowCubit>().resend(),
                      onVoiceCall:
                          () =>
                              context.read<OtpFlowCubit>().resend(voice: true),
                    ),
                    const SizedBox(height: ZSpacing.xl),
                    AccentButton(
                      label: state.submitting ? '...' : 'تأیید و ورود',
                      accent: ZAccentColor.teal,
                      onPressed:
                          (_code.length == 4 && !state.submitting)
                              ? _submit
                              : null,
                    ),
                    const SizedBox(height: ZSpacing.lg),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                      decoration: BoxDecoration(
                        color: z.surface,
                        border: Border.all(color: z.line),
                        borderRadius: BorderRadius.circular(ZRadius.cardMax),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'تازه‌واردی؟',
                                  style: ZTypography.cardTitle.copyWith(
                                    color: z.ink,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'با همین کد، حساب تازه‌ات ساخته می‌شود و ۱۰۰ سکهٔ خوش‌آمد می‌گیری.',
                                  style: ZTypography.metaLabel.copyWith(
                                    color: z.ink60,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Keeps up to 4 digits, folding Persian/Arabic-Indic digits to ASCII.
class _OtpDigitsFormatter extends TextInputFormatter {
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
