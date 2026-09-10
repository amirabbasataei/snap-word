import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:wordchain/core/database/app_database.dart';
import 'package:wordchain/core/di/injection.dart';
import 'package:wordchain/core/services/monetization_service.dart';
import 'package:wordchain/core/services/share_service.dart';
import 'package:wordchain/core/theme/app_elevation.dart';
import 'package:wordchain/core/theme/app_spacing.dart';
import 'package:wordchain/core/theme/app_tokens.dart';
import 'package:wordchain/core/theme/app_typography.dart';
import 'package:wordchain/core/utils/persian_digits.dart';
import 'package:wordchain/core/widgets/letter_tile.dart';
import 'package:wordchain/core/widgets/solid_card.dart';
import 'package:wordchain/core/widgets/z_buttons.dart';
import 'package:wordchain/features/game/bloc/game_bloc.dart';
import 'package:wordchain/features/game/data/game_constants.dart';

/// ZOver — the unified loss/continue/results screen for solo and vs-AI
/// matches (true multiplayer keeps the legacy `ContinuePrompt` +
/// `_GameOverScreen` pair; see game_screen.dart's dispatch and
/// REDESIGN_PLAN.md §3). The canvas merges what used to be two separate
/// screens (continue offer, then final results) into one: the score/chain
/// summary is always shown, with continue actions layered on top only
/// while the 15s continue window is open.
class ZOverScreen extends StatefulWidget {
  final GameOver state;

  const ZOverScreen({super.key, required this.state});

  @override
  State<ZOverScreen> createState() => _ZOverScreenState();
}

class _ZOverScreenState extends State<ZOverScreen> {
  int _recordChainLength = 0;

  @override
  void initState() {
    super.initState();
    _loadRecord();
  }

  Future<void> _loadRecord() async {
    try {
      final stats = await getIt<StatsDao>().getStats();
      if (mounted) setState(() => _recordChainLength = stats?.bestMatchStreak ?? 0);
    } catch (_) {
      // Best-effort — near-miss/record lines just stay hidden.
    }
  }

  void _navigateHome(BuildContext context) async {
    await getIt<MonetizationService>().showInterstitialAd();
    if (context.mounted) context.go('/home');
  }

