import 'package:equatable/equatable.dart';

sealed class GameEvent extends Equatable {
  const GameEvent();
}

class GameStarted extends GameEvent {
  final String mode; // classic | time_attack
  final String opponentType; // solo | ai_easy | ai_medium | ai_hard
  final int? resumeMatchId; // null = new game

  const GameStarted({
    required this.mode,
    required this.opponentType,
    this.resumeMatchId,
  });

  @override
  List<Object?> get props => [mode, opponentType, resumeMatchId];
}

class WordSubmitted extends GameEvent {
  final String word;

  const WordSubmitted(this.word);

  @override
  List<Object?> get props => [word];
}

class HintRequested extends GameEvent {
  const HintRequested();

  @override
  List<Object?> get props => [];
}

class GameEnded extends GameEvent {
  const GameEnded();

  @override
  List<Object?> get props => [];
}

class ContinueRequested extends GameEvent {
  final String method; // 'ad' | 'coins'

  const ContinueRequested(this.method);

  @override
  List<Object?> get props => [method];
}

class AcceptDefeat extends GameEvent {
  const AcceptDefeat();

  @override
  List<Object?> get props => [];
}

// Internal — emitted by the turn timer
class GameTimerTicked extends GameEvent {
  const GameTimerTicked();

  @override
  List<Object?> get props => [];
}

// Internal — emitted by the continue-window countdown
class ContinueTimerTicked extends GameEvent {
  const ContinueTimerTicked();

  @override
  List<Object?> get props => [];
}
