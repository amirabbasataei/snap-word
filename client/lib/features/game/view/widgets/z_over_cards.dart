import 'package:flutter/material.dart';
import 'package:wordchain/core/theme/app_game_metrics.dart';
import 'package:wordchain/core/theme/app_scene_tokens.dart';
import 'package:wordchain/core/theme/app_tokens.dart';
import 'package:wordchain/core/utils/persian_digits.dart';
import 'package:wordchain/core/widgets/chunky.dart';
import 'package:wordchain/core/widgets/z_disc_avatar.dart';

/// The cards of the result screen (canvas `ZOverA`): the score card with its
/// stat tiles and record bar (loss), the head-to-head pill and the reward
/// chips (win).

/// One labelled value of the score card.
class ZOverStat {
  final String label;
  final String value;

  /// A signed number («−۲۰»): laid out left-to-right so the sign stays on
  /// its left in an RTL row.
  final bool ltr;

  const ZOverStat(this.label, this.value, {this.ltr = false});
}

/// «امتیاز این دست» + the big score, the [stats] as a two-column grid of
/// wash tiles, and an optional [bar] underneath.
class ZOverScoreCard extends StatelessWidget {
  final int score;
  final List<ZOverStat> stats;
  final Widget? bar;

  const ZOverScoreCard({
    super.key,
    required this.score,
    required this.stats,
    this.bar,
  });

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    return ChunkyBox(
      fill: z.surface,
      depth: ZGame.overCardDepth,
      radius: ZGame.overCardRadius,
      highlight: false,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'امتیاز این دست',
                    style: TextStyle(
                      color: z.ink60,
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                    ),
                  ),
                  Text(
                    toPersianDigits(score),
                    style: TextStyle(
                      color: z.ink,
                      fontWeight: FontWeight.w900,
                      fontSize: 46,
                      height: 1.1,
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 14),
              Expanded(child: _StatGrid(stats: stats)),
            ],
          ),
          if (bar != null) ...[const SizedBox(height: 12), bar!],
        ],
      ),
    );
  }
}

class _StatGrid extends StatelessWidget {
  final List<ZOverStat> stats;

  const _StatGrid({required this.stats});

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var i = 0; i < stats.length; i += 2) {
      if (i > 0) rows.add(const SizedBox(height: 6));
      rows.add(
        // Tiles of a row share the taller one's height.
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: _StatTile(stat: stats[i])),
              const SizedBox(width: 6),
              Expanded(
                child:
                    i + 1 < stats.length
                        ? _StatTile(stat: stats[i + 1])
                        : const SizedBox.shrink(),
              ),
            ],
          ),
        ),
      );
    }
    return Column(mainAxisSize: MainAxisSize.min, children: rows);
  }
}

class _StatTile extends StatelessWidget {
  final ZOverStat stat;

