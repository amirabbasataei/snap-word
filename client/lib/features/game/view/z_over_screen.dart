import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:wordchain/core/database/app_database.dart';
import 'package:wordchain/core/di/injection.dart';
import 'package:wordchain/core/services/ad_service.dart';
import 'package:wordchain/core/services/dictionary_service.dart';
import 'package:wordchain/core/services/monetization_service.dart';
import 'package:wordchain/core/services/share_service.dart';
import 'package:wordchain/core/theme/app_spacing.dart';
import 'package:wordchain/core/theme/app_tokens.dart';
import 'package:wordchain/core/theme/app_typography.dart';
import 'package:wordchain/core/utils/avatar_initial.dart';
import 'package:wordchain/core/utils/persian_digits.dart';
import 'package:wordchain/core/widgets/insufficient_coins_dialog.dart';
import 'package:wordchain/core/widgets/z_hud_coin_pill.dart';
import 'package:wordchain/core/widgets/z_toast.dart';
import 'package:wordchain/features/auth/cubit/auth_cubit.dart';
import 'package:wordchain/features/game/bloc/game_bloc.dart';
import 'package:wordchain/features/game/data/game_constants.dart';
import 'package:wordchain/features/game/view/game_screen.dart';
import 'package:wordchain/features/game/view/widgets/z_game_hud.dart';
import 'package:wordchain/features/game/view/widgets/z_game_scaffold.dart';
import 'package:wordchain/features/game/view/widgets/z_game_word.dart';
import 'package:wordchain/features/game/view/widgets/z_over_actions.dart';
import 'package:wordchain/features/game/view/widgets/z_over_cards.dart';
import 'package:wordchain/features/game/view/widgets/z_over_hero.dart';

const _aiLevels = {'ai_easy': 'آسان', 'ai_medium': 'متوسط', 'ai_hard': 'سخت'};

/// ZOver — the result screen for every match type (solo, vs-AI, true
/// multiplayer), in the "A · mascot-led" language (canvas turn 7, `ZOverA`:
/// 7i loss, 7j win). One screen: a loss (or a result not yet decided) shows
/// the broken chain with the sad mascot, the score card and — while the
/// 15 s continue window is open — the continue offer; a win shows the happy
/// mascot, the head-to-head score and the rewards. Once decided, the actions
/// are «play again», home and share.
class ZOverScreen extends StatefulWidget {
  final GameOver state;

  const ZOverScreen({super.key, required this.state});

  @override
  State<ZOverScreen> createState() => _ZOverScreenState();
}

class _ZOverScreenState extends State<ZOverScreen> {
  /// The saved best chain length; null until read (and when it can't be).
  int? _recordChainLength;

  @override
  void initState() {
    super.initState();
    _loadRecord();
  }

  Future<void> _loadRecord() async {
    try {
      final stats = await getIt<StatsDao>().getStats();
      if (mounted) {
        setState(() => _recordChainLength = stats?.bestMatchStreak ?? 0);
      }
    } catch (_) {
      // Best-effort — the record bar just stays hidden.
    }
  }

  void _home(BuildContext context) => context.go('/home');

  void _share(GameOver s) => getIt<ShareService>().shareMatch(
    score: s.score,
    chainLength: s.chainLength,
  );

  /// Same opponent again for solo / vs-AI; multiplayer has no rematch, so it
  /// goes back to the lobby for a new one.
  void _playAgain(BuildContext context, GameOver s) {
    final type = s.opponentType;
    if (type == null) {
      context.pushReplacement('/lobby');
      return;
    }
    context.pushReplacement(
      '/game',
      extra: GameRouteArgs(mode: s.mode, opponentType: type),
    );
  }

  void _handleContinue(BuildContext context, String method) async {
    final monetization = getIt<MonetizationService>();
    if (method == 'ad') {
      final watched = await getIt<AdService>().showRewardedAd();
      if (!context.mounted) return;
      if (!watched) {
        ZToast.show(
          context,
          'تبلیغی در دسترس نیست؛ بعداً دوباره تلاش کن.',
          kind: ZToastKind.error,
        );
        return;
      }
    } else if (method == 'coins') {
      final spent = monetization.spendCoins(GameConstants.continueCostCoins);
      if (!spent) {
        if (context.mounted) {
          showInsufficientCoinsDialog(
            context,
            cost: GameConstants.continueCostCoins,
          );
        }
        return;
      }
    }
    if (context.mounted) {
      context.read<GameBloc>().add(ContinueRequested(method));
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final z = context.z;

    // Daily challenge auto-navigates to /daily once saved (see game_screen's
    // BlocConsumer listener) — this is a brief transitional frame, not a
    // real result screen. ZDailyAfter (Stage 3) owns the real design.
    if (state.mode == 'daily') {
      return Scaffold(
        backgroundColor: z.paper,
        body: Center(
          child:
              state.isSaved
                  ? const SizedBox.shrink()
                  : Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(
                        strokeWidth: 2,
                        color: z.indigo,
                      ),
                      const SizedBox(height: ZSpacing.md),
                      Text(
                        'در حال ذخیره…',
                        style: ZTypography.body.copyWith(color: z.ink60),
                      ),
                    ],
                  ),
        ),
      );
    }

