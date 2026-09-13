import 'package:flutter/material.dart';
import 'package:wordchain/core/di/injection.dart';
import 'package:wordchain/core/theme/app_spacing.dart';
import 'package:wordchain/core/theme/app_tokens.dart';
import 'package:wordchain/core/theme/app_typography.dart';
import 'package:wordchain/core/widgets/z_buttons.dart';
import 'package:wordchain/features/auth/cubit/auth_cubit.dart';
import 'package:wordchain/features/auth/data/auth_repository.dart';

/// The "کد دعوت داری؟" referral entry point, shared by both places it can be
/// triggered from:
///  - Pre-signup (ZLogin's teaser card, AuthCubit not yet AuthAuthenticated):
///    stashes the code and returns it via Navigator.pop(code) so the caller
///    can forward it into verify-otp — entry point (a), 100-coin bonus.
///  - Post-login (already AuthAuthenticated): redeems it directly against
///    the one-time /referral/redeem endpoint — entry point (b), 50 coins.
/// Branching on auth state at open time means the two entry points can never
/// collide — a session is either authenticated or not when the sheet opens.
class ReferralBottomSheet extends StatefulWidget {
  const ReferralBottomSheet({super.key});

  static Future<String?> show(BuildContext context) {
    return showModalBottomSheet<String?>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => const ReferralBottomSheet(),
    );
  }

  @override
  State<ReferralBottomSheet> createState() => _ReferralBottomSheetState();
}

class _ReferralBottomSheetState extends State<ReferralBottomSheet> {
  final _controller = TextEditingController();
  bool _submitting = false;
  String? _error;

  bool get _authenticated => getIt<AuthCubit>().state is AuthAuthenticated;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final code = _controller.text.trim().toUpperCase();
    if (code.isEmpty) return;

    if (!_authenticated) {
      Navigator.of(context).pop(code);
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final awarded = await getIt<AuthCubit>().redeemReferral(code);
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$awarded سکه به حسابت اضافه شد!')),
      );
    } on AuthException catch (e) {
      setState(() {
        _submitting = false;
        _error = _mapError(e.code);
      });
    } on NetworkException catch (_) {
      setState(() {
        _submitting = false;
        _error = 'خطا در اتصال به اینترنت';
      });
    }
  }

  String _mapError(String code) {
    switch (code) {
      case 'self_referral':
        return 'نمی‌توانی از کد خودت استفاده کنی';
      case 'referral_not_found':
        return 'کد دعوت پیدا نشد';
      case 'referral_already_used':
        return 'قبلاً یک کد دعوت استفاده کرده‌ای';
      default:
        return 'مشکلی پیش آمد، دوباره تلاش کن';
    }
  }

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    return Container(
      decoration: BoxDecoration(
        color: z.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(ZRadius.sheetMax)),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            ZSpacing.xxl,
            ZSpacing.xl,
            ZSpacing.xxl,
            ZSpacing.xxl,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('کد دعوت داری؟', style: ZTypography.screenTitle.copyWith(color: z.ink)),
              const SizedBox(height: 4),
              Text(
                _authenticated
                    ? 'وارد کن و ۵۰ سکه بگیر'
                    : 'با همین کد، حساب تازه‌ات ساخته می‌شود و ۱۰۰ سکهٔ خوش‌آمد می‌گیری',
                style: ZTypography.body.copyWith(color: z.ink60),
              ),
              const SizedBox(height: ZSpacing.xl),
              Container(
                height: 52,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  color: z.paper,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: z.line),
                ),
                child: TextField(
                  controller: _controller,
                  textCapitalization: TextCapitalization.characters,
                  maxLength: 6,
                  textDirection: TextDirection.ltr,
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    counterText: '',
                    isDense: true,
                  ),
                  style: ZTypography.cardTitle.copyWith(color: z.ink, letterSpacing: 2),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: ZSpacing.sm),
                Text(_error!, style: ZTypography.metaLabel.copyWith(color: z.coral)),
              ],
              const SizedBox(height: ZSpacing.xl),
              AccentButton(
                label: _submitting ? '...' : 'ثبت کد',
                accent: ZAccentColor.amber,
                onPressed: _submitting ? null : _submit,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
