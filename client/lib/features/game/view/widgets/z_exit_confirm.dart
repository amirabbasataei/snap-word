import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:wordchain/core/theme/app_game_metrics.dart';
import 'package:wordchain/core/theme/app_scene_tokens.dart';
import 'package:wordchain/core/theme/app_tokens.dart';
import 'package:wordchain/core/theme/app_typography.dart';
import 'package:wordchain/core/utils/persian_digits.dart';
import 'package:wordchain/core/widgets/chunky.dart';
import 'package:wordchain/core/widgets/motion.dart';
import 'package:wordchain/core/widgets/z_dialog.dart';
import 'package:wordchain/core/widgets/z_mascot.dart';
import 'package:wordchain/features/game/bloc/game_bloc.dart';

/// Which game the player is leaving. Each mode ends differently, so each has
/// its own copy (canvas turn 8, frames 8b–8e).
enum ZExitMode { solo, ai, online, daily }

/// The mode of a running game, from its state.
ZExitMode zExitModeOf(GameActive s) {
  if (s.mode == 'daily') return ZExitMode.daily;
  if (s.isMultiplayer) return ZExitMode.online;
  if (s.isVsAI) return ZExitMode.ai;
  return ZExitMode.solo;
}

/// Whether the game clock stops while the dialog is up. Solo and vs-AI
/// clocks stop (nothing ranked depends on them); an online match runs on the
/// server and cannot be paused. The daily challenge is ranked and prized, so
/// it keeps running too — otherwise the back button would be a free "think
/// as long as you like" button on a leaderboard.
bool zExitPausesClock(ZExitMode mode) =>
    mode == ZExitMode.solo || mode == ZExitMode.ai;

enum _Tone { indigo, amber, coral }

class _Stake {
  final String value;
  final String label;
  final _Tone tone;

  /// The value starts with a sign («−۲۰»), so it is laid out left-to-right.
  final bool signed;

  const _Stake(this.value, this.label, this.tone, {this.signed = false});
}

/// Everything a mode says. The wording follows the canvas, adapted wherever
/// the canvas claims something the product does not do (see the notes on each
/// mode); the cards only ever show numbers the game actually has.
class ZExitCopy {
  final ZMascotMood mascot;
  final String pill;
  final String title;
  final String body;
  final String stakesHeader;
  final String stay;
  final String leave;

  /// The clock keeps running while the dialog is up (the pill says so).
  final bool live;
  final List<_Stake> _stakes;

  const ZExitCopy._({
    required this.mascot,
    required this.live,
    required this.pill,
    required this.title,
    required this.body,
    required this.stakesHeader,
    required this.stay,
    required this.leave,
    required List<_Stake> stakes,
  }) : _stakes = stakes;