    // True multiplayer's WS-driven GameOver never sets opponentType (see
    // GameBloc._handleWsLossEvent/_handleWsGameOver).
    final isVersus = state.opponentType == null;
    final isAIDuel =
        state.opponentType != null &&
        state.opponentType!.startsWith('ai_') &&
        state.opponentScore > 0;
    final isDuel = isVersus || isAIDuel;
    // Versus: the server decides (a mistake loses regardless of score); null
    // while my own continue window is still open.
    final bool? iWon =
        isVersus
            ? state.iWon
            : (isAIDuel ? state.score > state.opponentScore : null);
    final showContinue =
        !state.isSaved && state.canContinue && state.continueTimeRemaining > 0;

    final auth = getIt<AuthCubit>().state;
    final won = iWon == true;

    return ZGameScaffold(
      header: _Hud(onClose: () => _leave(context, showContinue)),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child:
            won
                ? _WinBody(state: state, auth: auth)
                : _LossBody(
                  state: state,
                  record: _recordChainLength,
                  isDuel: isDuel,
                  isVersus: isVersus,
                  iWon: iWon,
                ),
      ),
      footer: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 18),
        // Buttons keep their canvas height; labels stop growing at 1.3×.
        child: MediaQuery.withClampedTextScaling(
          maxScaleFactor: 1.3,
          child:
              showContinue
                  ? ZOverContinueActions(
                    coinCost: GameConstants.continueCostCoins,
                    secondsLeft: state.continueTimeRemaining,
                    onVideo: () => _handleContinue(context, 'ad'),
                    onCoins: () => _handleContinue(context, 'coins'),
                    onShare: () => _share(state),
                    onDecline:
                        () =>
                            context.read<GameBloc>().add(const AcceptDefeat()),
                  )
                  : ZOverFinalActions(
                    playLabel: isVersus ? 'حریف جدید' : 'بازی دوباره',
                    onPlay:
                        state.isSaved ? () => _playAgain(context, state) : null,
                    onHome: () => _home(context),
                    onShare: () => _share(state),
                    big: won,
                  ),
        ),
      ),
    );
  }

  /// ✕: with the continue offer open it declines it (like the home square),
  /// otherwise it leaves for home.
  void _leave(BuildContext context, bool showContinue) {
    if (showContinue) {
      context.read<GameBloc>().add(const AcceptDefeat());
    } else {
      _home(context);
    }
  }
}

/// Coin balance (signed-in players) on the start side, ✕ on the end side.
class _Hud extends StatelessWidget {
  final VoidCallback onClose;

  const _Hud({required this.onClose});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
      child: SizedBox(
        height: 48,
        child: Row(
          children: [
            BlocBuilder<AuthCubit, AuthState>(
              bloc: getIt<AuthCubit>(),
              builder:
                  (context, auth) =>
                      auth is AuthAuthenticated
                          ? Padding(
                            padding: const EdgeInsetsDirectional.only(start: 7),
                            child: ZHudCoinPill(coins: auth.coins),
                          )
                          : const SizedBox.shrink(),
            ),
            const Spacer(),
            ZGameBackButton(onTap: onClose, close: true, semanticLabel: 'بستن'),
          ],
        ),
      ),
    );
  }
}

String? _longestWord(List<String> chain) =>
    chain.isEmpty ? null : chain.reduce((a, b) => a.length >= b.length ? a : b);

class _LossBody extends StatelessWidget {
  final GameOver state;
  final int? record;
  final bool isDuel;
  final bool isVersus;
  final bool? iWon;

  const _LossBody({
    required this.state,
    required this.record,
    required this.isDuel,
    required this.isVersus,
    required this.iWon,
  });

  String get _title {
    if (iWon == false) return 'باختی!';
    if (state.reason == 'ended_by_user') return 'بازی را پایان دادی';
    return 'زنجیر پاره شد!';
  }

