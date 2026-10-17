import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:wordchain/core/di/injection.dart';
import 'package:wordchain/core/theme/app_tokens.dart';
import 'package:wordchain/core/utils/avatar_initial.dart';
import 'package:wordchain/core/utils/persian_digits.dart';
import 'package:wordchain/core/widgets/chunky_pill.dart';
import 'package:wordchain/core/widgets/z_coin.dart';
import 'package:wordchain/core/widgets/z_disc_avatar.dart';
import 'package:wordchain/core/widgets/z_mascot.dart';
import 'package:wordchain/features/auth/cubit/auth_cubit.dart';
import 'package:wordchain/features/game/bloc/game_bloc.dart';
import 'package:wordchain/features/game/data/game_constants.dart';
import 'package:wordchain/features/game/view/widgets/z_game_hud.dart';
import 'package:wordchain/features/game/view/widgets/z_game_scaffold.dart';
import 'package:wordchain/features/game/view/widgets/z_taunt_tray.dart';

export 'package:wordchain/features/game/view/widgets/z_taunt_tray.dart'
    show ZVersusChain, ZVersusChainState;

/// ZVersus — the 1v1 multiplayer active-game screen in the "A · mascot-led"
/// language (canvas `ZVersusA`), laid out like ZPlay: head-to-head pill with
/// the turn chip, the countdown ring, the shared chain as chunky bubbles (me
/// on the start side, the opponent on the end side), then the input card with
/// the taunt button and the four power-ups.
///
/// Left out on purpose, because nothing backs them (REDESIGN_PLAN.md, todo.md
/// § 1): the «۲ جان» lives chip (the server ends the match on the first
/// mistake), the «دست N از ۵» round dots, the «… دارد می‌نویسد» typing bubble
/// and the «کلمهٔ بلند · دوبرابر» tag (the Go scorer has no long-word bonus).
/// The caller (game_screen.dart) wraps this in the continue-window and
/// disconnected overlays.
class ZVersusActiveScreen extends StatelessWidget {
  final GameActive state;

  const ZVersusActiveScreen({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    final auth = getIt<AuthCubit>().state;
    final myInitial = avatarInitial(
      auth is AuthAuthenticated ? auth.username : null,
    );
    // The WS game state carries no usernames yet, so this is «حریف» in practice.
    final opponentName = state.opponentUsername ?? 'حریف';
    final opponentInitial = avatarInitial(opponentName, fallback: 'ح');

    Widget me(double size, {bool highlight = true}) => ZDiscAvatar.me(
      context,
      letter: myInitial,
      size: size,
      highlight: highlight,
      avatarId: state.myAvatarId,
    );
    Widget them(double size, {bool highlight = true}) => ZDiscAvatar.opponent(
      context,
      letter: opponentInitial,
      size: size,
      highlight: highlight,
      avatarId: state.opponentAvatarId,
    );
    Widget meFlat(double size) => me(size, highlight: false);
    Widget themFlat(double size) => them(size, highlight: false);

    return ZGameScaffold(
      header: ZGameHeader(
        center: ZVersusPill(
          myAvatar: me,
          myLabel: 'تو',
          myScore: state.score,
          opponentAvatar: them,
          opponentLabel: opponentName,
          opponentScore: state.opponentScore,
          myTurn: state.isMyTurn,
          myTurnLabel: 'نوبت تو',
          opponentTurnLabel: 'نوبت $opponentName',
          myPremium: state.myPremium,
          opponentPremium: state.opponentPremium,
        ),
        // Clocks run on both turns in a duel, so the ring is never dimmed.
        ring: ZTimerRing(
          secondsRemaining: state.turnTimeRemaining,
          totalSeconds: GameConstants.classicTurnTimerSec,
          calm: true,
        ),
        below: _EntryFeeChip.maybe(context),
      ),
      body: ZVersusChain(
        state: state,
        myInitial: myInitial,
        myAvatar: meFlat,
        opponentAvatar: themFlat,
      ),
      // Fixed-height chunky controls: text scale is capped (like ZOver's
      // actions) so the labels can't outgrow them.
      footer: MediaQuery.withClampedTextScaling(
        maxScaleFactor: 1.3,
        child: ZGameFooter(
          state: state,
          opponentLabel: opponentName,
          powerups: const ['hint', 'freeze', 'extra_time', 'shield'],
          inputEnabled: !state.opponentContinueWindowActive,
          trailing: ZTauntButton(premium: state.myPremium),
          thinkingAccessory: const ZMascot(
            mood: ZMascotMood.thinking,
            size: 34,
            shadow: false,
          ),
        ),
      ),
    );
  }
}

/// «ورودی ۲۰ سکه» — what this player paid to enter the match. Shown only when
/// something was charged (matches against the AI fallback are free).
class _EntryFeeChip extends StatelessWidget {
  final int fee;

  const _EntryFeeChip(this.fee);

  static Widget? maybe(BuildContext context) {
    final fee = context.read<GameBloc>().entryFee;
    return fee > 0 ? Center(child: _EntryFeeChip(fee)) : null;
  }

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    return ZChunkPill(
      fill: z.surface,
      height: 32,
      padding: const EdgeInsetsDirectional.only(start: 12, end: 10),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const ZCoin(size: 18),
          const SizedBox(width: 6),
          Text(
            'ورودی ${toPersianDigits(fee)} سکه',
            style: TextStyle(
              color: z.ink,
              fontWeight: FontWeight.w900,
              fontSize: 12.5,
              height: 1,
            ),
          ),
        ],
      ),
    );
  }
}
