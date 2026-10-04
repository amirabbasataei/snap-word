import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:wordchain/core/di/injection.dart';
import 'package:wordchain/core/theme/app_spacing.dart';
import 'package:wordchain/core/theme/app_tokens.dart';
import 'package:wordchain/core/theme/app_typography.dart';
import 'package:wordchain/core/utils/persian_digits.dart';
import 'package:wordchain/core/widgets/letter_tile.dart';
import 'package:wordchain/core/widgets/solid_card.dart';
import 'package:wordchain/core/widgets/tint_chip.dart';
import 'package:wordchain/core/widgets/z_buttons.dart';
import 'package:wordchain/features/auth/cubit/auth_cubit.dart';
import 'package:wordchain/features/daily/data/daily_repository.dart';
import 'package:wordchain/features/game/data/game_constants.dart';

/// Today's Daily Challenge ranking (best score per player). Prizes are paid
/// as claimable rewards at Iran midnight: a completion prize for everyone plus
/// a rank prize for the top 3.
class DailyBoardScreen extends StatefulWidget {
  const DailyBoardScreen({super.key});

  @override
  State<DailyBoardScreen> createState() => _DailyBoardScreenState();
}

class _DailyBoardScreenState extends State<DailyBoardScreen> {
  late Future<DailyBoard> _future;

  @override
  void initState() {
    super.initState();
    _future = getIt<DailyRepository>().getLeaderboard();
  }

  void _reload() => setState(() => _future = getIt<DailyRepository>().getLeaderboard());

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    final auth = getIt<AuthCubit>().state;
    final myId = auth is AuthAuthenticated ? auth.userId : '';

    return Scaffold(
      backgroundColor: z.paper,
      body: SafeArea(
        child: FutureBuilder<DailyBoard>(
          future: _future,
          builder: (context, snap) {
            final board = snap.data;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    ZSpacing.screenGutter, ZSpacing.lg, ZSpacing.screenGutter, ZSpacing.sm,
                  ),
                  child: Row(
                    children: [
                      IconButton(
                        onPressed: () => context.pop(),
                        icon: Icon(Icons.arrow_forward_rounded, color: z.ink),
                      ),
                      const SizedBox(width: ZSpacing.sm),
                      Expanded(
                        child: Text(
                          board == null || board.dayNumber == 0
                              ? 'جدول امروز'
                              : 'جدول چالش #${toPersianDigits(board.dayNumber)}',
                          style: ZTypography.screenTitle.copyWith(color: z.ink),
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: ZSpacing.screenGutter),
                  child: Text(
                    'جایزه‌ها نیمه‌شب به وقت ایران در «پیام‌ها» می‌آید: '
                    'همهٔ شرکت‌کننده‌ها ${toPersianDigits(GameConstants.dailyCompletePrize)} سکه، '
                    '۳ نفر اول جایزهٔ بیشتر.',
                    style: ZTypography.metaLabel.copyWith(color: z.ink60),
                  ),
                ),
                const SizedBox(height: ZSpacing.md),
                Expanded(child: _body(context, snap, board, myId)),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _body(BuildContext context, AsyncSnapshot<DailyBoard> snap, DailyBoard? board, String myId) {
    final z = context.z;
    if (snap.hasError) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('بارگذاری جدول ممکن نشد', style: ZTypography.body.copyWith(color: z.ink60)),
            const SizedBox(height: ZSpacing.md),
            NeutralButton(label: 'تلاش دوباره', onPressed: _reload),
          ],
        ),
      );
    }
    if (board == null) {
      return Center(child: CircularProgressIndicator(color: z.indigo));
    }
    if (board.entries.isEmpty) {
      return Center(
        child: Text(
          'هنوز کسی چالش امروز را بازی نکرده — اولین نفر باش!',
          style: ZTypography.body.copyWith(color: z.ink40),
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        ZSpacing.screenGutter, 0, ZSpacing.screenGutter, ZSpacing.xl,
      ),
      children: [
        SolidCard(
          padding: const EdgeInsets.symmetric(horizontal: ZSpacing.lg),
          radius: ZRadius.cardMax,
          child: Column(
            children: [
              for (var i = 0; i < board.entries.length; i++)
                _Row(
                  entry: board.entries[i],
                  isMe: board.entries[i].userId == myId,
                  showTopBorder: i > 0,
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Row extends StatelessWidget {
  final DailyBoardEntry entry;
  final bool isMe;
  final bool showTopBorder;

  const _Row({required this.entry, required this.isMe, required this.showTopBorder});

  static const _accents = [ZAccent.amber, ZAccent.indigo, ZAccent.teal];

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    final prizes = GameConstants.dailyRankPrizes;
    final prize = entry.rank >= 1 && entry.rank <= prizes.length ? prizes[entry.rank - 1] : null;
    final initial = entry.username.isEmpty ? '؟' : entry.username.substring(0, 1).toUpperCase();
    final accent = entry.rank >= 1 && entry.rank <= _accents.length ? _accents[entry.rank - 1] : ZAccent.coral;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 11),
      decoration: BoxDecoration(
        border: showTopBorder ? Border(top: BorderSide(color: z.line)) : null,
      ),
      child: Row(
        children: [
          SizedBox(
            width: 24,
            child: Text(
              toPersianDigits(entry.rank),
              style: ZTypography.cardTitle.copyWith(fontSize: 13, color: z.ink40),
            ),
          ),
          const SizedBox(width: ZSpacing.md),
          LetterTile(letter: initial, size: 32, accent: accent, radius: 10, fontSize: 14),
          const SizedBox(width: ZSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isMe ? '${entry.username} (تو)' : entry.username,
                  style: ZTypography.cardTitle.copyWith(
                    fontSize: 13.5,
                    color: isMe ? z.indigo : z.ink,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  '${toPersianDigits(entry.chainLength)} کلمه',
                  style: ZTypography.metaLabel.copyWith(color: z.ink40),
                ),
              ],
            ),
          ),
          if (prize != null) ...[
            TintChip(label: '+${toPersianDigits(prize)} سکه', tint: ZTint.teal),
            const SizedBox(width: ZSpacing.sm),
          ],
          Text(
            formatPersianNumber(entry.score),
            style: ZTypography.cardTitle.copyWith(fontSize: 14, color: z.ink),
          ),
        ],
      ),
    );
  }
}