  String _subtitle(String? requiredLetter) {
    switch (state.reason) {
      case 'timeout':
        return requiredLetter != null
            ? 'وقت تموم شد؛ کلمه‌ای با «$requiredLetter» نداشتی.'
            : 'وقت تموم شد.';
      case 'invalid_word':
        final word = state.rejectedWord ?? '';
        return switch (state.rejectionReason) {
          'wrong_letter' => '«$word» با حرف درست شروع نمی‌شد.',
          'already_used' => '«$word» قبلاً استفاده شده بود.',
          'too_short' => '«$word» خیلی کوتاه بود.',
          _ => '«$word» توی فرهنگ لغت نبود.',
        };
      case 'ended_by_user':
        return 'با میل خودت بازی رو تموم کردی.';
      case 'opponent_disconnected':
        return 'حریف از بازی خارج شد.';
      default:
        return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final chain = state.wordChain;
    final requiredLetter =
        chain.isEmpty ? null : DictionaryService.lastLetterOf(chain.last);
    final tail = chain.length > 3 ? chain.sublist(chain.length - 3) : chain;
    final longest = _longestWord(chain);
    final recordKnown = record != null && !isDuel;

    final stats = [
      ZOverStat('طول زنجیر', '${toPersianDigits(state.chainLength)} کلمه'),
      if (longest != null) ZOverStat('بلندترین', longest),
      if (isDuel)
        ZOverStat('امتیاز حریف', toPersianDigits(state.opponentScore)),
      if (state.entryFee > 0)
        ZOverStat(
          'سکه',
          state.coinsNet == 0
              ? 'بدون تغییر'
              : '${state.coinsNet > 0 ? '+' : '−'}${toPersianDigits(state.coinsNet.abs())}',
          ltr: state.coinsNet != 0,
        ),
      // vs-AI chains are shared, but the record is still the one on file.
      if (isDuel && !isVersus && record != null)
        ZOverStat('رکورد تو', '${toPersianDigits(record!)} کلمه'),
    ];

    return Column(
      children: [
        ZOverLossHero(
          title: _title,
          subtitle: _subtitle(requiredLetter),
          tail: tail,
          tailStart: chain.length - tail.length,
          requiredLetter: requiredLetter,
        ),
        ZOverEnter(
          kind: ZOverEnterKind.up,
          delayMs: 600,
          child: Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 8),
            child: ZOverScoreCard(
              score: state.score,
              stats: stats,
              bar:
                  recordKnown && state.chainLength > 0
                      ? ZOverRecordBar(
                        chain: state.chainLength,
                        record:
                            record! < state.chainLength
                                ? state.chainLength
                                : record!,
                      )
                      : null,
            ),
          ),
        ),
      ],
    );
  }
}

class _WinBody extends StatelessWidget {
  final GameOver state;
  final AuthState auth;

  const _WinBody({required this.state, required this.auth});

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    final level = _aiLevels[state.opponentType];
    final longest = _longestWord(state.wordChain);
    final signedIn = auth is AuthAuthenticated;
    final myLetter = avatarInitial(
      auth is AuthAuthenticated ? (auth as AuthAuthenticated).username : null,
    );

    final chips = <(int, Widget)>[
      if (state.entryFee > 0 && state.coinsNet > 0)
        (
          10,
          ZOverChip(
            kind: ZOverChipKind.amber,
            value: '+${toPersianDigits(state.coinsNet)}',
            label: 'سکه · سود این بازی',
          ),
        ),
      // XP is the game's score (GameService.AddXP); guests have no level.
      if (signedIn && state.score > 0)
        (
          10,
          ZOverChip(
            kind: ZOverChipKind.indigo,
            value: '+${toPersianDigits(state.score)}',
            label: 'امتیاز تجربه',
          ),
        ),
      if (longest != null)
        (
          12,
          ZOverChip(
            kind: ZOverChipKind.surface,
            value: longest,
            label: 'بلندترین کلمه',
            valueSpan: zChainWordSpan(
              context,
              word: longest,
              index: 3,
              fontSize: 20,
              color: z.ink,
            ),
          ),
        ),
    ];

    return Column(
      children: [
        const ZOverWinHero(title: 'بردی!'),
        ZOverEnter(
          kind: ZOverEnterKind.up,
          delayMs: 450,
          child: ZOverVersusPill(
            myLetter: myLetter,
            myScore: state.score,
            opponentScore: state.opponentScore,
            opponentLetter: level != null ? null : 'ح',
            myAvatarId: state.myAvatarId,
            opponentAvatarId: state.opponentAvatarId,
            caption:
                level != null ? 'مقابل حریف هوشمند · $level' : 'مقابل حریف',
          ),
        ),
        if (chips.isNotEmpty)
          ZOverEnter(
            kind: ZOverEnterKind.up,
            delayMs: 600,
            child: Padding(
              padding: const EdgeInsets.only(top: 16, bottom: 8),
              child: IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var i = 0; i < chips.length; i++) ...[
                      if (i > 0) const SizedBox(width: 10),
                      Expanded(flex: chips[i].$1, child: chips[i].$2),
                    ],
                  ],
                ),
              ),
            ),
          ),
        const SizedBox(height: 8),
      ],
    );
  }
}
