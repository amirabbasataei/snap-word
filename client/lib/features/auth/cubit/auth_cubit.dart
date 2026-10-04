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
        emit(AuthAuthenticated(userId: userId, username: username, coins: _repo.storedCoins));
        unawaited(_syncService.sync());
        return;
      }
    }

    if (_repo.hasRefreshToken) {
      try {
        await _repo.refreshToken();
        final userId = _repo.storedUserId ?? '';
        final username = _repo.storedUsername ?? '';
        emit(AuthAuthenticated(userId: userId, username: username, coins: _repo.storedCoins));
        unawaited(_syncService.sync());
        return;
      } catch (e) {
        _log.w('Token refresh failed at startup: $e');
        await _repo.logout();
      }
    }

    emit(const AuthGuest());
  }

  /// Sends (or resends) a 4-digit OTP to [phone]. Throws AuthException /
  /// NetworkException on failure — the caller (OtpFlowCubit) owns the
  /// countdown/error UI, so this does not touch AuthCubit's own state.
  Future<SendOtpResult> sendOtp({required String phone, bool voice = false}) {
    return _repo.sendOtp(phone: phone, voice: voice);
  }

  /// Verifies the OTP and, on success, transitions to AuthAuthenticated.
  /// Throws AuthException / NetworkException on failure so the OTP screen
  /// can show inline/per-box errors instead of a page-level banner.
  Future<AuthResult> verifyOtp({
    required String phone,
    required String code,
    String? referralCode,
  }) async {
    final result = await _repo.verifyOtp(phone: phone, code: code, referralCode: referralCode);
    emit(AuthAuthenticated(userId: result.userId, username: result.username, coins: result.coins));
    unawaited(_syncService.sync());
    return result;
  }

  /// Overwrites the balance with the authoritative server value.
  Future<void> setCoins(int coins) async {
    await _repo.setCoins(coins);
    final current = state;
    if (current is AuthAuthenticated && current.coins != coins) {
      emit(current.copyWith(coins: coins));
    }
  }

  /// Adds server-credited coins (e.g. a claimed reward) to the live balance.
  Future<void> creditCoins(int amount) async {
    await _repo.creditCoins(amount);
    final current = state;
    if (current is AuthAuthenticated) {
      emit(current.copyWith(coins: current.coins + amount));
    }
  }

  Future<void> updateUsername(String username) async {
    final saved = await _repo.updateUsername(username);
    final current = state;
    if (current is AuthAuthenticated) emit(current.copyWith(username: saved));
  }

  Future<String> fetchMyReferralCode() => _repo.fetchMyReferralCode();

  /// Entry point (b): post-login, one-time referral redemption. Throws on
  /// failure (self-referral, not found, or already used).
  Future<int> redeemReferral(String code) async {
    final awarded = await _repo.redeemReferral(code);
    final current = state;
    if (current is AuthAuthenticated) {
      emit(current.copyWith(coins: current.coins + awarded));
    }
    return awarded;
  }

  void continueAsGuest() => emit(const AuthGuest());

  Future<void> logout() async {
    await _repo.logout();
    emit(const AuthGuest());
  }
}
