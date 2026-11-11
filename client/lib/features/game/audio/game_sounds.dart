import 'package:wordchain/core/services/audio_service.dart';
import 'package:wordchain/features/game/bloc/game_bloc.dart';
import 'package:wordchain/features/game/data/game_constants.dart';

/// The sounds a [GameState] change should make. Pure (no audio engine), so the
/// mapping is unit-tested; `GameSoundListener` plays the result.
///
/// At most one "main" sound per change (a word the player scored is the
/// accepted chime *or* the streak *or* the long-word run, never a stack of
/// them), plus the small ones that go with it.
List<Sound> soundsForTransition(GameState prev, GameState curr) {
  if (curr is GameActive) {
    if (prev is! GameActive) {
      // Entering a match: only an online one has a "found you" moment (a solo
      // or vs-AI start, or a continue after a loss, is silent).
      return curr.isMultiplayer && prev is GameLoading
          ? const [Sound.matchFound]
          : const [];
    }
    return _activeSounds(prev, curr);
  }
  if (curr is GameOver) return _overSounds(prev, curr);
  return const [];
}

List<Sound> _activeSounds(GameActive prev, GameActive curr) {
  final out = <Sound>[];

  if (curr.wordChain.length > prev.wordChain.length) {
    final word = curr.wordChain.last;
    if (_isMine(curr)) {
      if (GameBloc.letterCount(word) > GameConstants.longWordBonusFrom) {
        out.add(Sound.longWord);
      } else if (curr.streak >= 3 && curr.streak > prev.streak) {
        out.add(Sound.streak);
      } else {
        out.add(Sound.accepted);
      }
    } else {
      out.add(Sound.oppWord);
    }
    out.add(Sound.tileLand);
    return out;
  }

  if (curr.livesRemaining < prev.livesRemaining) {
    out.add(Sound.lifeLost);
  } else if (curr.shieldActive != prev.shieldActive ||
      curr.usedPowerups.length > prev.usedPowerups.length &&
          curr.usedPowerups.contains('shield') &&
          !prev.usedPowerups.contains('shield')) {
    out.add(Sound.shield);
  } else if (curr.hintWord != null && curr.hintWord != prev.hintWord) {
    out.add(Sound.hint);
  } else if (curr.usedPowerups.contains('extra_time') &&
      !prev.usedPowerups.contains('extra_time')) {
    out.add(Sound.extraTime);
  } else if (curr.tauntSeq > prev.tauntSeq && !curr.tauntFromMe) {
    out.add(Sound.taunt);
  } else if (curr.isMyTurn &&
      curr.turnTimeRemaining < prev.turnTimeRemaining &&
      curr.turnTimeRemaining > 0 &&
      curr.turnTimeRemaining <= GameConstants.tickFromSeconds) {
    out.add(Sound.tick);
  }
  return out;
}

/// Whether the newest word of [s] is the local player's. Solo has no owners
/// list (every word is mine); vs-AI uses 'player'/'ai'; online uses user ids.
bool _isMine(GameActive s) {
  if (s.wordOwners.length != s.wordChain.length || s.wordOwners.isEmpty) {
    return true;
  }
  final owner = s.wordOwners.last;
  return owner == null || owner == s.myPlayerId;
}

List<Sound> _overSounds(GameState prev, GameOver curr) {
  // The «جام» change arrives a moment after game_over.
  if (prev is GameOver) {
    if (prev.rating == null && curr.rating != null && curr.rating!.delta != 0) {
      return [curr.rating!.delta > 0 ? Sound.ratingUp : Sound.ratingDown];
    }
    // A decided result after an undecided loss (the continue offer ran out, or
    // the opponent's game_over came in).
    if (prev.iWon == null && curr.iWon != null) {
      return [curr.iWon! ? Sound.win : Sound.lose];
    }
    return const [];
  }
  if (prev is! GameActive) return const [];
  final won = curr.iWon;
  if (won != null) return [won ? Sound.win : Sound.lose];
  switch (curr.reason) {
    case 'timeout':
      return const [Sound.timeout];
    case 'invalid_word':
      return const [Sound.rejected];
    default:
      return const []; // ended by the player, or a disconnect
  }
}
