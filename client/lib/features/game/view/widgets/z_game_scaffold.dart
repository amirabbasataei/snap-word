import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:wordchain/core/theme/app_scene_tokens.dart';
import 'package:wordchain/features/game/bloc/game_bloc.dart';
import 'package:wordchain/features/game/view/widgets/z_game_shared.dart';
import 'package:wordchain/features/home/view/widgets/home_scene_background.dart';

/// Frame of the "A · mascot-led" active-game screens: the calm sky scene
/// behind a [header], the [body] filling the middle and the [footer] (see
/// [ZGameFooter]) at the bottom. The scene stays put behind the keyboard; the
/// content pads itself by the keyboard height instead.
class ZGameScaffold extends StatelessWidget {
  final Widget header;
  final Widget body;
  final Widget footer;

  const ZGameScaffold({
    super.key,
    required this.header,
    required this.body,
    required this.footer,
  });

  @override
  Widget build(BuildContext context) {
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    return Scaffold(
      backgroundColor: context.zs.sky3,
      resizeToAvoidBottomInset: false,
      body: Stack(
        children: [
          const Positioned.fill(child: HomeSceneBackground(calm: true)),
          Padding(
            padding: EdgeInsets.only(bottom: keyboard),
            child: SafeArea(
              bottom: keyboard == 0,
              child: Column(children: [header, Expanded(child: body), footer]),
            ),
          ),
        ],
      ),
    );
  }
}

/// The input card (with an optional [banner] above it) and the chunky
/// power-up row. [opponentLabel] set → the card shows «… در حال فکر کردن…»
/// while it is the opponent's turn; [longWordMinLength] set → the
/// double-score tag appears for long words.
class ZGameFooter extends StatelessWidget {
  final GameActive state;
  final Widget? banner;
  final String? opponentLabel;
  final int? longWordMinLength;

  const ZGameFooter({
    super.key,
    required this.state,
    this.banner,
    this.opponentLabel,
    this.longWordMinLength,
  });

  @override
  Widget build(BuildContext context) {
    final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;
    final thinking = opponentLabel != null && !state.isMyTurn;
    return Padding(
      padding: EdgeInsets.fromLTRB(14, 0, 14, keyboardOpen ? 8 : 18),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (banner != null)
            Padding(padding: const EdgeInsets.only(bottom: 10), child: banner),
          ZWordInput(
            chunky: true,
            startLetter: state.nextStartLetter,
            enabled: state.isMyTurn,
            hintWord: state.hintWord,
            isOpponentThinking: thinking,
            opponentLabel: opponentLabel ?? 'حریف',
            longWordMinLength: longWordMinLength,
            onSubmit:
                (word) => context.read<GameBloc>().add(WordSubmitted(word)),
          ),
          const SizedBox(height: 14),
          ZPowerupBar(
            state: state,
            types: const ['hint', 'extra_time', 'shield'],
            chunky: true,
          ),
        ],
      ),
    );
  }
}