  /// [chainLength] and [score] are the running game's; [entryFee] is the
  /// coins an online match took from this player (0 against the AI fallback).
  factory ZExitCopy.of(
    ZExitMode mode, {
    required int chainLength,
    required int score,
    int entryFee = 0,
  }) {
    final chain = _Stake(
      '${formatPersianNumber(chainLength)} کلمه',
      'زنجیر فعلی',
      _Tone.indigo,
    );
    final points = _Stake(formatPersianNumber(score), 'امتیاز', _Tone.amber);
    // Leaving solo / AI / daily ends the game and saves it as it stands
    // (`GameEnded` → stats, XP, sync), so these cards are what gets recorded.
    const kept = 'تا همین‌جا ثبت می‌شه';
    final live = !zExitPausesClock(mode);
    switch (mode) {
      case ZExitMode.solo:
        return ZExitCopy._(
          mascot: ZMascotMood.sad,
          live: live,
          pill: 'بازی متوقف شد',
          title: 'زنجیرت نصفه می‌مونه!',
          // Canvas: "این زنجیر ذخیره نمی‌شه" — it is saved; what is lost is
          // the chance to carry on (no continue after leaving).
          body:
              'اگه الان بری، بازی همین‌جا تموم می‌شه و دیگه نمی‌تونی ادامه‌اش بدی. '
              'امتیازت همون‌طور که هست ثبت می‌شه.',
          stakesHeader: kept,
          stay: 'ادامه می‌دم',
          leave: 'خروج',
          stakes: [chain, points],
        );
      case ZExitMode.ai:
        return ZExitCopy._(
          mascot: ZMascotMood.sad,
          live: live,
          pill: 'بازی متوقف شد',
          title: 'بازی رو وا می‌دی؟',
          // Canvas: "باخت در کارنامه" — vs-AI has no win/loss record; the
          // game just ends with the score it has.
          body:
              'اگه الان بری، بازی با حریف هوشمند همین‌جا تموم می‌شه و دیگه '
              'نمی‌تونی ادامه‌اش بدی. امتیازت همون‌طور که هست ثبت می‌شه.',
          stakesHeader: kept,
          stay: 'ادامه می‌دم',
          leave: 'تسلیم و خروج',
          stakes: [points, chain],
        );
      case ZExitMode.online:
        return ZExitCopy._(
          mascot: ZMascotMood.surprised,
          live: live,
          pill: 'تایمر متوقف نمی‌شه',
          title: 'تسلیم می‌شی؟',
          // Canvas: "حریفت منتظره … سکه‌های شرط مال اون می‌شه" and a rank
          // penalty. There is no rank; the entry fee only exists against a
          // human opponent, so the coin line is conditional.
          body:
              entryFee > 0
                  ? 'اگه بری، بازی رو می‌بازی و ${formatPersianNumber(entryFee)} سکهٔ ورودی‌ات مال حریفت می‌شه.'
                  : 'اگه بری، بازی رو می‌بازی.',
          stakesHeader: 'اگه بری از دستت می‌ره',
          stay: 'برمی‌گردم',
          leave: 'تسلیم و خروج',
          stakes: [
            if (entryFee > 0)
              _Stake(
                '−${formatPersianNumber(entryFee)} سکه',
                'ورودی بازی',
                _Tone.amber,
                signed: true,
              ),
            const _Stake('باخت', 'نتیجهٔ بازی', _Tone.coral),
          ],
        );
      case ZExitMode.daily:
        return ZExitCopy._(
          mascot: ZMascotMood.sad,
          live: live,
          // Canvas pauses the clock here; the daily one keeps running.
          pill: 'تایمر متوقف نمی‌شه',
          title: 'تلاش امروزت تموم می‌شه!',
          // Canvas: "تا فردا نمی‌تونی دوباره بازی کنی", "۶ روز رکورد پیاپی",
          // "۵۰ سکه جایزهٔ امروز" — leaving posts today's attempt with its
          // score, keeps the streak (the game counts as played), and the
          // prizes depend on rank, not on finishing.
          body:
              'اگه بری، تلاش امروزت همین‌جا تموم می‌شه و با همین امتیاز '
              'توی جدول امروز ثبت می‌شه.',
          stakesHeader: kept,
          stay: 'ادامه می‌دم',
          leave: 'خروج',
          stakes: [chain, points],
        );
    }
  }

  /// `(value, label)` of each stake card, in display order.
  List<(String, String)> get stakes => [for (final s in _stakes) (s.value, s.label)];
}

/// The exit-confirm content: mascot, status pill, title, body, the "what
/// happens to your game" cards and the two buttons. Stay is the primary
/// button; leaving is secondary.
class ZExitConfirm extends StatelessWidget {
  final ZExitMode mode;
  final int chainLength;
  final int score;
  final int entryFee;
  final VoidCallback onStay;
  final VoidCallback onLeave;

  const ZExitConfirm({
    super.key,
    required this.mode,
    required this.chainLength,
    required this.score,
    this.entryFee = 0,
    required this.onStay,
    required this.onLeave,
  });

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    final copy = ZExitCopy.of(
      mode,
      chainLength: chainLength,
      score: score,
      entryFee: entryFee,
    );
    return ZDialogCard(
      semanticLabel: copy.title,
      mascot: ZMascot(
        mood: copy.mascot,
        size: ZGame.dialogMascotSize,
        shadow: false,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(child: _StatusPill(text: copy.pill, live: copy.live)),
          const SizedBox(height: 14),
          Text(
            copy.title,
            textAlign: TextAlign.center,
            style: ZTypography.screenTitle.copyWith(
              fontSize: 22,
              height: 1.3,
              color: z.ink,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            copy.body,
            textAlign: TextAlign.center,
            style: ZTypography.body.copyWith(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              height: 1.65,
              color: z.ink60,
            ),
          ),
          const SizedBox(height: 14),
          _Stakes(header: copy.stakesHeader, stakes: copy._stakes),
          const SizedBox(height: 14),
          ZDialogButton.primary(label: copy.stay, onTap: onStay),
          const SizedBox(height: 7),
          ZDialogButton.secondary(
            label: copy.leave,
            onTap: onLeave,
            labelColor: context.zs.coralInk,
            icon: SvgPicture.string(
              '<svg viewBox="0 0 24 24" fill="none" stroke="${svgHex(context.zs.coralInk)}" stroke-width="3" stroke-linecap="round" stroke-linejoin="round"><path d="M14 4h4a2 2 0 0 1 2 2v12a2 2 0 0 1-2 2h-4M9 8l-4 4 4 4M5 12h10"/></svg>',
              width: 18,
              height: 18,
            ),
          ),
        ],
      ),
    );
  }
}

