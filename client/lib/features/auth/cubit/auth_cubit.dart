import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:logger/logger.dart';
import 'package:wordchain/core/services/sync_service.dart';
import 'package:wordchain/features/auth/data/auth_repository.dart';

part 'auth_state.dart';

class AuthCubit extends Cubit<AuthState> {
  final AuthRepository _repo;
  final SyncService _syncService;
  final _log = Logger();

  AuthCubit({
    required AuthRepository authRepository,
    required SyncService syncService,
  })  : _repo = authRepository,
        _syncService = syncService,
        super(const AuthInitial());

  bool get isGuest => state is! AuthAuthenticated;

  /// Called once at startup. Resolves to AuthAuthenticated or AuthGuest.
  Future<void> init() async {
    emit(const AuthLoading());

    if (_repo.hasAccessToken) {
      final userId = _repo.storedUserId;
      final username = _repo.storedUsername;
      if (userId != null && username != null) {
        emit(AuthAuthenticated(userId: userId, username: username));
        unawaited(_syncService.sync());
        return;
      }
    }

    if (_repo.hasRefreshToken) {
      try {
        await _repo.refreshToken();
        final userId = _repo.storedUserId ?? '';
        final username = _repo.storedUsername ?? '';
        emit(AuthAuthenticated(userId: userId, username: username));
        unawaited(_syncService.sync());
        return;
      } catch (e) {
        _log.w('Token refresh failed at startup: $e');
        await _repo.logout();
      }
    }

    emit(const AuthGuest());
  }

  Future<void> login(String email, String password) async {
    emit(const AuthLoading());
    try {
      final result = await _repo.login(email, password);
      emit(AuthAuthenticated(userId: result.userId, username: result.username));
      unawaited(_syncService.sync());
    } on AuthException catch (e) {
      emit(AuthError(e.message));
    } on NetworkException catch (e) {
      emit(AuthError(e.message));
    }
  }

  Future<void> register(
    String username,
    String email,
    String password,
  ) async {
    emit(const AuthLoading());
    try {
      final result = await _repo.register(username, email, password);
      emit(AuthAuthenticated(userId: result.userId, username: result.username));
      unawaited(_syncService.sync());
    } on AuthException catch (e) {
      emit(AuthError(e.message));
    } on NetworkException catch (e) {
      emit(AuthError(e.message));
    }
  }

  void continueAsGuest() => emit(const AuthGuest());

  Future<void> logout() async {
    await _repo.logout();
    emit(const AuthGuest());
  }
}
