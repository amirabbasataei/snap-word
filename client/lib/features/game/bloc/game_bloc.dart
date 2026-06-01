import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:logger/logger.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wordchain/core/database/app_database.dart';
import 'package:wordchain/core/services/dictionary_service.dart';
import 'package:wordchain/core/services/sync_service.dart';
import 'package:wordchain/features/game/bloc/game_event.dart';
import 'package:wordchain/features/game/bloc/game_state.dart';
import 'package:wordchain/features/game/data/game_constants.dart';
import 'package:wordchain/features/game/data/game_repository.dart';

export 'game_event.dart';
export 'game_state.dart';

class GameBloc extends Bloc<GameEvent, GameState> {
  final GameRepository _gameRepository;
  final DictionaryService _dictionaryService;
  final StatsDao _statsDao;
  final SyncService _syncService;
  final SharedPreferences _prefs;
  final Logger _log = Logger();

  Timer? _turnTimer;
  Timer? _continueTimer;
  DateTime? _turnStartTime;
  int _timeLimitSec = GameConstants.classicTurnTimerSec;

  GameBloc({
    required GameRepository gameRepository,
    required DictionaryService dictionaryService,
    required StatsDao statsDao,
    required SyncService syncService,
    required SharedPreferences prefs,
  })  : _gameRepository = gameRepository,
        _dictionaryService = dictionaryService,
        _statsDao = statsDao,
        _syncService = syncService,
        _prefs = prefs,
        super(const GameInitial()) {
    on<GameStarted>(_onGameStarted);
    on<WordSubmitted>(_onWordSubmitted);
    on<HintRequested>(_onHintRequested);
    on<GameEnded>(_onGameEnded);
    on<ContinueRequested>(_onContinueRequested);
    on<AcceptDefeat>(_onAcceptDefeat);
    on<GameTimerTicked>(_onTimerTicked);
    on<ContinueTimerTicked>(_onContinueTimerTicked);
  }

  bool get _isGuest => _prefs.getString('jwt_access_token') == null;

  @override
  Future<void> close() {
    _turnTimer?.cancel();
    _continueTimer?.cancel();
    return super.close();
  }

