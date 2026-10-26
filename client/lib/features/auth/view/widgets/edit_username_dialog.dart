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

/// Dialog for changing the signed-in user's username (canvas `ZDialogs`, 14b).
Future<void> showEditUsernameDialog(BuildContext context) =>
    showZDialog<void>(context, builder: (_) => const EditUsernameDialog());

class EditUsernameDialog extends StatefulWidget {
  const EditUsernameDialog({super.key});

  @override
  State<EditUsernameDialog> createState() => _EditUsernameDialogState();
}

class _EditUsernameDialogState extends State<EditUsernameDialog> {
  // Mirrors the server (`AuthService.UpdateUsername`): 3–20 letters/digits/_.
  static const _maxLength = 20;
  static const _minLength = 3;
  static final _charsRe = RegExp(r'^[\p{L}\p{N}_]+$', unicode: true);

  late final TextEditingController _controller;
  late final String _current;
  bool _submitting = false;
  bool _saved = false;
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

  String get _name => _controller.text.trim();
  bool get _lengthOk =>
      _name.runes.length >= _minLength && _name.runes.length <= _maxLength;
  bool get _charsOk => _name.isNotEmpty && _charsRe.hasMatch(_name);
  bool get _changed => _name != _current;
  bool get _canSave => _changed && _lengthOk && _charsOk && !_submitting;

  Future<void> _submit() async {
    if (!_canSave) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await getIt<AuthCubit>().updateUsername(_name);
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _saved = true;
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
    final charsBad = !_saved && _changed && _name.isNotEmpty && !_charsOk;
    final message = _error ?? (charsBad ? 'فقط حرف، عدد و _ مجاز است' : null);
    final bad = message != null;
    return ZFormDialog(
      mood:
          _saved
              ? ZMascotMood.happy
              : bad
              ? ZMascotMood.surprised
              : ZMascotMood.thinking,
      pillText: _saved ? 'ذخیره شد' : 'پروفایل',
      pillAccent: _saved ? ZDialogAccent.teal : ZDialogAccent.indigo,
      title: _saved ? 'نام تازه‌ات ثبت شد!' : 'نام کاربری',
      body:
          _saved
              ? 'دوستات از این به بعد تو رو با این نام می‌بینن.'
              : 'این نام توی جدول امتیاز و بازی‌های آنلاین دیده می‌شه.',
      panel: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ZDialogField(
            border:
                _saved
                    ? z.teal
                    : bad
                    ? z.coral
                    : null,
            child: Row(
              textDirection: TextDirection.ltr,
              children: [
                _AtBadge(),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _controller,
                    autofocus: true,
                    readOnly: _saved,
                    textDirection: TextDirection.ltr,
                    textAlign: TextAlign.left,
                    maxLength: _maxLength,
                    inputFormatters: [
                      FilteringTextInputFormatter.deny(RegExp(r'\s')),
                    ],
                    onChanged: (_) => setState(() => _error = null),
                    onSubmitted: (_) => _submit(),
                    cursorColor: z.indigo,
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
                      hintText: 'username',
                      hintStyle: TextStyle(color: z.ink40),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  '${toPersianDigits(_name.runes.length)}/${toPersianDigits(_maxLength)}',
                  textDirection: TextDirection.rtl,
                  style: ZTypography.metaLabel.copyWith(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: z.ink60,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 6,
            runSpacing: 6,
            children: [
              _RuleChip(
                label:
                    '${toPersianDigits(_minLength)} تا ${toPersianDigits(_maxLength)} نویسه',
                pass: _saved || _lengthOk,
              ),
              _RuleChip(label: 'حرف، عدد و _', pass: _saved || _charsOk),
            ],
          ),
          if (bad) ...[
            const SizedBox(height: 8),
            Text(
              message,
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
          _saved
              ? 'باشه'
              : _submitting
              ? '...'
              : 'ذخیره',
      primaryAccent: _saved ? ZDialogAccent.teal : ZDialogAccent.indigo,
      onPrimary:
          _saved
              ? () => Navigator.of(context).pop()
              : _canSave
              ? _submit
              : null,
      secondaryLabel: _saved ? null : 'انصراف',
      onSecondary: () => Navigator.of(context).pop(),
    );
  }
}

class _AtBadge extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final z = context.z;
    return Container(
      width: 30,
      height: 30,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: z.indigo,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: context.zs.outline, width: 2.5),
      ),
      child: Text(
        '@',
        style: ZTypography.button.copyWith(
          fontSize: 16,
          height: 1,
          color: z.onIndigo,
        ),
      ),
    );
  }
}

class _RuleChip extends StatelessWidget {
  final String label;
  final bool pass;

  const _RuleChip({required this.label, required this.pass});

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: pass ? z.teal : z.surface,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: context.zs.outline, width: 2),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: ZTypography.metaLabel.copyWith(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              height: 1,
              color: pass ? z.onTeal : z.ink60,
            ),
          ),
        ],
      ),
    );
  }
}