  void _handleContinue(BuildContext context, String method) async {
    final monetization = getIt<MonetizationService>();
    if (method == 'ad') {
      final watched = await monetization.showRewardedAd();
      if (!watched || !context.mounted) return;
    } else if (method == 'coins') {
      final spent = monetization.spendCoins(GameConstants.continueCostCoins);
      if (!spent) {
        if (context.mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(const SnackBar(content: Text('سکه کافی نداری.')));
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
          child: state.isSaved
              ? const SizedBox.shrink()
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(strokeWidth: 2, color: z.indigo),
                    const SizedBox(height: ZSpacing.md),
                    Text('در حال ذخیره…', style: ZTypography.body.copyWith(color: z.ink60)),
                  ],
                ),
        ),
      );
    }

    final isDuel = state.opponentType != null && state.opponentType!.startsWith('ai_') && state.opponentScore > 0;
    final iWon = isDuel && state.score > state.opponentScore;
    final showContinue = !state.isSaved && state.canContinue && state.continueTimeRemaining > 0;

    return Scaffold(
      backgroundColor: z.paper,
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            children: [
              _Hero(state: state, isDuel: isDuel, iWon: iWon),
              Padding(
                padding: const EdgeInsets.all(ZSpacing.xxl),
                child: Column(
                  children: [
                    _ScoreCard(state: state, recordChainLength: _recordChainLength),
                    const SizedBox(height: ZSpacing.lg),
                    if (!isDuel && _recordChainLength > state.chainLength)
                      _NearMissBar(gap: _recordChainLength - state.chainLength),
                    if (!isDuel && state.chainLength > 0 && _recordChainLength <= state.chainLength) ...[
                      const SizedBox(height: ZSpacing.lg),
                      _NewRecordBanner(),
                    ],
                    const SizedBox(height: ZSpacing.lg),
                    if (state.wordChain.isNotEmpty) _ChainTail(state: state),
                    const SizedBox(height: ZSpacing.xl),
                    if (showContinue)
                      _ContinueActions(
                        state: state,
                        onContinue: (m) => _handleContinue(context, m),
                        onAcceptDefeat: () => context.read<GameBloc>().add(const AcceptDefeat()),
                      )
                    else
                      _FinalActions(
                        state: state,
                        onHome: () => _navigateHome(context),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Hero extends StatelessWidget {
  final GameOver state;
  final bool isDuel;
  final bool iWon;

  const _Hero({required this.state, required this.isDuel, required this.iWon});

  String get _title {
    if (isDuel) return iWon ? 'بردی! 🏆' : 'باختی 😞';
    if (state.reason == 'ended_by_user') return 'بازی را پایان دادی';
    return 'زنجیر پاره شد!';
  }

  String get _subtitle {
    final requiredLetter =
        state.wordChain.isNotEmpty ? state.wordChain.last[state.wordChain.last.length - 1] : null;
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
      case 'time_limit':
        return 'زمان کل بازی تموم شد.';
      case 'opponent_disconnected':
        return 'حریف از بازی خارج شد.';
      default:
        return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    final requiredLetter =
        state.wordChain.isNotEmpty ? state.wordChain.last[state.wordChain.last.length - 1] : '؟';
    final lastFirstLetter = state.wordChain.isNotEmpty ? state.wordChain.last[0] : '؟';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(ZSpacing.xxl, ZSpacing.xxxl, ZSpacing.xxl, ZSpacing.xxxl),
      decoration: BoxDecoration(
        color: z.inkSurface,
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(ZRadius.sheetMax)),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Transform.translate(
                offset: const Offset(0, 4),
                child: LetterTile(letter: requiredLetter, size: 42, height: 50, accent: ZAccent.coral, rotation: -0.12),
              ),
              const SizedBox(width: ZSpacing.sm),
              LetterTile(letter: lastFirstLetter, size: 42, height: 50, accent: ZAccent.amber, rotation: 0.07),
              const SizedBox(width: ZSpacing.sm),
              Transform.translate(
                offset: const Offset(0, 6),
                child: const LetterTile(letter: '؟', size: 42, height: 50, accent: ZAccent.indigo, rotation: -0.05),
              ),
            ],
          ),
          const SizedBox(height: ZSpacing.lg),
          Text(
            _title,
            textAlign: TextAlign.center,
            style: ZTypography.screenTitle.copyWith(color: z.onInkSurface, fontSize: 27),
          ),
          if (_subtitle.isNotEmpty) ...[
            const SizedBox(height: ZSpacing.sm),
            Text(
              _subtitle,
              textAlign: TextAlign.center,
              style: ZTypography.body.copyWith(color: z.onInkSurfaceSoft),
            ),
          ],
        ],
      ),
    );
  }
}

class _ScoreCard extends StatelessWidget {
  final GameOver state;
  final int recordChainLength;

  const _ScoreCard({required this.state, required this.recordChainLength});

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    final longestWord =
        state.wordChain.isEmpty ? null : state.wordChain.reduce((a, b) => a.length >= b.length ? a : b);

    return SolidCard(
      elevated: false,
      radius: ZRadius.sheetMin,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('امتیاز این دست', style: ZTypography.metaLabel.copyWith(color: z.ink40, fontSize: 11)),
              const SizedBox(height: 5),
              Text(toPersianDigits(state.score),
                  style: ZTypography.display.copyWith(color: z.ink, fontSize: 40)),
            ],
          ),
          const Spacer(),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              _StatLine(label: 'طول زنجیر', value: '${toPersianDigits(state.chainLength)} کلمه'),
              if (longestWord != null) _StatLine(label: 'بلندترین کلمه', value: longestWord),
              _StatLine(
                label: 'رکورد تو',
                value: '${toPersianDigits(recordChainLength)} کلمه',
                valueColor: z.teal,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatLine extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;

  const _StatLine({required this.label, required this.value, this.valueColor});

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: RichText(
        textAlign: TextAlign.end,
        text: TextSpan(
          style: ZTypography.metaLabel.copyWith(color: z.ink60, fontSize: 11.5),
          children: [
            TextSpan(text: '$label: '),
            TextSpan(
              text: value,
              style: TextStyle(color: valueColor ?? z.ink, fontWeight: FontWeight.w800),
            ),
          ],
        ),
      ),
    );
  }
}

class _NearMissBar extends StatelessWidget {
  final int gap;

  const _NearMissBar({required this.gap});

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    return SolidCard(
      elevated: false,
      radius: ZRadius.cardMin,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: z.amber, borderRadius: BorderRadius.circular(9)),
            child: Text(toPersianDigits(gap),
                style: ZTypography.cardTitle.copyWith(color: z.onAmber, fontSize: 14)),
          ),
          const SizedBox(width: ZSpacing.md),
          Expanded(
            child: Text(
              '${toPersianDigits(gap)} کلمهٔ دیگر تا شکستن رکوردت مانده بود.',
              style: ZTypography.body.copyWith(color: z.ink60, fontWeight: FontWeight.w600, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}

class _NewRecordBanner extends StatelessWidget {
  const _NewRecordBanner();

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(color: z.tintTeal, borderRadius: BorderRadius.circular(ZRadius.cardMin)),
      child: Text(
        'رکورد جدید! 🎉',
        textAlign: TextAlign.center,
        style: ZTypography.cardTitle.copyWith(color: z.teal, fontSize: 13),
      ),
    );
  }
}

class _ChainTail extends StatelessWidget {
  final GameOver state;

  const _ChainTail({required this.state});

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    final chain = state.wordChain;
    final tail = chain.length > 4 ? chain.sublist(chain.length - 4) : chain;
    final requiredLetter = chain.last[chain.last.length - 1];
    final failChip = state.rejectedWord ?? '$requiredLetter ؟';

