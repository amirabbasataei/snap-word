import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:wordchain/features/auth/cubit/auth_cubit.dart';
import 'package:wordchain/features/auth/data/auth_repository.dart';

part 'otp_flow_state.dart';

/// Feature-local, screen-scoped state for ZOtpVerifyScreen: the resend
/// countdown, resend/voice-call actions, and code submission. Built via
/// BlocProvider per screen instance (not registered in GetIt) since it's
/// scoped to one in-flight phone verification.
class OtpFlowCubit extends Cubit<OtpFlowState> {
  final AuthCubit _authCubit;
  final String phone;
  Timer? _ticker;

  OtpFlowCubit({
    required AuthCubit authCubit,
    required this.phone,
    required int initialCooldownSeconds,
  })  : _authCubit = authCubit,
        super(OtpFlowState(cooldownSecondsRemaining: initialCooldownSeconds)) {
    _startTicker();
  }

  void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (isClosed) {
        _ticker?.cancel();
        return;
      }
      if (state.cooldownSecondsRemaining <= 0) {
        _ticker?.cancel();
        return;
      }
      emit(state.copyWith(cooldownSecondsRemaining: state.cooldownSecondsRemaining - 1));
    });
  }

  /// Resends the code, by SMS or — once the same cooldown has elapsed — by
  /// voice call ("تماس صوتی").
  Future<void> resend({bool voice = false}) async {
    if (!state.canResend) return;
    emit(state.copyWith(sendingResend: true, clearError: true));
    try {
      final result = await _authCubit.sendOtp(phone: phone, voice: voice);
      emit(state.copyWith(
        sendingResend: false,
        cooldownSecondsRemaining: result.resendCooldownSeconds,
      ));
      _startTicker();
    } on AuthException catch (e) {
      emit(state.copyWith(sendingResend: false, errorCode: e.code, errorMessage: e.message));
    } on NetworkException catch (e) {
      emit(state.copyWith(sendingResend: false, errorCode: 'network_error', errorMessage: e.message));
    }
  }

  /// Submits the 4-digit code. Returns the result on success, or null (with
  /// state.errorCode/errorMessage set) on failure — the caller doesn't need
  /// to catch anything.
  Future<AuthResult?> submit(String code, {String? referralCode}) async {
    emit(state.copyWith(submitting: true, clearError: true));
    try {
      final result = await _authCubit.verifyOtp(
        phone: phone,
        code: code,
        referralCode: referralCode,
      );
      emit(state.copyWith(submitting: false));
      return result;
    } on AuthException catch (e) {
      emit(state.copyWith(submitting: false, errorCode: e.code, errorMessage: e.message));
      return null;
    } on NetworkException catch (e) {
      emit(state.copyWith(submitting: false, errorCode: 'network_error', errorMessage: e.message));
      return null;
    }
  }

  @override
  Future<void> close() {
    _ticker?.cancel();
    return super.close();
  }
}
