import 'package:flutter/material.dart';
import 'package:wordchain/core/di/injection.dart';
import 'package:wordchain/core/theme/app_spacing.dart';
import 'package:wordchain/core/theme/app_tokens.dart';
import 'package:wordchain/core/theme/app_typography.dart';
import 'package:wordchain/core/widgets/z_buttons.dart';
import 'package:wordchain/core/widgets/z_toast.dart';
import 'package:wordchain/features/auth/cubit/auth_cubit.dart';
import 'package:wordchain/features/auth/data/auth_repository.dart';

/// Bottom sheet for changing the signed-in user's username.
class EditUsernameSheet extends StatefulWidget {
  const EditUsernameSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => const EditUsernameSheet(),
    );
  }

  @override
  State<EditUsernameSheet> createState() => _EditUsernameSheetState();
}

class _EditUsernameSheetState extends State<EditUsernameSheet> {
  static final _validRe = RegExp(r'^[\p{L}\p{N}_]{3,20}$', unicode: true);

  late final TextEditingController _controller;
  late final String _current;
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final auth = getIt<AuthCubit>().state;
    _current = auth is AuthAuthenticated ? auth.username : '';
    _controller = TextEditingController(text: _current);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final name = _controller.text.trim();
    if (name == _current) {
      Navigator.of(context).pop();
      return;
    }
    if (!_validRe.hasMatch(name)) {
      setState(() => _error = _mapError('invalid_username'));
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await getIt<AuthCubit>().updateUsername(name);
      if (!mounted) return;
      Navigator.of(context).pop();
      ZToast.show(context, 'نام کاربری تغییر کرد', kind: ZToastKind.success);
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
      case 'invalid_username':
        return 'نام کاربری باید ۳ تا ۲۰ حرف، عدد یا _ باشد';
      case 'username_taken':
        return 'این نام کاربری قبلاً گرفته شده';
      default:
        return 'مشکلی پیش آمد، دوباره تلاش کن';
    }
  }

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        decoration: BoxDecoration(
          color: z.surface,
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(ZRadius.sheetMax),
          ),
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
                Text(
                  'ویرایش نام کاربری',
                  style: ZTypography.screenTitle.copyWith(color: z.ink),
                ),
                const SizedBox(height: 4),
                Text(
                  'دوستانت با همین نام پیدایت می‌کنند',
                  style: ZTypography.body.copyWith(color: z.ink60),
                ),
                const SizedBox(height: ZSpacing.xl),
                Container(
                  height: 52,
                  alignment: AlignmentDirectional.centerStart,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  decoration: BoxDecoration(
                    color: z.paper,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: z.line),
                  ),
                  child: TextField(
                    controller: _controller,
                    autofocus: true,
                    maxLength: 20,
                    onSubmitted: (_) => _submit(),
                    decoration: const InputDecoration(
                      border: InputBorder.none,
                      counterText: '',
                      isDense: true,
                    ),
                    style: ZTypography.cardTitle.copyWith(color: z.ink),
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: ZSpacing.sm),
                  Text(
                    _error!,
                    style: ZTypography.metaLabel.copyWith(color: z.coral),
                  ),
                ],
                const SizedBox(height: ZSpacing.xl),
                AccentButton(
                  label: _submitting ? '...' : 'ذخیره',
                  accent: ZAccentColor.amber,
                  onPressed: _submitting ? null : _submit,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