    return SolidCard(
      elevated: false,
      radius: ZRadius.cardMin,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('آخر زنجیر', style: ZTypography.metaLabel.copyWith(color: z.ink40, fontSize: 11)),
          const SizedBox(height: ZSpacing.sm),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final w in tail)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
                  decoration: BoxDecoration(color: z.paper, borderRadius: BorderRadius.circular(ZRadius.chip)),
                  child: Text(w, style: ZTypography.metaLabel.copyWith(color: z.ink, fontWeight: FontWeight.w700, fontSize: 12.5)),
                ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
                decoration: BoxDecoration(color: z.coral, borderRadius: BorderRadius.circular(ZRadius.chip)),
                child: Text(failChip, style: ZTypography.metaLabel.copyWith(color: z.onCoral, fontWeight: FontWeight.w700, fontSize: 12.5)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ContinueActions extends StatelessWidget {
  final GameOver state;
  final void Function(String method) onContinue;
  final VoidCallback onAcceptDefeat;

  const _ContinueActions({
    required this.state,
    required this.onContinue,
    required this.onAcceptDefeat,
  });

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    return Column(
      children: [
        GestureDetector(
          onTap: () => onContinue('ad'),
          child: Container(
            width: double.infinity,
            height: 56,
            decoration: BoxDecoration(
              color: z.teal,
              borderRadius: BorderRadius.circular(ZRadius.cardMin),
              boxShadow: ZElevation.solidEdge(z.tealDeep, depth: ZElevation.buttonDepth),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('ادامه با تماشای ویدیو', style: ZTypography.button.copyWith(color: z.onTeal, fontSize: 16)),
                const SizedBox(width: ZSpacing.sm),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
                  decoration: BoxDecoration(color: z.onTeal.withValues(alpha: 0.22), borderRadius: BorderRadius.circular(999)),
                  child: Text('۳۰ ثانیه', style: ZTypography.metaLabel.copyWith(color: z.onTeal, fontSize: 11)),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: ZSpacing.sm),
        Row(
          children: [
            Expanded(
              child: GestureDetector(
                onTap: () => onContinue('coins'),
                child: Container(
                  height: 50,
                  decoration: BoxDecoration(
                    color: z.surface,
                    borderRadius: BorderRadius.circular(ZRadius.cardMin),
                    border: Border.all(color: z.line),
                    boxShadow: ZElevation.solidEdge(z.line, depth: ZElevation.cardDepth),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text('ادامه با ${toPersianDigits(GameConstants.continueCostCoins)}',
                          style: ZTypography.cardTitle.copyWith(color: z.ink, fontSize: 14)),
                      const SizedBox(width: ZSpacing.sm),
                      Container(
                        width: 16,
                        height: 16,
                        decoration: BoxDecoration(
                          color: z.amber,
                          shape: BoxShape.circle,
                          boxShadow: ZElevation.solidEdge(z.amberDeep, depth: 2),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: ZSpacing.sm),
            Expanded(
              child: GestureDetector(
                onTap: () => getIt<ShareService>().shareMatch(score: state.score, chainLength: state.chainLength),
                child: Container(
                  height: 50,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: z.surface,
                    borderRadius: BorderRadius.circular(ZRadius.cardMin),
                    border: Border.all(color: z.line),
                    boxShadow: ZElevation.solidEdge(z.line, depth: ZElevation.cardDepth),
                  ),
                  child: Text('هم‌رسانی نتیجه', style: ZTypography.cardTitle.copyWith(color: z.ink, fontSize: 14)),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: ZSpacing.md),
        GestureDetector(
          onTap: onAcceptDefeat,
          child: Container(
            height: 44,
            alignment: Alignment.center,
            child: Text(
              state.continueTimeRemaining > 0
                  ? 'بازگشت به خانه (${toPersianDigits(state.continueTimeRemaining)})'
                  : 'بازگشت به خانه',
              style: ZTypography.body.copyWith(color: z.ink40, fontWeight: FontWeight.w600, fontSize: 13),
            ),
          ),
        ),
      ],
    );
  }
}

class _FinalActions extends StatelessWidget {
  final GameOver state;
  final VoidCallback onHome;

  const _FinalActions({required this.state, required this.onHome});

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    return Column(
      children: [
        AccentButton(
          accent: ZAccentColor.teal,
          label: 'هم‌رسانی نتیجه',
          onPressed: () => getIt<ShareService>().shareMatch(score: state.score, chainLength: state.chainLength),
        ),
        const SizedBox(height: ZSpacing.md),
        GestureDetector(
          onTap: onHome,
          child: Container(
            height: 44,
            alignment: Alignment.center,
            child: Text('بازگشت به خانه',
                style: ZTypography.body.copyWith(color: z.ink40, fontWeight: FontWeight.w600, fontSize: 13)),
          ),
        ),
      ],
    );
  }
}
