import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:wordchain/core/di/injection.dart';
import 'package:wordchain/core/theme/app_scene_tokens.dart';
import 'package:wordchain/core/theme/app_tokens.dart';
import 'package:wordchain/core/theme/app_typography.dart';
import 'package:wordchain/core/utils/error_messages.dart';
import 'package:wordchain/core/utils/persian_digits.dart';
import 'package:wordchain/core/widgets/z_dialog.dart';
import 'package:wordchain/core/widgets/z_form_dialog.dart';
import 'package:wordchain/core/widgets/z_mascot.dart';
import 'package:wordchain/features/auth/cubit/auth_cubit.dart';
import 'package:wordchain/features/auth/data/auth_repository.dart';
import 'package:wordchain/features/game/data/game_constants.dart';

/// The "کد دعوت داری؟" referral entry point (canvas `ZDialogs`, 14a), shared
/// by both places it can be triggered from:
///  - Pre-signup (ZLogin's teaser card, AuthCubit not yet AuthAuthenticated):
///    stashes the code and returns it via Navigator.pop(code) so the caller
///    can forward it into verify-otp — entry point (a), 100-coin bonus.
///  - Post-login (already AuthAuthenticated): redeems it directly against
///    the one-time /referral/redeem endpoint — entry point (b), 50 coins.
/// Branching on auth state at open time means the two entry points can never
/// collide — a session is either authenticated or not when the dialog opens.
Future<String?> showReferralDialog(BuildContext context) =>
    showZDialog<String>(context, builder: (_) => const ReferralDialog());

class ReferralDialog extends StatefulWidget {
  const ReferralDialog({super.key});

  @override
  State<ReferralDialog> createState() => _ReferralDialogState();
}

class _ReferralDialogState extends State<ReferralDialog> {
  // Codes are 6 characters (`referral_code VARCHAR(6)`).
  static const _codeLength = 6;

  final _controller = TextEditingController();
  bool _submitting = false;
  int? _awarded;
  String? _error;

  bool get _authenticated => getIt<AuthCubit>().state is AuthAuthenticated;
  bool get _filled => _controller.text.trim().isNotEmpty;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final code = _controller.text.trim().toUpperCase();
    if (code.isEmpty || _submitting) return;

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
      setState(() {
        _submitting = false;
        _awarded = awarded;
      });
    } on AuthException catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = errorMessageFor(e.code);
      });
    } on NetworkException catch (_) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = networkErrorMessage;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    final awarded = _awarded;
    final done = awarded != null;
    final bad = _error != null;
    // What the server actually pays: the new account's signup gift or the
    // post-login redeem, and always +50 to the inviter.
    final mine =
        _authenticated
            ? GameConstants.referralRedeemCoins
            : GameConstants.referralSignupCoins;
    return ZFormDialog(
      mood:
          done
              ? ZMascotMood.happy
              : bad
              ? ZMascotMood.surprised
              : ZMascotMood.idle,
      pillText: done ? 'هدیه اضافه شد' : 'هدیهٔ دعوت',
      pillAccent: done ? ZDialogAccent.teal : ZDialogAccent.amber,
      title: done ? 'خوش اومدی به زنجیر!' : 'کد دعوت داری؟',
      body:
          done
              // The inviter's +50 is a claimable inbox reward, not instant coins.
              ? 'سکه‌ها به حساب تو اضافه شد و هدیهٔ دوستت هم ثبت شد.'
              : 'اگه دوستی دعوتت کرده، کدش رو بزن تا هر دوتون سکه بگیرید.',
      panel: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: ZRewardChip(
                  amount: '+${toPersianDigits(mine)} سکه',
                  caption: 'برای تو',
                  dot: z.amber,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ZRewardChip(
                  amount:
                      '+${toPersianDigits(GameConstants.referralInviterCoins)} سکه',
                  caption: 'برای دوستت',
                  dot: z.coral,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ZDialogField(
            border:
                done
                    ? z.teal
                    : bad
                    ? z.coral
                    : null,
            child: TextField(
              controller: _controller,
              autofocus: true,
              readOnly: done,
              textAlign: TextAlign.center,
              textDirection: TextDirection.ltr,
              textCapitalization: TextCapitalization.characters,
              maxLength: _codeLength,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp('[A-Za-z0-9]')),
              ],
              onChanged: (_) => setState(() => _error = null),
              onSubmitted: (_) => _submit(),
              cursorColor: z.amber,
              style: ZTypography.cardTitle.copyWith(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: z.ink,
              ),
              decoration: InputDecoration(
                isDense: true,
                filled: false,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                contentPadding: EdgeInsets.zero,
                counterText: '',
                hintText: 'کد دعوت را وارد کن',
                hintStyle: ZTypography.cardTitle.copyWith(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: z.ink60,
                ),
              ),
            ),
          ),
          if (bad) ...[
            const SizedBox(height: 8),
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: ZTypography.metaLabel.copyWith(
                fontSize: 12.5,
                fontWeight: FontWeight.w800,
                height: 1.5,
                color: context.zs.coralInk,
              ),
            ),
          ],
        ],
      ),
      primaryLabel:
          done
              ? 'بزن بریم'
              : _submitting
              ? '...'
              : 'ثبت کد',
      primaryAccent: done ? ZDialogAccent.teal : ZDialogAccent.amber,
      onPrimary:
          done
              ? () => Navigator.of(context).pop()
              : _filled && !_submitting
              ? _submit
              : null,
      secondaryLabel: done ? null : 'کد ندارم',
      onSecondary: () => Navigator.of(context).pop(),
    );
  }
}
