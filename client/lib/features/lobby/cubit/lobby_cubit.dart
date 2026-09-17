import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:wordchain/core/services/notification_service.dart';
import 'package:wordchain/core/services/sync_service.dart';
import 'package:wordchain/features/lobby/cubit/lobby_state.dart';
import 'package:wordchain/features/lobby/data/lobby_repository.dart';

export 'lobby_state.dart';

class LobbyCubit extends Cubit<LobbyState> {
  final LobbyRepository _repo;
  final SyncService _syncService;
  final NotificationService _notificationService;

  Timer? _elapsedTimer;
  StreamSubscription<String?>? _notificationSub;

  LobbyCubit({
    required LobbyRepository repo,
    required SyncService syncService,
    required NotificationService notificationService,
  })  : _repo = repo,
        _syncService = syncService,
        _notificationService = notificationService,
        super(const LobbyIdle());

  @override
  Future<void> close() {
    _cancelTimers();
    return super.close();
  }

  Future<void> startSearch(String mode) async {
    if (state is LobbySearching) return;

    emit(LobbySearching(mode: mode, elapsedSeconds: 0));
    // Backup signal only (per CLAUDE.md's "Match found" push trigger) —
    // covers the app being backgrounded mid-wait, where iOS can suspend the
    // in-flight HTTP call. In the normal foreground case below, `joinQueue`
    // itself already resolves with the match once the server pairs it.
    _subscribeToNotifications(mode);
    _startElapsedTicker();

    try {
      await _syncService.sync();
      // joinQueue long-polls server-side (see LobbyRepository) and returns
      // the resolved match directly — this IS the match-found signal, not
      // just a queue-join ack. Emitting here (rather than waiting on the
      // push listener above) is what actually gets the player into a match:
      // FCM isn't configured for local/simulator use, so relying solely on
      // the notification path silently never navigates anywhere.
      final result = await _repo.joinQueue(mode);
      _cancelTimers();
      if (state is LobbySearching) {
        emit(LobbyMatchFound(roomId: result.roomId, mode: mode));
      }
    } on LobbyException catch (e) {
      _cancelTimers();
      emit(LobbyError(e.message));
    } catch (e) {
      _cancelTimers();
      emit(const LobbyError('خطا در اتصال به اینترنت'));
    }
  }

  Future<void> cancelSearch() async {
    _cancelTimers();
    await _repo.cancelQueue();
    emit(const LobbyIdle());
  }

  void reset() => emit(const LobbyIdle());

  // FCM payload for match-found: data.route = "/game/{roomId}"
  void _subscribeToNotifications(String mode) {
    _notificationSub?.cancel();
    _notificationSub = _notificationService.payloadStream.listen((route) {
      if (route == null) return;
      if (route.startsWith('/game/')) {
        final roomId = route.substring('/game/'.length);
        if (roomId.isNotEmpty) {
          _cancelTimers();
          emit(LobbyMatchFound(roomId: roomId, mode: mode));
        }
      }
    });
  }

  // Visual-only tick for the "۰۰:۱۱" elapsed display — the actual timeout
  // is enforced server-side (matchmaking.go's AIFallbackWaitSec+5) and
  // surfaces as a real `no_match` error from `joinQueue` above, so this no
  // longer needs its own separate cutoff.
  void _startElapsedTicker() {
    _elapsedTimer?.cancel();
    _elapsedTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      final s = state;
      if (s is! LobbySearching) return;
      emit(s.copyWith(elapsedSeconds: s.elapsedSeconds + 1));
    });
  }

  void _cancelTimers() {
    _elapsedTimer?.cancel();
    _elapsedTimer = null;
    _notificationSub?.cancel();
    _notificationSub = null;
  }
}
