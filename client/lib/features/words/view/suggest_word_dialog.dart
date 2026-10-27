import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:wordchain/core/di/injection.dart';
import 'package:wordchain/core/services/dictionary_service.dart';
import 'package:wordchain/core/theme/app_scene_tokens.dart';
import 'package:wordchain/core/theme/app_tokens.dart';
import 'package:wordchain/core/theme/app_typography.dart';
import 'package:wordchain/core/utils/persian_digits.dart';
import 'package:wordchain/core/widgets/z_dialog.dart';
import 'package:wordchain/core/widgets/z_form_dialog.dart';
import 'package:wordchain/core/widgets/z_mascot.dart';
import 'package:wordchain/features/auth/cubit/auth_cubit.dart';
import 'package:wordchain/features/game/data/game_constants.dart';
import 'package:wordchain/features/words/cubit/word_report_cubit.dart';
import 'package:wordchain/features/words/data/word_suggestions_repository.dart';
import 'package:wordchain/features/words/view/word_report_texts.dart';

/// «پیشنهاد کلمه»: the player types a valid word the game did not know. It is
/// reviewed by an admin and, once approved, added for everyone.
Future<void> showSuggestWordDialog(
  BuildContext context, {
  String source = 'profile',
}) => showZDialog<void>(
  context,
  builder:
      (_) => BlocProvider(
        create:
            (_) => WordReportCubit(
              getIt<WordSuggestionsRepository>(),
              source: source,
            ),
        child: const SuggestWordDialog(),
      ),
);

class SuggestWordDialog extends StatefulWidget {
  const SuggestWordDialog({super.key});

  @override
  State<SuggestWordDialog> createState() => _SuggestWordDialogState();
}

class _SuggestWordDialogState extends State<SuggestWordDialog> {
  static const _maxLength = 30; // mirrors config.WordSuggestMaxRunes
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String get _word => _controller.text.trim();

  /// Why the typed word cannot be sent, or null when it can (also null for an
  /// empty field — nothing to complain about yet).
  String? get _problem {
    final word = _word;
    if (word.isEmpty) return null;
    if (word.runes.length < GameConstants.minWordLength) {
      return 'حداقل ${toPersianDigits(GameConstants.minWordLength)} حرف';
    }
    if (!DictionaryService.hasValidChars(word)) {
      return 'فقط حرف فارسی، بدون فاصله و عدد';
    }
    if (getIt<DictionaryService>().isValid(word)) {
      return 'این کلمه از قبل در بازی هست';
    }
    return null;
  }

  bool get _canSend => _word.isNotEmpty && _problem == null;

  void _send(WordReportCubit cubit) {
    if (_canSend) cubit.suggest(_word);
  }

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    final cubit = context.read<WordReportCubit>();
    final signedIn = getIt<AuthCubit>().state is AuthAuthenticated;
    return BlocBuilder<WordReportCubit, WordReportState>(
      builder: (context, state) {
        if (state.sent) {
          return ZFormDialog(
            mood: ZMascotMood.happy,
            pillText: 'ارسال شد',
            pillAccent: ZDialogAccent.teal,
            title: 'ممنون از کمکت!',
            body: wordSentMessage(
              signedIn: signedIn,
              already: state.alreadyReported,
            ),
            primaryLabel: 'باشه',
            primaryAccent: ZDialogAccent.teal,
            onPrimary: () => Navigator.of(context).pop(),
            secondaryLabel: 'کلمهٔ دیگر',
            onSecondary: () {
              _controller.clear();
              cubit.reset();
            },
          );
        }
        final problem = _problem ?? state.message;
        return ZFormDialog(
          mood: problem != null ? ZMascotMood.surprised : ZMascotMood.thinking,
          pillText: 'پیشنهاد کلمه',
          pillAccent: ZDialogAccent.indigo,
          title: 'کلمه‌ای کم داریم؟',
          body:
              'کلمهٔ درستی را که بازی نپذیرفت بنویس. بعد از بررسی به همه اضافه می‌شود'
              '${signedIn ? ' و ${toPersianDigits(GameConstants.wordSuggestionCoins)} سکه هدیه می‌گیری.' : '.'}',
          panel: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ZDialogField(
                border: problem != null ? z.coral : null,
                child: TextField(
                  controller: _controller,
                  autofocus: true,
                  enabled: !state.sending,
                  maxLength: _maxLength,
                  textAlign: TextAlign.center,
                  onChanged: (_) {
                    setState(() {});
                    if (state.status == WordReportStatus.failed) cubit.reset();
                  },
                  onSubmitted: (_) => _send(cubit),
                  cursorColor: z.indigo,
                  style: ZTypography.cardTitle.copyWith(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: z.ink,
                  ),
                  decoration: InputDecoration(
                    isDense: true,
                    filled: false,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    disabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    contentPadding: EdgeInsets.zero,
                    counterText: '',
                    hintText: 'کلمه',
                    hintStyle: TextStyle(color: z.ink40),
                  ),
                ),
              ),
              if (problem != null) ...[
                const SizedBox(height: 8),
                Text(
                  problem,
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
          primaryLabel: state.sending ? '...' : 'ارسال',
          primaryAccent: ZDialogAccent.indigo,
          onPrimary: _canSend && !state.sending ? () => _send(cubit) : null,
          secondaryLabel: 'انصراف',
          onSecondary: () => Navigator.of(context).pop(),
        );
      },
    );
  }
}