  void _startTurnTimer() {
    _turnTimer?.cancel();
    _turnTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => add(const GameTimerTicked()),
    );
  }

  void _stopTurnTimer() {
    _turnTimer?.cancel();
    _turnTimer = null;
  }

  void _startContinueTimer() {
    _continueTimer?.cancel();
    _continueTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => add(const ContinueTimerTicked()),
    );
  }

  void _stopContinueTimer() {
    _continueTimer?.cancel();
    _continueTimer = null;
  }

  Future<void> _onGameStarted(
    GameStarted event,
    Emitter<GameState> emit,
  ) async {
    emit(const GameLoading());
    try {
      int localMatchId;
      String mode;
      String opponentType;
      List<String> wordChain;
      int score;

      if (event.resumeMatchId != null) {
        final match = await _gameRepository.getMatchById(event.resumeMatchId!);
        if (match == null) {
          emit(const GameError('Could not find match to resume.'));
          return;
        }
        localMatchId = match.id;
        mode = match.mode;
        opponentType = match.opponentType;
        wordChain = List<String>.from(jsonDecode(match.wordChain) as List);
        score = match.score;
      } else {
        mode = event.mode;
        opponentType = event.opponentType;
        wordChain = [];
        score = 0;
        localMatchId = await _gameRepository.startLocalGame(mode, opponentType);
      }

      _timeLimitSec = mode == 'time_attack'
          ? GameConstants.timeAttackTurnTimerSec
          : GameConstants.classicTurnTimerSec;
      _turnStartTime = DateTime.now();

      emit(GameActive(
        localMatchId: localMatchId,
        mode: mode,
        opponentType: opponentType,
        wordChain: wordChain,
        wordScores: const [],
        score: score,
        streak: 0,
        turnTimeRemaining: _timeLimitSec,
        matchTimeRemaining: mode == 'time_attack'
            ? GameConstants.timeAttackMatchDurationSec
            : null,
        nextStartLetter: wordChain.isNotEmpty
            ? wordChain.last[wordChain.last.length - 1]
            : null,
        guestHintUsesLeft:
            _isGuest ? GameConstants.guestHintUsesPerSession : 999,
        continueUsed: false,
      ));

      _startTurnTimer();
    } catch (e) {
      _log.e('GameStarted failed', error: e);
      emit(GameError(e.toString()));
    }
  }

  Future<void> _onWordSubmitted(
    WordSubmitted event,
    Emitter<GameState> emit,
  ) async {
    final active = state;
    if (active is! GameActive) return;

    _stopTurnTimer();

    final word = event.word.trim().toLowerCase();

    // Validation order matches CLAUDE.md rules
    String? rejectionReason;

    if (word.length < GameConstants.minWordLength) {
      rejectionReason = 'too_short';
    } else if (!RegExp(r'^[a-z]+$').hasMatch(word)) {
      rejectionReason = 'invalid_characters';
    } else if (active.nextStartLetter != null &&
        word[0] != active.nextStartLetter) {
      rejectionReason = 'wrong_letter';
    } else if (await _gameRepository.isWordUsed(active.localMatchId, word)) {
      rejectionReason = 'already_used';
    } else if (!_dictionaryService.isValid(word)) {
      rejectionReason = 'not_in_dictionary';
    }

    if (rejectionReason != null) {
      await _handleGameOver(
        emit: emit,
        active: active,
        reason: 'invalid_word',
        rejectedWord: word,
        rejectionReason: rejectionReason,
      );
      return;
    }

    // Word accepted
    final responseTimeSec = _turnStartTime != null
        ? DateTime.now().difference(_turnStartTime!).inMilliseconds / 1000.0
        : _timeLimitSec.toDouble();

    final turnScore = _calculateScore(
      word,
      responseTimeSec,
      active.streak,
      _timeLimitSec.toDouble(),
    );

    final newChain = [...active.wordChain, word];
    final newScores = [...active.wordScores, turnScore];

    await _gameRepository.recordAcceptedWord(active.localMatchId, newChain);

    _turnStartTime = DateTime.now();
    _startTurnTimer();

    emit(active.copyWith(
      wordChain: newChain,
      wordScores: newScores,
      score: active.score + turnScore,
      streak: active.streak + 1,
      turnTimeRemaining: _timeLimitSec,
      nextStartLetter: word[word.length - 1],
      hintWord: null,
    ));
  }

  Future<void> _onHintRequested(
    HintRequested event,
    Emitter<GameState> emit,
  ) async {
    final active = state;
    if (active is! GameActive) return;
    if (_isGuest && active.guestHintUsesLeft <= 0) return;

    final startLetter = active.nextStartLetter ?? 'a';
    final suggestions = _dictionaryService.suggestWords(startLetter);
    if (suggestions.isEmpty) return;

    final hint = suggestions[Random().nextInt(suggestions.length)];
    final newHintUses = _isGuest
        ? max(0, active.guestHintUsesLeft - 1)
        : active.guestHintUsesLeft;

    emit(active.copyWith(hintWord: hint, guestHintUsesLeft: newHintUses));
  }

  Future<void> _onTimerTicked(
    GameTimerTicked event,
    Emitter<GameState> emit,
  ) async {
    final active = state;
    if (active is! GameActive) return;

    final newTurnTime = active.turnTimeRemaining - 1;
    final newMatchTime = active.matchTimeRemaining != null
        ? active.matchTimeRemaining! - 1
        : null;

    // Time Attack match timer expired
    if (newMatchTime != null && newMatchTime <= 0) {
      _stopTurnTimer();
      await _finalizeGame(
        emit: emit,
        localMatchId: active.localMatchId,
        mode: active.mode,
        reason: 'time_limit',
        score: active.score,
        wordChain: active.wordChain,
        canContinue: false,
      );
      return;
    }

    // Turn timer expired
    if (newTurnTime <= 0) {
      _stopTurnTimer();
      await _handleGameOver(
        emit: emit,
        active: active,
        reason: 'timeout',
        rejectedWord: null,
        rejectionReason: null,
      );
      return;
    }

    emit(active.copyWith(
      turnTimeRemaining: newTurnTime,
      matchTimeRemaining: newMatchTime,
    ));
  }

  Future<void> _onGameEnded(
    GameEnded event,
    Emitter<GameState> emit,
  ) async {
    final active = state;
    if (active is! GameActive) return;

    _stopTurnTimer();
    await _finalizeGame(
      emit: emit,
      localMatchId: active.localMatchId,
      mode: active.mode,
      reason: 'ended_by_user',
      score: active.score,
      wordChain: active.wordChain,
      canContinue: false,
    );
  }

  Future<void> _onContinueRequested(
    ContinueRequested event,
    Emitter<GameState> emit,
  ) async {
    final over = state;
    if (over is! GameOver || !over.canContinue) return;

    _stopContinueTimer();

    _timeLimitSec = over.mode == 'time_attack'
        ? GameConstants.timeAttackTurnTimerSec
        : GameConstants.classicTurnTimerSec;
    _turnStartTime = DateTime.now();

    final chain = over.wordChain;
    emit(GameActive(
      localMatchId: over.localMatchId,
      mode: over.mode,
      opponentType: 'solo',
      wordChain: chain,
      wordScores: const [],
      score: over.score,
      streak: 0,
      turnTimeRemaining: _timeLimitSec,
      matchTimeRemaining: null,
      nextStartLetter: chain.isNotEmpty
          ? chain.last[chain.last.length - 1]
          : null,
      guestHintUsesLeft:
          _isGuest ? GameConstants.guestHintUsesPerSession : 999,
      continueUsed: true,
    ));

    _startTurnTimer();
  }

  Future<void> _onAcceptDefeat(
    AcceptDefeat event,
    Emitter<GameState> emit,
  ) async {
    final over = state;
    if (over is! GameOver) return;

    _stopContinueTimer();
    await _saveAndEmitFinal(emit, over);
  }

  Future<void> _onContinueTimerTicked(
    ContinueTimerTicked event,
    Emitter<GameState> emit,
  ) async {
    final over = state;
    if (over is! GameOver || !over.canContinue) return;

    final newTime = over.continueTimeRemaining - 1;
    if (newTime <= 0) {
      _stopContinueTimer();
      await _saveAndEmitFinal(emit, over);
    } else {
      emit(over.copyWith(continueTimeRemaining: newTime));
    }
  }

  Future<void> _handleGameOver({
    required Emitter<GameState> emit,
    required GameActive active,
    required String reason,
    required String? rejectedWord,
    required String? rejectionReason,
  }) async {
    final canContinue = active.mode == 'classic' && !active.continueUsed;

    if (canContinue) {
      emit(GameOver(
        localMatchId: active.localMatchId,
        mode: active.mode,
        reason: reason,
        rejectedWord: rejectedWord,
        rejectionReason: rejectionReason,
        score: active.score,
        chainLength: active.wordChain.length,
        wordChain: active.wordChain,
        canContinue: true,
        continueTimeRemaining: GameConstants.continueWindowSec,
        isSaved: false,
      ));
      _startContinueTimer();
    } else {
      await _finalizeGame(
        emit: emit,
        localMatchId: active.localMatchId,
        mode: active.mode,
        reason: reason,
        score: active.score,
        wordChain: active.wordChain,
        canContinue: false,
        rejectedWord: rejectedWord,
        rejectionReason: rejectionReason,
      );
    }
  }

  Future<void> _finalizeGame({
    required Emitter<GameState> emit,
    required int localMatchId,
    required String mode,
    required String reason,
    required int score,
    required List<String> wordChain,
    required bool canContinue,
    String? rejectedWord,
    String? rejectionReason,
  }) async {
    final over = GameOver(
      localMatchId: localMatchId,
      mode: mode,
      reason: reason,
      rejectedWord: rejectedWord,
      rejectionReason: rejectionReason,
      score: score,
      chainLength: wordChain.length,
      wordChain: wordChain,
      canContinue: false,
      continueTimeRemaining: 0,
      isSaved: false,
    );
    emit(over);
    await _saveAndEmitFinal(emit, over);
  }

  Future<void> _saveAndEmitFinal(
    Emitter<GameState> emit,
    GameOver over,
  ) async {
    try {
      await _gameRepository.finishLocalGame(
        over.localMatchId,
        over.score,
        over.wordChain,
      );

      final longestWord = over.wordChain.isEmpty
          ? null
          : over.wordChain.reduce(
              (a, b) => a.length >= b.length ? a : b,
            );

      await _statsDao.recordGameResult(
        score: over.score,
        longestWord: longestWord,
      );

      // Fire-and-forget: do not await
      _syncService.sync().ignore();

      emit(over.copyWith(isSaved: true));
    } catch (e) {
      _log.e('Failed to save game', error: e);
      // Still dismiss UI even on error
      emit(over.copyWith(isSaved: true));
    }
  }

  static int _calculateScore(
    String word,
    double responseTimeSec,
    int streak,
    double timeLimitSec,
  ) {
    final baseScore = word.length * 10;
    final speedBonus = ((timeLimitSec - responseTimeSec) * 2)
        .clamp(0.0, double.infinity)
        .toInt();
    final streakBonus = streak >= 3 ? (baseScore * 0.5).toInt() : 0;
    return baseScore + speedBonus + streakBonus;
  }
}
