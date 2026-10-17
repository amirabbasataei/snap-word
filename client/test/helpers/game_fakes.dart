import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:wordchain/features/auth/cubit/auth_cubit.dart';
import 'package:wordchain/features/game/bloc/game_bloc.dart';

/// Auth cubit stand-in for widget tests: reports [current] and never emits.
class FakeAuthCubit extends Fake implements AuthCubit {
  final AuthState current;

  FakeAuthCubit([this.current = const AuthGuest()]);

  @override
  AuthState get state => current;

  @override
  Stream<AuthState> get stream => const Stream.empty();
}

/// Game bloc stand-in: records the events a screen adds. The active-game
/// screens read their state from the constructor, so nothing else is needed.
class FakeGameBloc extends Fake implements GameBloc {
  final events = <GameEvent>[];

  @override
  void add(GameEvent event) => events.add(event);

  @override
  GameState get state => const GameInitial();

  @override
  Stream<GameState> get stream => const Stream.empty();

  @override
  Future<void> close() async {}
}

/// A bloc whose state and entry fee the test chooses, with a stream it can
/// push new states on (the exit dialog closes itself when the game ends).
class ScriptedGameBloc extends FakeGameBloc {
  GameState _state;
  final int _fee;
  final _states = StreamController<GameState>.broadcast();

  ScriptedGameBloc(this._state, {int entryFee = 0}) : _fee = entryFee;

  @override
  GameState get state => _state;

  @override
  int get entryFee => _fee;

  @override
  Stream<GameState> get stream => _states.stream;

  void push(GameState next) {
    _state = next;
    _states.add(next);
  }

  @override
  Future<void> close() async => _states.close();
}
