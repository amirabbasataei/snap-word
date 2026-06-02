import 'package:equatable/equatable.dart';

sealed class GameEvent extends Equatable {
  const GameEvent();
}

class GameStarted extends GameEvent {
  final String mode; // classic | time_attack
  final String opponentType; // solo | ai_easy | ai_medium | ai_hard | multiplayer
  final int? resumeMatchId; // null = new game (solo/AI only)
  final String? roomId; // multiplayer WS room ID
  final String? myPlayerId; // authenticated user's UUID

  const GameStarted({
    required this.mode,
    required this.opponentType,
    this.resumeMatchId,
    this.roomId,
    this.myPlayerId,
  });

  @override
  List<Object?> get props => [mode, opponentType, resumeMatchId, roomId, myPlayerId];
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

// Internal — emitted by the turn timer (solo/AI only)
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

// Internal — emitted by the opponent continue-window countdown (multiplayer)
class OpponentContinueTimerTicked extends GameEvent {
  const OpponentContinueTimerTicked();

  @override
  List<Object?> get props => [];
}

// Internal — raw WebSocket event received from server (multiplayer)
class WsEventReceived extends GameEvent {
  final String type;
  final Map<String, dynamic> data;

  const WsEventReceived(this.type, this.data);

  @override
  List<Object?> get props => [type, data];
}
