import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:wordchain/core/theme/app_scene_tokens.dart';
import 'package:wordchain/core/widgets/motion.dart';
import 'package:wordchain/features/game/bloc/game_bloc.dart';
import 'package:wordchain/features/game/view/widgets/z_exit_confirm.dart';
import 'package:wordchain/features/game/view/widgets/z_game_hud.dart';
import 'package:wordchain/features/game/view/widgets/z_game_shared.dart';
import 'package:wordchain/features/game/view/widgets/z_persian_keyboard.dart';
import 'package:wordchain/features/home/view/widgets/home_scene_background.dart';

/// Frame of the "A · mascot-led" active-game screens: the calm sky scene
/// behind a [header], the [body] filling the middle and the [footer] (see
/// [ZGameFooter]) at the bottom. Typing uses the game's own keyboard, which
/// the footer draws flush with the bottom edge (it pads for the gesture bar
/// itself), so the scaffold never reacts to the system keyboard.
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
    return Scaffold(
      backgroundColor: context.zs.sky3,
      resizeToAvoidBottomInset: false,
      body: Stack(
        children: [
          const Positioned.fill(child: HomeSceneBackground(calm: true)),
          SafeArea(
            bottom: false,
            child: Column(children: [header, Expanded(child: body), footer]),
          ),
        ],
      ),
    );
  }
}

/// Top of the active-game screens: the back button (ends the game after a
/// confirmation), the [center] widget (score pill) and the timer [ring] on one
/// row, then [below] (chips) 12dp lower.
class ZGameHeader extends StatelessWidget {
  final Widget center;
  final Widget ring;

  /// Chips under the row; null leaves the header one row tall.
  final Widget? below;

  const ZGameHeader({
    super.key,
    required this.center,
    required this.ring,
    this.below,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
      child: Column(
        children: [
          Row(
            children: [
              ZGameBackButton(onTap: () => zShowEndGameDialog(context)),
              const SizedBox(width: 10),
              Expanded(child: center),
              const SizedBox(width: 10),
              ring,
            ],
          ),
          if (below != null) ...[const SizedBox(height: 12), below!],
        ],
      ),
    );
  }
}

/// The input card (with an optional [banner] above it), the chunky power-up
/// row and the [ZPersianKeyboard] under them. [opponentLabel] set → the card shows «… در حال فکر کردن…»
/// while it is the opponent's turn; [longWordMinLength] set → the
/// double-score tag appears for long words. [powerups] picks the tiles (solo
/// has no Freeze, a duel does); [trailing] sits beside the input card (the
/// taunt button of ZVersus); [thinkingAccessory] stands at the end of the
/// «… در حال فکر کردن» card.
class ZGameFooter extends StatefulWidget {
  final GameActive state;
  final Widget? banner;
  final String? opponentLabel;
  final int? longWordMinLength;
  final List<String> powerups;
  final Widget? trailing;
  final Widget? thinkingAccessory;

  /// False blocks typing even on the player's turn (an overlay is up).
  final bool inputEnabled;

  const ZGameFooter({
    super.key,
    required this.state,
    this.banner,
    this.opponentLabel,
    this.longWordMinLength,
    this.powerups = const ['hint', 'extra_time', 'shield'],
    this.trailing,
    this.thinkingAccessory,
    this.inputEnabled = true,
  });

  @override
  State<ZGameFooter> createState() => _ZGameFooterState();
}

class _ZGameFooterState extends State<ZGameFooter> {
  /// Shared by the word field and the keyboard that types into it.
  final _controller = TextEditingController();
  final _focusNode = FocusNode();

  bool get _canType => widget.state.isMyTurn && widget.inputEnabled;

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _submit() {
    final word = _controller.text.trim();
    if (word.isEmpty || !_canType) return;
    context.read<GameBloc>().add(WordSubmitted(word));
    _controller.clear();
    if (!homeReducedMotion(context)) _focusNode.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final compact = MediaQuery.sizeOf(context).height < 600;
    final thinking = widget.opponentLabel != null && !state.isMyTurn;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 0, 14, 0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.banner != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: widget.banner,
                ),
              Row(
                children: [
                  Expanded(
                    child: ZWordInput(
                      chunky: true,
                      customKeyboard: true,
                      controller: _controller,
                      focusNode: _focusNode,
                      startLetter: state.nextStartLetter,
                      enabled: _canType,
                      hintWord: state.hintWord,
                      isOpponentThinking: thinking,
                      opponentLabel: widget.opponentLabel ?? 'حریف',
                      longWordMinLength: widget.longWordMinLength,
                      thinkingAccessory: widget.thinkingAccessory,
                      onSubmit:
                          (word) =>
                              context.read<GameBloc>().add(WordSubmitted(word)),
                    ),
                  ),
                  if (widget.trailing != null) ...[
                    const SizedBox(width: 8),
                    widget.trailing!,
                  ],
                ],
              ),
              SizedBox(height: compact ? 8 : 14),
              ZPowerupBar(state: state, types: widget.powerups, chunky: true),
              SizedBox(height: compact ? 8 : 12),
            ],
          ),
        ),
        ZPersianKeyboard(
          controller: _controller,
          enabled: _canType,
          onSend: _submit,
        ),
      ],
    );
  }
}