/// «بازی متوقف شد» (ink pill with a pause glyph) or, when the clock keeps
/// running, a coral pill with a pulsing dot.
class _StatusPill extends StatelessWidget {
  final String text;
  final bool live;

  const _StatusPill({required this.text, required this.live});

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    final zs = context.zs;
    final bg = live ? z.coral : z.inkSurface;
    final ink = live ? zs.onCoralSm : z.onInkSurface;
    Widget bar() => Container(
      width: 3.5,
      height: 10,
      decoration: BoxDecoration(
        color: ink,
        borderRadius: BorderRadius.circular(1),
      ),
    );
    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: zs.outline, width: ZGame.outlineInner),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (live)
            HomeClock(
              enabled: !homeReducedMotion(context),
              builder:
                  (context, ms, _) => Opacity(
                    // The canvas `pulse`: a quick 1 → .3 → 1 blink.
                    opacity: 1 - .7 * HomeLoop.pingPong(ms, 700),
                    child: Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: ink,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
            )
          else
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [bar(), const SizedBox(width: 2.5), bar()],
            ),
          const SizedBox(width: 6),
          Text(
            text,
            style: ZTypography.button.copyWith(
              fontSize: 12,
              height: 1.2,
              color: ink,
            ),
          ),
        ],
      ),
    );
  }
}

class _Stakes extends StatelessWidget {
  final String header;
  final List<_Stake> stakes;

  const _Stakes({required this.header, required this.stakes});

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: z.wash,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            header,
            style: ZTypography.metaLabel.copyWith(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: z.ink60,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              for (var i = 0; i < stakes.length; i++) ...[
                if (i > 0) const SizedBox(width: 8),
                Expanded(child: _StakeCard(stake: stakes[i])),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _StakeCard extends StatelessWidget {
  final _Stake stake;

  const _StakeCard({required this.stake});

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    final zs = context.zs;
    final color = switch (stake.tone) {
      _Tone.indigo => z.indigo,
      _Tone.amber => z.amber,
      _Tone.coral => z.coral,
    };
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: z.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: zs.outline, width: ZGame.outlineInner),
      ),
      child: Row(
        children: [
          // The tone dot: a small chunky disc with the top highlight.
          ChunkyBox(
            fill: color,
            circle: true,
            depth: 0,
            borderWidth: ZGame.outlineInner,
            width: 26,
            height: 26,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  stake.value,
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.ellipsis,
                  textDirection: stake.signed ? TextDirection.ltr : null,
                  style: ZTypography.button.copyWith(
                    fontSize: 15,
                    height: 1.2,
                    color: z.ink,
                  ),
                ),
                Text(
                  stake.label,
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.ellipsis,
                  style: ZTypography.metaLabel.copyWith(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    height: 1.3,
                    color: z.ink60,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Shows the exit confirmation over the running game and, on "leave", ends it
/// (`GameEnded`). Shared by every game screen's back button — ZSolo, ZPlay and
/// ZVersus — so the dialog always matches the mode being left.
///
/// Solo and vs-AI pause their clock while it is open (see [zExitPausesClock]);
/// if the game ends under it (a turn timing out in an online or daily game)
/// the dialog closes itself.
Future<void> zShowEndGameDialog(BuildContext context) async {
  final bloc = context.read<GameBloc>();
  final state = bloc.state;
  if (state is! GameActive) return;

  final mode = zExitModeOf(state);
  final pauses = zExitPausesClock(mode);
  if (pauses) bloc.add(const GamePaused());

  StreamSubscription<GameState>? sub;
  final leave = await showZDialog<bool>(
    context,
    builder: (dialogContext) {
      sub ??= bloc.stream.listen((s) {
        if (s is! GameActive && dialogContext.mounted) {
          Navigator.of(dialogContext).maybePop();
        }
      });
      return ZExitConfirm(
        mode: mode,
        chainLength: state.wordChain.length,
        score: state.score,
        entryFee: bloc.entryFee,
        onStay: () => Navigator.of(dialogContext).pop(false),
        onLeave: () => Navigator.of(dialogContext).pop(true),
      );
    },
  );
  unawaited(sub?.cancel());

  if (leave == true) {
    bloc.add(const GameEnded());
  } else if (pauses) {
    bloc.add(const GameResumed());
  }
}
