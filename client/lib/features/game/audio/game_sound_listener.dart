import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:wordchain/core/services/audio_service.dart';
import 'package:wordchain/features/game/audio/game_sounds.dart';
import 'package:wordchain/features/game/bloc/game_bloc.dart';

/// Plays the match's sounds and owns the music of the game screen: the game
/// loop while a match runs, silence on the result (the win / lose sting stands
/// alone), and the menu loop again when the screen is left.
///
/// It keeps its own "previous state" because a `BlocListener` only hands over
/// the new one, and the sounds are a function of the change.
class GameSoundListener extends StatefulWidget {
  final Widget child;

  const GameSoundListener({super.key, required this.child});

  @override
  State<GameSoundListener> createState() => _GameSoundListenerState();
}

class _GameSoundListenerState extends State<GameSoundListener> {
  StreamSubscription<GameState>? _sub;
  late GameState _prev;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_sub != null) return;
    final bloc = context.read<GameBloc>();
    _prev = bloc.state;
    _music(_prev);
    _sub = bloc.stream.listen((curr) {
      for (final s in soundsForTransition(_prev, curr)) {
        Sfx.play(s);
      }
      _music(curr);
      _prev = curr;
    });
  }

  void _music(GameState s) {
    if (s is GameActive) {
      Sfx.music(MusicTrack.game);
    } else if (s is GameOver) {
      Sfx.music(null);
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    Sfx.music(MusicTrack.menu);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
