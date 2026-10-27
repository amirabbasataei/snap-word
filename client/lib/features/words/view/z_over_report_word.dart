import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:wordchain/core/di/injection.dart';
import 'package:wordchain/core/theme/app_game_metrics.dart';
import 'package:wordchain/core/theme/app_tokens.dart';
import 'package:wordchain/core/theme/app_typography.dart';
import 'package:wordchain/core/widgets/chunky_pill.dart';
import 'package:wordchain/core/widgets/chunky_pressable.dart';
import 'package:wordchain/core/widgets/z_toast.dart';
import 'package:wordchain/features/auth/cubit/auth_cubit.dart';
import 'package:wordchain/features/words/cubit/word_report_cubit.dart';
import 'package:wordchain/features/words/data/word_suggestions_repository.dart';
import 'package:wordchain/features/words/view/flag_word_dialog.dart';
import 'package:wordchain/features/words/view/word_report_texts.dart';

/// On the result screen after a loss for a word the dictionary refused:
/// «کلمهٔ «X» درست بود؟ گزارش بده». One tap reports it (the word is already
/// known); the pill then confirms. Guests can report too.
class ZOverReportWord extends StatelessWidget {
  final String word;

  const ZOverReportWord({super.key, required this.word});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create:
          (_) => WordReportCubit(
            getIt<WordSuggestionsRepository>(),
            source: 'game_over',
          ),
      child: _ReportPill(word: word),
    );
  }
}

class _ReportPill extends StatelessWidget {
  final String word;

  const _ReportPill({required this.word});

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    return BlocConsumer<WordReportCubit, WordReportState>(
      listener: (context, state) {
        if (state.sent) {
          final signedIn = getIt<AuthCubit>().state is AuthAuthenticated;
          ZToast.show(
            context,
            wordSentToast(signedIn: signedIn, already: state.alreadyReported),
            kind: ZToastKind.success,
          );
        } else if (state.status == WordReportStatus.failed) {
          ZToast.show(
            context,
            state.message ?? 'مشکلی پیش آمد، دوباره تلاش کن',
            kind: ZToastKind.error,
          );
        }
      },
      builder: (context, state) {
        final sent = state.sent;
        final label =
            sent
                ? 'گزارش شد؛ ممنون'
                : state.sending
                ? 'در حال ارسال…'
                : '«$word» درست بود؟ گزارش بده';
        return Center(
          child: MediaQuery.withClampedTextScaling(
            maxScaleFactor: 1.3,
            child: ChunkyPressable(
              depth: sent ? 0 : ZGame.depthSm,
              semanticLabel: label,
              onTap:
                  sent || state.sending
                      ? null
                      : () => context.read<WordReportCubit>().suggest(word),
              builder:
                  (context, depth, _) => ZChunkPill(
                    fill: sent ? z.tintTeal : z.surface,
                    depth: depth,
                    height: 40,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: ExcludeSemantics(
                      child: Text(
                        label,
                        maxLines: 1,
                        style: ZTypography.metaLabel.copyWith(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          height: 1,
                          color: sent ? z.teal : z.ink,
                        ),
                      ),
                    ),
                  ),
            ),
          ),
        );
      },
    );
  }
}

/// «کلمه‌ای اشتباه بود؟» under the result of a game with an opponent: opens
/// the dialog to flag a word of the chain.
class ZOverFlagWordLink extends StatelessWidget {
  final List<String> chain;

  const ZOverFlagWordLink({super.key, required this.chain});

  @override
  Widget build(BuildContext context) {
    if (chain.isEmpty) return const SizedBox.shrink();
    final z = context.z;
    return Semantics(
      button: true,
      label: 'گزارش کلمهٔ اشتباه یا نامناسب',
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => showFlagWordDialog(context, chain: chain),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Center(
            child: Text(
              'کلمه‌ای اشتباه یا نامناسب بود؟',
              style: ZTypography.metaLabel.copyWith(
                fontSize: 12.5,
                fontWeight: FontWeight.w800,
                decoration: TextDecoration.underline,
                color: z.ink60,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
