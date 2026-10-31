import 'package:flutter/material.dart';
import 'package:wordchain/core/di/injection.dart';
import 'package:wordchain/core/widgets/z_toast.dart';
import 'package:wordchain/features/auth/cubit/auth_cubit.dart';
import 'package:wordchain/features/words/cubit/word_report_cubit.dart';
import 'package:wordchain/features/words/data/word_suggestions_repository.dart';
import 'package:wordchain/features/words/view/word_report_texts.dart';

/// Longer than the default: the player has to read the question mid-game and
/// decide.
const _offerDuration = Duration(seconds: 7);

/// Modes with lives (solo, Daily Challenge) keep playing after a mistake, so
/// there is no result screen to report from. When the refused word cost a
/// life, ask in a toast: «X» تو لغات ما نبود، می‌خوای گزارش کنی؟ — the button
/// sends the word as a missing-word suggestion.
void showMissingWordToast(BuildContext context, String word) {
  // The root overlay outlives the game screen (the Daily Challenge leaves for
  // its result page right after the last life), so the report can finish and
  // confirm after navigation.
  final overlay = Overlay.of(context, rootOverlay: true);
  ZToast.showOn(
    overlay,
    '«$word» تو لغات ما نبود، می‌خوای گزارش کنی؟',
    kind: ZToastKind.info,
    duration: _offerDuration,
    actionLabel: 'گزارش بده',
    onAction: () => _report(overlay, word),
  );
}

Future<void> _report(OverlayState overlay, String word) async {
  final cubit = WordReportCubit(
    getIt<WordSuggestionsRepository>(),
    source: 'life_lost',
  );
  await cubit.suggest(word);
  final state = cubit.state;
  await cubit.close();
  if (!overlay.mounted) return;
  if (state.sent) {
    final signedIn = getIt<AuthCubit>().state is AuthAuthenticated;
    ZToast.showOn(
      overlay,
      wordSentToast(signedIn: signedIn, already: state.alreadyReported),
      kind: ZToastKind.success,
    );
  } else {
    ZToast.showOn(
      overlay,
      state.message ?? 'مشکلی پیش آمد، دوباره تلاش کن',
      kind: ZToastKind.error,
    );
  }
}
