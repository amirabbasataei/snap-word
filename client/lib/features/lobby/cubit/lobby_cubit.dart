import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:wordchain/core/services/notification_service.dart';
import 'package:wordchain/core/services/sync_service.dart';
import 'package:wordchain/features/lobby/cubit/lobby_state.dart';
import 'package:wordchain/features/lobby/data/lobby_repository.dart';

export 'lobby_state.dart';

// How long to wait before giving up — server AI fallback is at 30s,
// so 35s gives a short grace period for the notification to arrive.
const _searchTimeoutSec = 35;

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

    try {
      await _syncService.sync();
      await _repo.joinQueue(mode);
    } on LobbyException catch (e) {
      _cancelTimers();
      emit(LobbyError(e.message));
      return;
    } catch (e) {
      _cancelTimers();
      emit(const LobbyError('Network error. Check your connection.'));
      return;
    }

    _subscribeToNotifications(mode);
    _startElapsedTimer(mode);
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

  void _startElapsedTimer(String mode) {
    _elapsedTimer?.cancel();
    _elapsedTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      final s = state;
      if (s is! LobbySearching) return;

      final next = s.elapsedSeconds + 1;
      if (next >= _searchTimeoutSec) {
        _cancelTimers();
        _repo.cancelQueue().ignore();
        emit(const LobbyError('No opponent found. Try again.'));
      } else {
        emit(s.copyWith(elapsedSeconds: next));
      }
    });
  }

  void _cancelTimers() {
    _elapsedTimer?.cancel();
    _elapsedTimer = null;
    _notificationSub?.cancel();
    _notificationSub = null;
  }
}
