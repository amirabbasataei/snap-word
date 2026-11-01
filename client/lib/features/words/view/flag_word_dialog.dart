import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:wordchain/core/di/injection.dart';
import 'package:wordchain/core/theme/app_scene_tokens.dart';
import 'package:wordchain/core/theme/app_tokens.dart';
import 'package:wordchain/core/theme/app_typography.dart';
import 'package:wordchain/core/widgets/z_dialog.dart';
import 'package:wordchain/core/widgets/z_form_dialog.dart';
import 'package:wordchain/core/widgets/z_mascot.dart';
import 'package:wordchain/features/auth/cubit/auth_cubit.dart';
import 'package:wordchain/features/words/cubit/word_report_cubit.dart';
import 'package:wordchain/features/words/data/word_suggestions_repository.dart';

/// «کلمه‌ای اشتباه بود؟»: the player picks a word of the finished chain that
/// should not be in the dictionary (not a real word, or inappropriate) and
/// says why. An admin decides; nothing is removed automatically.
Future<void> showFlagWordDialog(
  BuildContext context, {
  required List<String> chain,
}) => showZDialog<void>(
  context,
  builder:
      (_) => BlocProvider(
        create:
            (_) => WordReportCubit(
              getIt<WordSuggestionsRepository>(),
              source: 'chain',
            ),
        child: FlagWordDialog(chain: chain),
      ),
);

class FlagWordDialog extends StatefulWidget {
  final List<String> chain;

  const FlagWordDialog({super.key, required this.chain});

  @override
  State<FlagWordDialog> createState() => _FlagWordDialogState();
}

class _FlagWordDialogState extends State<FlagWordDialog> {
  String? _word;
  WordFlagReason? _reason;

  /// Each word once, newest first (the recent words are the ones remembered).
  late final List<String> _words = widget.chain.reversed.toSet().toList();

  bool get _canSend => _word != null && _reason != null;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<WordReportCubit>();
    final signedIn = getIt<AuthCubit>().state is AuthAuthenticated;
    return BlocBuilder<WordReportCubit, WordReportState>(
      builder: (context, state) {
        if (state.sent) {
          return ZFormDialog(
            mood: ZMascotMood.happy,
            pillText: 'ارسال شد',
            pillAccent: ZDialogAccent.teal,
            title: 'ممنون از گزارشت',
            body:
                state.alreadyReported
                    ? 'این کلمه را قبلاً گزارش کرده بودی.'
                    : 'کلمه بررسی می‌شود؛ تصمیم با تیم زنجیر است.',
            primaryLabel: 'باشه',
            primaryAccent: ZDialogAccent.teal,
            onPrimary: () => Navigator.of(context).pop(),
          );
        }
        return ZFormDialog(
          mood:
              state.status == WordReportStatus.failed
                  ? ZMascotMood.surprised
                  : ZMascotMood.thinking,
          pillText: 'گزارش کلمه',
          pillAccent: ZDialogAccent.coral,
          title: 'کدام کلمه مشکل داشت؟',
          body:
              'کلمه‌ای که واقعاً وجود ندارد یا نامناسب است را انتخاب کن.'
              '${signedIn ? '' : ' (برای گزارش لازم نیست وارد حساب باشی.)'}',
          panel: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 150),
                child: SingleChildScrollView(
                  child: Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final w in _words)
                        _Choice(
                          label: w,
                          selected: w == _word,
                          onTap:
                              state.sending
                                  ? null
                                  : () => setState(() => _word = w),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Divider(height: 1, thickness: 2, color: context.zs.outline),
              const SizedBox(height: 10),
              Text(
                'مشکل کلمه چیست؟',
                textAlign: TextAlign.center,
                style: ZTypography.metaLabel.copyWith(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                  color: context.z.ink60,
                ),
              ),
              const SizedBox(height: 8),
              for (final r in WordFlagReason.values) ...[
                _ReasonOption(
                  label: r.label,
                  selected: r == _reason,
                  onTap:
                      state.sending ? null : () => setState(() => _reason = r),
                ),
                if (r != WordFlagReason.values.last) const SizedBox(height: 6),
              ],
              if (state.message != null) ...[
                const SizedBox(height: 8),
                Text(
                  state.message!,
                  textAlign: TextAlign.center,
                  style: ZTypography.metaLabel.copyWith(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                    color: context.zs.coralInk,
                  ),
                ),
              ],
            ],
          ),
          primaryLabel: state.sending ? '...' : 'ارسال گزارش',
          primaryAccent: ZDialogAccent.coral,
          onPrimary:
              _canSend && !state.sending
                  ? () => cubit.flag(_word!, _reason!)
                  : null,
          secondaryLabel: 'انصراف',
          onSecondary: () => Navigator.of(context).pop(),
        );
      },
    );
  }
}

/// A reason row: a radio mark + label in a rounded rectangle, deliberately
/// unlike the pill [_Choice] used for the words above it.
class _ReasonOption extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback? onTap;

  const _ReasonOption({
    required this.label,
    required this.selected,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    final fg = selected ? z.onIndigo : z.ink;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: selected ? z.indigo : z.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: context.zs.outline, width: 2),
          ),
          child: Row(
            children: [
              Container(
                width: 20,
                height: 20,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: selected ? z.onIndigo : Colors.transparent,
                  border: Border.all(
                    color: selected ? z.onIndigo : context.zs.outline,
                    width: 2,
                  ),
                ),
                child:
                    selected
                        ? Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: z.indigo,
                          ),
                        )
                        : null,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  style: ZTypography.metaLabel.copyWith(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    height: 1,
                    color: fg,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Choice extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback? onTap;

  const _Choice({required this.label, required this.selected, this.onTap});

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? z.coral : z.surface,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: context.zs.outline, width: 2),
          ),
          child: Text(
            label,
            style: ZTypography.metaLabel.copyWith(
              fontSize: 13.5,
              fontWeight: FontWeight.w800,
              height: 1,
              color: selected ? z.onCoral : z.ink,
            ),
          ),
        ),
      ),
    );
  }
}
