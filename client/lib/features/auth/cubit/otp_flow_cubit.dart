import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:wordchain/features/auth/cubit/auth_cubit.dart';
import 'package:wordchain/features/auth/data/auth_repository.dart';

part 'otp_flow_state.dart';

/// Feature-local, screen-scoped state for ZOtpVerifyScreen: the resend
/// countdown, resend action, and code submission. Built via
/// BlocProvider per screen instance (not registered in GetIt) since it's
/// scoped to one in-flight phone verification.
///
/// The countdown is a pair of deadlines compared with [clock], not a counter
/// that is decremented: a backgrounded app (timers paused) shows the right
/// time the moment it resumes. One owned [Timer] only nudges the state to
/// re-read the clock and stops itself once both deadlines have passed.
class OtpFlowCubit extends Cubit<OtpFlowState> {
  final AuthCubit _authCubit;
  final String phone;
  final DateTime Function() _clock;
  Timer? _ticker;

  OtpFlowCubit({
    required AuthCubit authCubit,
    required this.phone,
    required int initialCooldownSeconds,
    int? initialExpiresSeconds,
    DateTime Function()? clock,
  }) : _authCubit = authCubit,
       _clock = clock ?? DateTime.now,
       super(
         _initial(
           (clock ?? DateTime.now)(),
           initialCooldownSeconds,
           initialExpiresSeconds,
         ),
       ) {
    _startTicker();
  }

  static OtpFlowState _initial(DateTime now, int cooldown, int? expires) =>
      OtpFlowState(
        now: now,
        resendAt: now.add(Duration(seconds: cooldown)),
        expiresAt: expires == null ? null : now.add(Duration(seconds: expires)),
      );

  bool get _timeLeft =>
      state.cooldownSecondsRemaining > 0 ||
      (state.expiresAt != null && !state.codeExpired);

  void _startTicker() {
    _ticker?.cancel();
    if (!_timeLeft) return;
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (isClosed) {
        _ticker?.cancel();
        return;
      }
      emit(state.copyWith(now: _clock()));
      if (!_timeLeft) _ticker?.cancel();
    });
  }

  /// Resends the code by SMS once the cooldown has elapsed.
  Future<void> resend() async {
    if (!state.canResend) return;
    emit(state.copyWith(sendingResend: true, clearError: true));
    try {
      final result = await _authCubit.sendOtp(phone: phone);
      if (isClosed) return;
      final now = _clock();
      emit(
        state.copyWith(
          now: now,
          sendingResend: false,
          resendAt: now.add(Duration(seconds: result.resendCooldownSeconds)),
          expiresAt: now.add(Duration(seconds: result.expiresInSeconds)),
        ),
      );
      _startTicker();
    } on AuthException catch (e) {
      if (isClosed) return;
      emit(
        state.copyWith(
          now: _clock(),
          sendingResend: false,
          errorCode: e.code,
          errorMessage: e.message,
        ),
      );
    } on NetworkException catch (e) {
      if (isClosed) return;
      emit(
        state.copyWith(
          now: _clock(),
          sendingResend: false,
          errorCode: 'network_error',
          errorMessage: e.message,
        ),
      );
    }
  }

  /// Submits the 4-digit code. Returns the result on success, or null (with
  /// state.errorCode/errorMessage set) on failure — the caller doesn't need
  /// to catch anything.
  Future<AuthResult?> submit(String code, {String? referralCode}) async {
    if (state.submitting) return null;
    emit(state.copyWith(submitting: true, clearError: true));
    try {
      final result = await _authCubit.verifyOtp(
        phone: phone,
        code: code,
        referralCode: referralCode,
      );
      if (!isClosed) emit(state.copyWith(submitting: false));
      return result;
    } on AuthException catch (e) {
      if (!isClosed) {
        emit(
          state.copyWith(
            submitting: false,
            errorCode: e.code,
            errorMessage: e.message,
          ),
        );
      }
      return null;
    } on NetworkException catch (e) {
      if (!isClosed) {
        emit(
          state.copyWith(
            submitting: false,
            errorCode: 'network_error',
            errorMessage: e.message,
          ),
        );
      }
      return null;
    }
  }

  /// Drops the shown error (the player started typing a new code).
  void clearError() {
    if (state.hasError) emit(state.copyWith(clearError: true));
  }

  @override
  Future<void> close() {
    _ticker?.cancel();
    return super.close();
  }
}
