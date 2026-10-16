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