  const _StatTile({required this.stat});

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: z.wash,
        borderRadius: BorderRadius.circular(12),
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: AlignmentDirectional.centerStart,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              stat.label,
              style: TextStyle(
                color: z.ink60,
                fontWeight: FontWeight.w700,
                fontSize: 12,
              ),
            ),
            Directionality(
              textDirection:
                  stat.ltr ? TextDirection.ltr : Directionality.of(context),
              child: Text(
                stat.value,
                style: TextStyle(
                  color: z.ink,
                  fontWeight: FontWeight.w900,
                  fontSize: 16,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Record progress inside the score card. Near miss («تا رکوردت (۲۳) · ۶
/// کلمهٔ دیگر», coral bar at 17/23) or, once the record is beaten, a full
/// teal bar with «رکورد جدید!».
class ZOverRecordBar extends StatelessWidget {
  final int chain;
  final int record;

  const ZOverRecordBar({super.key, required this.chain, required this.record});

  bool get _isNewRecord => chain >= record;

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    final zs = context.zs;
    final fill = _isNewRecord ? z.teal : z.coral;
    final progress = _isNewRecord ? 1.0 : (chain / record).clamp(0.0, 1.0);
    final header =
        _isNewRecord
            ? ('رکورد جدید!', '${toPersianDigits(chain)} کلمه')
            : (
              'تا رکوردت (${toPersianDigits(record)})',
              '${toPersianDigits(record - chain)} کلمهٔ دیگر',
            );
    // The ratio chip only makes sense while the record is still ahead.
    final label =
        _isNewRecord
            ? null
            : '${toPersianDigits(chain)} / ${toPersianDigits(record)}';

    return Semantics(
      label: '${header.$1}، ${header.$2}',
      excludeSemantics: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                header.$1,
                style: TextStyle(
                  color: z.ink,
                  fontWeight: FontWeight.w800,
                  fontSize: 12,
                ),
              ),
              Text(
                header.$2,
                style: TextStyle(
                  color: z.ink60,
                  fontWeight: FontWeight.w800,
                  fontSize: 12,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Container(
            height: ZGame.overBarHeight,
            decoration: BoxDecoration(
              color: z.wash,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: zs.outline, width: ZGame.outline),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: Stack(
                children: [
                  FractionallySizedBox(
                    widthFactor: progress,
                    alignment: AlignmentDirectional.centerStart,
                    heightFactor: 1,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Color.alphaBlend(zs.hi, fill), fill],
                          stops: const [0, .6],
                        ),
                      ),
                    ),
                  ),
                  if (label != null)
                    Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        decoration: BoxDecoration(
                          color: z.surface,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Directionality(
                          textDirection: TextDirection.ltr,
                          child: Text(
                            label,
                            style: TextStyle(
                              color: z.ink,
                              fontWeight: FontWeight.w900,
                              fontSize: 12,
                              height: 1.15,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Win header: my disc, «۳ – ۲» (final scores, mine first), the opponent's
/// disc — and the line naming the opponent underneath.
class ZOverVersusPill extends StatelessWidget {
  final String myLetter;
  final int myScore;
  final int opponentScore;

  /// The opponent's initial; null draws the robot (vs-AI).
  final String? opponentLetter;
  final String caption;

  /// Premium avatars (1v1) shown instead of the initials.
  final String? myAvatarId;
  final String? opponentAvatarId;

  const ZOverVersusPill({
    super.key,
    required this.myLetter,
    required this.myScore,
    required this.opponentScore,
    required this.opponentLetter,
    required this.caption,
    this.myAvatarId,
    this.opponentAvatarId,
  });

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    return Semantics(
      label:
          '$caption: ${toPersianDigits(myScore)} در برابر ${toPersianDigits(opponentScore)}',
      excludeSemantics: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ZDiscAvatar.me(
                context,
                letter: myLetter,
                size: 40,
                highlight: false,
                avatarId: myAvatarId,
              ),
              const SizedBox(width: 12),
              // Five-digit scores shrink the pill instead of the discs.
              Flexible(
                child: ChunkyBox(
                  fill: z.surface,
                  depth: 4,
                  radius: 14,
                  highlight: false,
                  height: 46,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          toPersianDigits(myScore),
                          style: _score(z.ink, 26),
                        ),
                        const SizedBox(width: 8),
                        Text('–', style: _score(z.ink60, 18)),
                        const SizedBox(width: 8),
                        Text(
                          toPersianDigits(opponentScore),
                          style: _score(z.ink, 26),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              opponentLetter == null
                  ? ZDiscAvatar.robot(context, size: 40, highlight: false)
                  : ZDiscAvatar.opponent(
                    context,
                    letter: opponentLetter!,
                    size: 40,
                    highlight: false,
                    avatarId: opponentAvatarId,
                  ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            caption,
            style: TextStyle(
              color: z.ink,
              fontWeight: FontWeight.w800,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }

  TextStyle _score(Color c, double size) => TextStyle(
    color: c,
    fontWeight: FontWeight.w900,
    fontSize: size,
    height: 1.1,
  );
}

enum ZOverChipKind { amber, indigo, surface }

/// A reward chip of the win screen: a big [value] over a small [label].
/// [valueSpan] replaces the plain value (the longest word with its first
/// letter tinted).
class ZOverChip extends StatelessWidget {
  final ZOverChipKind kind;
  final String value;
  final String label;
  final InlineSpan? valueSpan;

  const ZOverChip({
    super.key,
    required this.kind,
    required this.value,
    required this.label,
    this.valueSpan,
  });

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    final (fill, deep, on, sub, size) = switch (kind) {
      ZOverChipKind.amber => (z.amber, z.amberDeep, z.onAmber, z.onAmber, 24.0),
      ZOverChipKind.indigo => (
        z.indigo,
        z.indigoDeep,
        z.onIndigo,
        z.onIndigo,
        24.0,
      ),
      ZOverChipKind.surface => (
        z.surface,
        context.zs.tileDeep,
        z.ink,
        z.ink60,
        20.0,
      ),
    };
    return Semantics(
      label: '$label: $value',
      excludeSemantics: true,
      child: ChunkyBox(
        fill: fill,
        deep: deep,
        depth: ZGame.depthMd,
        radius: 18,
        highlight: kind != ZOverChipKind.surface,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Directionality(
                // «+۴۰» keeps its sign on the left in an RTL row.
                textDirection:
                    kind == ZOverChipKind.surface
                        ? Directionality.of(context)
                        : TextDirection.ltr,
                child: Text.rich(
                  valueSpan ?? TextSpan(text: value),
                  style: TextStyle(
                    color: on,
                    fontWeight: FontWeight.w900,
                    fontSize: size,
                    height: 1.2,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: sub,
                fontWeight: FontWeight.w800,
                fontSize: 12,
                height: 1.25,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
