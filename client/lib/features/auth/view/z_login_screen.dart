import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:wordchain/core/di/injection.dart';
import 'package:wordchain/core/theme/app_spacing.dart';
import 'package:wordchain/core/theme/app_tokens.dart';
import 'package:wordchain/core/theme/app_typography.dart';
import 'package:wordchain/core/widgets/dashed_tile.dart';
import 'package:wordchain/core/widgets/letter_tile.dart';
import 'package:wordchain/core/widgets/z_buttons.dart';
import 'package:wordchain/features/auth/cubit/auth_cubit.dart';
import 'package:wordchain/features/auth/data/auth_repository.dart';
import 'package:wordchain/features/auth/view/widgets/carrier_chip.dart';
import 'package:wordchain/features/auth/view/widgets/phone_input_field.dart';
import 'package:wordchain/features/auth/view/widgets/referral_bottom_sheet.dart';
import 'package:wordchain/features/auth/view/z_otp_verify_screen.dart';

/// ZLogin — phone-entry screen (matches ZPhone.dc.html). Replaces the old
/// email/password login_screen.dart entirely.
class ZLoginScreen extends StatefulWidget {
  final String? returnPath;

  const ZLoginScreen({super.key, this.returnPath});

  @override
  State<ZLoginScreen> createState() => _ZLoginScreenState();
}

class _ZLoginScreenState extends State<ZLoginScreen> {
  String _digits = '';
  bool _termsAccepted = false;
  bool _sending = false;
  String? _error;
  String? _referralCode;

  bool get _phoneValid => _digits.length == 11 && _digits.startsWith('09');
  bool get _canSubmit => _phoneValid && _termsAccepted && !_sending;

  Future<void> _openReferralSheet() async {
    final code = await ReferralBottomSheet.show(context);
    if (code != null && mounted) {
      setState(() => _referralCode = code);
    }
  }

