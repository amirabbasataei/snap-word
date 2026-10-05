import 'package:equatable/equatable.dart';

sealed class LobbyState extends Equatable {
  const LobbyState();
}

class LobbyIdle extends LobbyState {
  const LobbyIdle();

  @override
  List<Object?> get props => [];
}

class LobbySearching extends LobbyState {
  final String mode;
  final int elapsedSeconds;

  const LobbySearching({required this.mode, required this.elapsedSeconds});

  LobbySearching copyWith({int? elapsedSeconds}) => LobbySearching(
        mode: mode,
        elapsedSeconds: elapsedSeconds ?? this.elapsedSeconds,
      );

  @override
  List<Object?> get props => [mode, elapsedSeconds];
}

class LobbyMatchFound extends LobbyState {
  final String roomId;
  final String mode;

  const LobbyMatchFound({required this.roomId, required this.mode});

  @override
  List<Object?> get props => [roomId, mode];
}

class LobbyError extends LobbyState {
  final String message;

  /// The player can't pay the entry fee — the screen shows the earn-coins
  /// dialog instead of a retry block.
  final bool insufficientCoins;

  const LobbyError(this.message, {this.insufficientCoins = false});

  @override
  List<Object?> get props => [message, insufficientCoins];
}
