import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:logger/logger.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wordchain/core/database/app_database.dart';
import 'package:wordchain/core/services/ai_opponent.dart';
import 'package:wordchain/core/services/dictionary_service.dart';
import 'package:wordchain/core/services/sync_service.dart';
import 'package:wordchain/core/services/websocket_service.dart';
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
  final WebSocketService _wsService;
  final Logger _log = Logger();

  Timer? _turnTimer;
  Timer? _continueTimer;
  Timer? _opponentContinueTimer;
  Timer? _aiTimer;
  StreamSubscription<WebSocketEvent>? _wsSub;
  DateTime? _turnStartTime;
  int _timeLimitSec = GameConstants.classicTurnTimerSec;

  AIDifficultyConfig _aiDifficulty = aiDifficulties['easy']!;

  // Multiplayer session state (reset on each GameStarted)
  bool _isMultiplayer = false;
  String _myPlayerId = '';
  bool _wsConnected = false;

  GameBloc({
    required GameRepository gameRepository,
    required DictionaryService dictionaryService,
    required StatsDao statsDao,
    required SyncService syncService,
    required SharedPreferences prefs,
    required WebSocketService wsService,
  })  : _gameRepository = gameRepository,
        _dictionaryService = dictionaryService,
        _statsDao = statsDao,
        _syncService = syncService,
        _prefs = prefs,
        _wsService = wsService,
        super(const GameInitial()) {
    on<GameStarted>(_onGameStarted);
    on<WordSubmitted>(_onWordSubmitted);
    on<HintRequested>(_onHintRequested);
    on<GameEnded>(_onGameEnded);
    on<ContinueRequested>(_onContinueRequested);
    on<AcceptDefeat>(_onAcceptDefeat);
    on<GameTimerTicked>(_onTimerTicked);
    on<ContinueTimerTicked>(_onContinueTimerTicked);
    on<OpponentContinueTimerTicked>(_onOpponentContinueTimerTicked);
    on<AITurnStarted>(_onAITurnStarted);
    on<WsEventReceived>(_onWsEventReceived);
  }

  bool get _isGuest => _prefs.getString('jwt_access_token') == null;

  bool _isVsAI(GameActive state) => isVsAI(state.opponentType);

  @override
  Future<void> close() async {
    _turnTimer?.cancel();
    _continueTimer?.cancel();
    _opponentContinueTimer?.cancel();
    _aiTimer?.cancel();
    await _wsSub?.cancel();
    if (_wsConnected) {
      _wsService.disconnect();
      _wsConnected = false;
    }
    return super.close();
  }

  // ---------------------------------------------------------------------------
  // Timers (solo/AI only)
  // ---------------------------------------------------------------------------

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

  void _startOpponentContinueTimer() {
    _opponentContinueTimer?.cancel();
    _opponentContinueTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => add(const OpponentContinueTimerTicked()),
    );
  }

  void _stopOpponentContinueTimer() {
    _opponentContinueTimer?.cancel();
    _opponentContinueTimer = null;
  }

  // ---------------------------------------------------------------------------
  // GameStarted
  // ---------------------------------------------------------------------------

  Future<void> _onGameStarted(
    GameStarted event,
    Emitter<GameState> emit,
  ) async {
    emit(const GameLoading());

    _isMultiplayer = event.roomId != null;
    _myPlayerId = event.myPlayerId ?? '';

    if (_isMultiplayer) {
      _connectMultiplayerWs(event.roomId!);
      // State stays GameLoading until 'game_start' WS event arrives
      return;
    }

    // --- Solo / AI path ---
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

      final vsAI = isVsAI(opponentType);
      if (vsAI) {
        _aiDifficulty = aiDifficulties[resolveAIDifficulty(opponentType)] ??
            aiDifficulties['easy']!;
      }

      _timeLimitSec = mode == 'time_attack'
          ? GameConstants.timeAttackTurnTimerSec
          : GameConstants.classicTurnTimerSec;
      _turnStartTime = DateTime.now();

      final difficultyLabel = vsAI
          ? resolveAIDifficulty(opponentType)[0].toUpperCase() +
              resolveAIDifficulty(opponentType).substring(1)
          : '';

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
            : event.startLetter,
        guestHintUsesLeft:
            _isGuest ? GameConstants.guestHintUsesPerSession : 999,
        continueUsed: false,
        isMyTurn: true,
        myPlayerId: vsAI ? 'player' : null,
        opponentId: vsAI ? 'ai' : null,
        opponentUsername: vsAI ? 'AI ($difficultyLabel)' : null,
        opponentScore: 0,
        wordOwners: vsAI
            ? List<String?>.filled(wordChain.length, 'player')
            : const [],
      ));

      _startTurnTimer();
    } catch (e) {
      _log.e('GameStarted failed', error: e);
      emit(GameError(e.toString()));
    }
  }

  void _connectMultiplayerWs(String roomId) {
    final token = _prefs.getString('jwt_access_token') ?? '';
    final uri = token.isNotEmpty
        ? 'ws://10.0.2.2:8080/api/v1/ws/game/$roomId?token=$token'
        : 'ws://10.0.2.2:8080/api/v1/ws/game/$roomId';

    _wsSub?.cancel();
    _wsService.connect(uri);
    _wsConnected = true;
    _wsSub = _wsService.events.listen(
      (e) => add(WsEventReceived(e.type, e.data)),
    );
  }

  // ---------------------------------------------------------------------------
  // WordSubmitted
  // ---------------------------------------------------------------------------

  Future<void> _onWordSubmitted(
    WordSubmitted event,
    Emitter<GameState> emit,
  ) async {
    final active = state;
    if (active is! GameActive) return;

    final word = event.word.trim().toLowerCase();

    if (_isMultiplayer) {
      // Server handles all validation and state updates
      _wsService.send({'type': 'submit_word', 'word': word});
      return;
    }

    _stopTurnTimer();

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
    final newOwners = _isVsAI(active)
        ? [...active.wordOwners, 'player']
        : active.wordOwners;

    await _gameRepository.recordAcceptedWord(active.localMatchId, newChain);

    // Daily challenge ends automatically after reaching the max word count
    if (active.mode == 'daily' && newChain.length >= GameConstants.dailyMaxWords) {
      _stopTurnTimer();
      await _finalizeGame(
        emit: emit,
        localMatchId: active.localMatchId,
        mode: active.mode,
        reason: 'max_words',
        score: active.score + turnScore,
        wordChain: newChain,
        canContinue: false,
        opponentScore: active.opponentScore,
      );
      return;
    }

    if (_isVsAI(active)) {
      // Switch to AI turn — restart turn timer so match timer keeps ticking
      emit(active.copyWith(
        wordChain: newChain,
        wordScores: newScores,
        wordOwners: newOwners,
        score: active.score + turnScore,
        streak: active.streak + 1,
        turnTimeRemaining: _timeLimitSec,
        nextStartLetter: word[word.length - 1],
        hintWord: null,
        isMyTurn: false,
      ));
      _turnStartTime = DateTime.now();
      _startTurnTimer();
      _scheduleAITurn();
      return;
    }

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

  // ---------------------------------------------------------------------------
  // HintRequested
  // ---------------------------------------------------------------------------

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

  // ---------------------------------------------------------------------------
  // AI opponent (offline VS AI)
  // ---------------------------------------------------------------------------

  void _scheduleAITurn() {
    _aiTimer?.cancel();
    _aiTimer = Timer(
      Duration(milliseconds: _aiDifficulty.delayMs),
      () => add(const AITurnStarted()),
    );
  }

  Future<void> _onAITurnStarted(
    AITurnStarted event,
    Emitter<GameState> emit,
  ) async {
    final active = state;
    if (active is! GameActive) return;
    if (active.isMyTurn) return;
    if (!_isVsAI(active)) return;

    _stopTurnTimer();

    final usedWords = <String>{};
    for (final w in active.wordChain) {
      usedWords.add(w.toLowerCase());
    }

    final rng = Random();
    final shouldMistake = rng.nextDouble() < _aiDifficulty.mistakeRate;

    if (shouldMistake) {
      await _handleAILoss(
        emit: emit,
        active: active,
        reason: 'invalid_word',
        rejectedWord: '???',
      );
      return;
    }

    final startLetter = active.nextStartLetter;
    final aiWord = selectAIWord(
      letter: startLetter,
      usedWords: usedWords,
      dictionary: _dictionaryService,
      difficulty: _aiDifficulty,
    );

    if (aiWord == null) {
      await _handleAILoss(
        emit: emit,
        active: active,
        reason: 'no_words',
      );
      return;
    }

    // Validate AI word (safety check)
    if (await _gameRepository.isWordUsed(active.localMatchId, aiWord)) {
      await _handleAILoss(
        emit: emit,
        active: active,
        reason: 'invalid_word',
        rejectedWord: aiWord,
      );
      return;
    }

    // Calculate AI score
    final turnScore = _calculateScore(
      aiWord,
      _aiDifficulty.delayMs / 1000.0,
      0,
      _timeLimitSec.toDouble(),
    );

    final newChain = [...active.wordChain, aiWord];
    final newOwners = [...active.wordOwners, 'ai'];

    await _gameRepository.recordAcceptedWord(active.localMatchId, newChain);

    // Switch back to player
    _turnStartTime = DateTime.now();
    _startTurnTimer();

    emit(active.copyWith(
      wordChain: newChain,
      wordOwners: newOwners,
      opponentScore: active.opponentScore + turnScore,
      turnTimeRemaining: _timeLimitSec,
      nextStartLetter: aiWord[aiWord.length - 1],
      isMyTurn: true,
    ));
  }

  Future<void> _handleAILoss({
    required Emitter<GameState> emit,
    required GameActive active,
    required String reason,
    String? rejectedWord,
  }) async {
    _aiTimer?.cancel();
    _stopContinueTimer();

    await _finalizeGame(
      emit: emit,
      localMatchId: active.localMatchId,
      mode: active.mode,
      reason: reason == 'timeout' ? 'timeout' : 'invalid_word',
      score: active.score,
      wordChain: active.wordChain,
      canContinue: false,
      opponentScore: active.opponentScore,
      opponentType: active.opponentType,
    );
  }

  // ---------------------------------------------------------------------------
  // Timer ticks (solo/AI)
  // ---------------------------------------------------------------------------

  Future<void> _onTimerTicked(
    GameTimerTicked event,
    Emitter<GameState> emit,
  ) async {
    final active = state;
    if (active is! GameActive) return;

    final vsAI = _isVsAI(active);
    final newTurnTime = active.turnTimeRemaining - 1;
    final newMatchTime = active.matchTimeRemaining != null
        ? active.matchTimeRemaining! - 1
        : null;

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
        opponentScore: active.opponentScore,
      );
      return;
    }

    if (newTurnTime <= 0) {
      _stopTurnTimer();
      if (vsAI && !active.isMyTurn) {
        await _handleAILoss(
          emit: emit,
          active: active,
          reason: 'timeout',
        );
        return;
      }
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

  // ---------------------------------------------------------------------------
  // GameEnded (user taps end game — solo/AI only)
  // ---------------------------------------------------------------------------

  Future<void> _onGameEnded(
    GameEnded event,
    Emitter<GameState> emit,
  ) async {
    final active = state;
    if (active is! GameActive) return;

    _stopTurnTimer();
    _aiTimer?.cancel();
    await _finalizeGame(
      emit: emit,
      localMatchId: active.localMatchId,
      mode: active.mode,
      reason: 'ended_by_user',
      score: active.score,
      wordChain: active.wordChain,
      canContinue: false,
      opponentScore: active.opponentScore,
    );
  }

  // ---------------------------------------------------------------------------
  // ContinueRequested
  // ---------------------------------------------------------------------------

  Future<void> _onContinueRequested(
    ContinueRequested event,
    Emitter<GameState> emit,
  ) async {
    final over = state;
    if (over is! GameOver || !over.canContinue) return;

    _stopContinueTimer();

    if (_isMultiplayer) {
      _wsService.send({'type': 'continue', 'method': event.method});
      // State will be updated by WS event (continue_decision)
      return;
    }

    _timeLimitSec = over.mode == 'time_attack'
        ? GameConstants.timeAttackTurnTimerSec
        : GameConstants.classicTurnTimerSec;
    _turnStartTime = DateTime.now();

    final opponentType = over.opponentType ?? 'solo';
    final vsAI = isVsAI(opponentType);
    if (vsAI) {
      _aiDifficulty = aiDifficulties[resolveAIDifficulty(opponentType)] ??
          aiDifficulties['easy']!;
    }
    final difficultyLabel = vsAI
        ? resolveAIDifficulty(opponentType)[0].toUpperCase() +
            resolveAIDifficulty(opponentType).substring(1)
        : '';

    final chain = over.wordChain;
    emit(GameActive(
      localMatchId: over.localMatchId,
      mode: over.mode,
      opponentType: opponentType,
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
      isMyTurn: true,
      myPlayerId: vsAI ? 'player' : null,
      opponentId: vsAI ? 'ai' : null,
      opponentUsername: vsAI ? 'AI ($difficultyLabel)' : null,
      opponentScore: 0,
      wordOwners: vsAI
          ? List<String?>.filled(chain.length, 'player')
          : const [],
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

    if (_isMultiplayer) {
      _wsService.send({'type': 'continue', 'method': 'forfeit'});
    }

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

  Future<void> _onOpponentContinueTimerTicked(
    OpponentContinueTimerTicked event,
    Emitter<GameState> emit,
  ) async {
    final active = state;
    if (active is! GameActive || !active.opponentContinueWindowActive) return;

    final newTime = active.opponentContinueWindowRemaining - 1;
    if (newTime <= 0) {
      _stopOpponentContinueTimer();
      emit(active.copyWith(opponentContinueWindowActive: false, opponentContinueWindowRemaining: 0));
    } else {
      emit(active.copyWith(opponentContinueWindowRemaining: newTime));
    }
  }

  // ---------------------------------------------------------------------------
  // WebSocket event handler (multiplayer)
  // ---------------------------------------------------------------------------

  Future<void> _onWsEventReceived(
    WsEventReceived event,
    Emitter<GameState> emit,
  ) async {
    switch (event.type) {
      case 'game_start':
        _handleWsGameStart(event.data, emit);
      case 'word_accepted':
        _handleWsWordAccepted(event.data, emit);
      case 'word_rejected':
        _handleWsWordRejected(event.data, emit);
      case 'turn_change':
        _handleWsTurnChange(event.data, emit);
      case 'timer_update':
        _handleWsTimerUpdate(event.data, emit);
      case 'loss_event':
        await _handleWsLossEvent(event.data, emit);
      case 'continue_window':
        _handleWsContinueWindow(event.data, emit);
      case 'continue_decision':
        _handleWsContinueDecision(event.data, emit);
      case 'game_over':
        _handleWsGameOver(event.data, emit);
      case 'opponent_disconnected':
        _handleWsOpponentDisconnected(emit);
      default:
        break;
    }
  }

  void _handleWsGameStart(Map<String, dynamic> data, Emitter<GameState> emit) {
    final gameState = data['state'] as Map<String, dynamic>? ?? data;
    final players = (gameState['players'] as List<dynamic>?) ?? [];
    final mode = gameState['mode'] as String? ?? 'classic';
    final currentPlayer = gameState['current_player'] as String? ?? '';

    _timeLimitSec = mode == 'time_attack'
        ? GameConstants.timeAttackTurnTimerSec
        : GameConstants.classicTurnTimerSec;

    String? opponentId;
    String? opponentUsername;
    for (final p in players) {
      final pm = p as Map<String, dynamic>;
      if (pm['id'] != _myPlayerId) {
        opponentId = pm['id'] as String?;
        opponentUsername = pm['username'] as String?;
      }
    }

    emit(GameActive(
      localMatchId: -1,
      mode: mode,
      opponentType: 'multiplayer',
      wordChain: const [],
      wordScores: const [],
      score: 0,
      streak: 0,
      turnTimeRemaining: _timeLimitSec,
      matchTimeRemaining: mode == 'time_attack'
          ? GameConstants.timeAttackMatchDurationSec
          : null,
      guestHintUsesLeft: 999,
      continueUsed: false,
      isMyTurn: currentPlayer == _myPlayerId || currentPlayer.isEmpty,
      myPlayerId: _myPlayerId,
      opponentId: opponentId,
      opponentUsername: opponentUsername,
    ));
  }

  void _handleWsWordAccepted(
    Map<String, dynamic> data,
    Emitter<GameState> emit,
  ) {
    final active = state;
    if (active is! GameActive) return;

    final word = data['word'] as String? ?? '';
    final score = data['score'] as int? ?? 0;
    final nextLetter = (data['next_letter'] as String?) ?? '';
    final playerId = data['player_id'] as String? ?? '';

    final isMyWord = playerId == _myPlayerId;

    emit(active.copyWith(
      wordChain: [...active.wordChain, word],
      wordOwners: [...active.wordOwners, playerId],
      wordScores: isMyWord ? [...active.wordScores, score] : active.wordScores,
      score: isMyWord ? active.score + score : active.score,
      opponentScore: !isMyWord ? active.opponentScore + score : active.opponentScore,
      streak: isMyWord ? active.streak + 1 : 0,
      nextStartLetter: nextLetter.isNotEmpty ? nextLetter : null,
      isMyTurn: !isMyWord, // alternating turns
      turnTimeRemaining: _timeLimitSec,
    ));
  }

  void _handleWsWordRejected(
    Map<String, dynamic> data,
    Emitter<GameState> emit,
  ) {
    // word_rejected is followed by loss_event; just log here
    final reason = data['reason'] as String?;
    _log.d('word_rejected: $reason');
  }

  void _handleWsTurnChange(
    Map<String, dynamic> data,
    Emitter<GameState> emit,
  ) {
    final active = state;
    if (active is! GameActive) return;

    final playerId = data['player_id'] as String? ?? '';
    emit(active.copyWith(isMyTurn: playerId == _myPlayerId));
  }

  void _handleWsTimerUpdate(
    Map<String, dynamic> data,
    Emitter<GameState> emit,
  ) {
    final active = state;
    if (active is! GameActive) return;

    final remainingMs = data['remaining_ms'] as int? ?? 0;
    emit(active.copyWith(turnTimeRemaining: (remainingMs / 1000).ceil()));
  }

  Future<void> _handleWsLossEvent(
    Map<String, dynamic> data,
    Emitter<GameState> emit,
  ) async {
    final active = state;
    if (active is! GameActive) return;

    final playerId = data['player_id'] as String? ?? '';
    final reason = data['reason'] as String? ?? 'invalid_word';

    if (playerId == _myPlayerId) {
      // My loss — show continue prompt (Classic only)
      final canContinue = active.mode == 'classic' && !active.continueUsed;
      emit(GameOver(
        localMatchId: -1,
        mode: active.mode,
        reason: reason,
        score: active.score,
        chainLength: active.wordChain.length,
        wordChain: active.wordChain,
        canContinue: canContinue,
        continueTimeRemaining: GameConstants.continueWindowSec,
        isSaved: false,
        opponentScore: active.opponentScore,
      ));
      if (canContinue) _startContinueTimer();
    } else {
      // Opponent lost — show "Opponent deciding..." overlay
      emit(active.copyWith(
        opponentContinueWindowActive: true,
        opponentContinueWindowRemaining: GameConstants.continueWindowSec,
      ));
      _startOpponentContinueTimer();
    }
  }

  void _handleWsContinueWindow(
    Map<String, dynamic> data,
    Emitter<GameState> emit,
  ) {
    final active = state;
    if (active is! GameActive) return;

    final playerId = data['player_id'] as String? ?? '';
    if (playerId != _myPlayerId) {
      _stopOpponentContinueTimer();
      emit(active.copyWith(
        opponentContinueWindowActive: true,
        opponentContinueWindowRemaining: GameConstants.continueWindowSec,
      ));
      _startOpponentContinueTimer();
    }
  }

  void _handleWsContinueDecision(
    Map<String, dynamic> data,
    Emitter<GameState> emit,
  ) {
    final active = state;
    if (active is! GameActive) return;

    _stopOpponentContinueTimer();
    final decision = data['decision'] as String? ?? 'forfeit';

    if (decision == 'continue') {
      emit(active.copyWith(
        opponentContinueWindowActive: false,
        opponentContinueWindowRemaining: 0,
        continueUsed: true,
        isMyTurn: true,
      ));
    }
    // If forfeit — game_over event will follow
  }

  void _handleWsGameOver(
    Map<String, dynamic> data,
    Emitter<GameState> emit,
  ) {
    final active = state is GameActive ? state as GameActive : null;
    final scores = data['scores'] as Map<String, dynamic>? ?? {};
    final winner = data['winner'] as String?;

    final myScore = scores[_myPlayerId] as int? ?? (active?.score ?? 0);
    final opponentScore = scores.entries
        .where((e) => e.key != _myPlayerId)
        .fold<int>(0, (sum, e) => sum + (e.value as int? ?? 0));

    _stopContinueTimer();
    _stopOpponentContinueTimer();

    emit(GameOver(
      localMatchId: -1,
      mode: active?.mode ?? 'classic',
      reason: 'game_over',
      score: myScore,
      chainLength: active?.wordChain.length ?? 0,
      wordChain: active?.wordChain ?? const [],
      canContinue: false,
      continueTimeRemaining: 0,
      isSaved: true, // server manages persistence
      winnerId: winner,
      opponentScore: opponentScore,
    ));
  }

  void _handleWsOpponentDisconnected(Emitter<GameState> emit) {
    final active = state;
    if (active is! GameActive) return;

    emit(active.copyWith(opponentDisconnected: true));
    // game_over event will follow if disconnect persists past the 30s grace
  }

  // ---------------------------------------------------------------------------
  // Solo/AI helpers
  // ---------------------------------------------------------------------------

  Future<void> _handleGameOver({
    required Emitter<GameState> emit,
    required GameActive active,
    required String reason,
    required String? rejectedWord,
    required String? rejectionReason,
  }) async {
    _aiTimer?.cancel();
    final canContinue = active.mode == 'classic' && !active.continueUsed;

    if (canContinue) {
      emit(GameOver(
        localMatchId: active.localMatchId,
        mode: active.mode,
        opponentType: active.opponentType,
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
        opponentScore: active.opponentScore,
        opponentType: active.opponentType,
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
    int opponentScore = 0,
    String? opponentType,
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
      opponentScore: opponentScore,
      opponentType: opponentType,
    );
    emit(over);
    await _saveAndEmitFinal(emit, over);
  }

  Future<void> _saveAndEmitFinal(
    Emitter<GameState> emit,
    GameOver over,
  ) async {
    if (_isMultiplayer) {
      // Server handles persistence for multiplayer games
      if (!over.isSaved) emit(over.copyWith(isSaved: true));
      return;
    }

    try {
      await _gameRepository.finishLocalGame(
        over.localMatchId,
        over.score,
        over.wordChain,
      );

      final longestWord = over.wordChain.isEmpty
          ? null
          : over.wordChain.reduce((a, b) => a.length >= b.length ? a : b);

      await _statsDao.recordGameResult(
        score: over.score,
        longestWord: longestWord,
      );

      // Daily challenge results must be uploaded before the result screen loads
      if (over.mode == 'daily') {
        await _syncService.sync();
      } else {
        _syncService.sync().ignore();
      }

      emit(over.copyWith(isSaved: true));
    } catch (e) {
      _log.e('Failed to save game', error: e);
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