  Future<void> _submit() async {
    if (!_canSubmit) return;
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      final result = await getIt<AuthCubit>().sendOtp(phone: _digits);
      if (!mounted) return;
      await context.push<void>(
        '/login/otp',
        extra: OtpVerifyArgs(
          phone: _digits,
          returnPath: widget.returnPath,
          referralCode: _referralCode,
          initialCooldownSeconds: result.resendCooldownSeconds,
        ),
      );
      if (mounted) setState(() => _sending = false);
    } on AuthException catch (e) {
      setState(() {
        _sending = false;
        _error = _mapSendError(e.code);
      });
    } on NetworkException catch (_) {
      setState(() {
        _sending = false;
        _error = 'خطا در اتصال به اینترنت';
      });
    }
  }

  String _mapSendError(String code) {
    switch (code) {
      case 'invalid_phone':
        return 'شماره موبایل معتبر نیست';
      case 'resend_cooldown':
        return 'کمی صبر کن و دوباره تلاش کن';
      case 'rate_limited':
        return 'درخواست‌های زیادی برای این شماره ثبت شده؛ بعداً دوباره امتحان کن';
      default:
        return 'مشکلی پیش آمد، دوباره تلاش کن';
    }
  }

  void _continueAsGuest() {
    getIt<AuthCubit>().continueAsGuest();
    context.go('/home');
  }

  @override
  Widget build(BuildContext context) {
    final z = context.z;

    return Scaffold(
      backgroundColor: z.paper,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(
                  ZSpacing.xxl,
                  ZSpacing.xxl,
                  ZSpacing.xxl,
                  ZSpacing.lg,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _wordmark(),
                    const SizedBox(height: ZSpacing.xxl),
                    Text(
                      'با شماره‌ات بیا تو',
                      style: ZTypography.display.copyWith(fontSize: 26, color: z.ink),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'یک کد چهاررقمی برایت می‌فرستیم. رمزی در کار نیست.',
                      style: ZTypography.body.copyWith(color: z.ink60),
                    ),
                    const SizedBox(height: ZSpacing.xl),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: z.surface,
                        border: Border.all(color: z.line),
                        borderRadius: BorderRadius.circular(ZRadius.cardMax),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'شمارهٔ موبایل',
                            style: ZTypography.metaLabel.copyWith(color: z.ink40),
                          ),
                          const SizedBox(height: 9),
                          PhoneInputField(
                            onDigitsChanged: (d) => setState(() => _digits = d),
                          ),
                          const SizedBox(height: 11),
                          CarrierChip(digits: _digits),
                        ],
                      ),
                    ),
                    const SizedBox(height: ZSpacing.lg),
                    GestureDetector(
                      onTap: () => setState(() => _termsAccepted = !_termsAccepted),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 20,
                            height: 20,
                            margin: const EdgeInsets.only(top: 1),
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: _termsAccepted ? z.teal : z.surface,
                              borderRadius: BorderRadius.circular(6),
                              border: _termsAccepted ? null : Border.all(color: z.line),
                            ),
                            child: _termsAccepted
                                ? Icon(Icons.check, size: 12, color: z.onTeal)
                                : null,
                          ),
                          const SizedBox(width: ZSpacing.sm + 1),
                          Expanded(
                            child: RichText(
                              text: TextSpan(
                                style: ZTypography.metaLabel.copyWith(
                                  color: z.ink60,
                                  fontWeight: FontWeight.w500,
                                  fontSize: 11.5,
                                ),
                                children: [
                                  const TextSpan(text: 'با ورود، '),
                                  TextSpan(
                                    text: 'قوانین و حریم خصوصی',
                                    style: TextStyle(fontWeight: FontWeight.w700, color: z.ink),
                                  ),
                                  const TextSpan(text: ' زنجیر را می‌پذیرم.'),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: ZSpacing.md),
                      Text(_error!, style: ZTypography.metaLabel.copyWith(color: z.coral)),
                    ],
                    const SizedBox(height: ZSpacing.lg),
                    AccentButton(
                      label: _sending ? '...' : 'فرستادن کد',
                      accent: ZAccentColor.ink,
                      onPressed: _canSubmit ? _submit : null,
                    ),
                    const SizedBox(height: ZSpacing.lg),
                    GestureDetector(
                      onTap: _openReferralSheet,
                      child: ZDashedContainer(
                        color: z.line,
                        child: Row(
                          children: [
                            Container(
                              width: 24,
                              height: 28,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: z.amber,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                '۵۰',
                                style: ZTypography.metaLabel.copyWith(
                                  color: z.onAmber,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                            const SizedBox(width: ZSpacing.md),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _referralCode == null ? 'کد دعوت داری؟' : 'کد دعوت: $_referralCode',
                                    style: ZTypography.cardTitle.copyWith(color: z.ink),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'بعد از ورود واردش کن، ۵۰ سکه بگیر',
                                    style: ZTypography.metaLabel.copyWith(color: z.ink60),
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
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                ZSpacing.xxl,
                0,
                ZSpacing.xxl,
                ZSpacing.lg,
              ),
              child: Center(
                child: GestureDetector(
                  onTap: _continueAsGuest,
                  child: Column(
                    children: [
                      Text(
                        'فعلاً مهمان می‌مانم',
                        style: ZTypography.cardTitle.copyWith(color: z.ink60, fontSize: 13),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        'امتیاز مهمان روی این گوشی می‌ماند',
                        style: ZTypography.metaLabel.copyWith(color: z.ink40, fontSize: 11),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _wordmark() {
    const letters = ['ز', 'ن', 'ج', 'ی', 'ر'];
    const accents = [ZAccent.indigo, ZAccent.teal, ZAccent.amber, ZAccent.coral, ZAccent.indigo];
    const rotations = [-5.0, 2.0, -2.0, 4.0, -3.0];
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < letters.length; i++) ...[
          if (i > 0) const SizedBox(width: 5),
          LetterTile(
            letter: letters[i],
            accent: accents[i],
            size: 38,
            height: 48,
            radius: 12,
            fontSize: 24,
            rotation: rotations[i] * 3.14159265 / 180,
          ),
        ],
      ],
    );
  }
}
