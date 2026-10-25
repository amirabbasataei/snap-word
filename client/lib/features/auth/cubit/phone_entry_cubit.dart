import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:wordchain/features/auth/cubit/auth_cubit.dart';
import 'package:wordchain/features/auth/data/auth_repository.dart';
import 'package:wordchain/features/auth/view/z_otp_verify_screen.dart';

part 'phone_entry_state.dart';

/// Screen-scoped state of ZLoginScreen (phone entry): the number, the send
/// request and the stashed referral code. Built by a BlocProvider per screen,
/// not registered in GetIt.
class PhoneEntryCubit extends Cubit<PhoneEntryState> {
  final AuthCubit _authCubit;
  final String? returnPath;
  final DateTime Function() _clock;

  /// Codes sent from this screen, by phone. The server answers a second
  /// send-otp inside its cooldown with `resend_cooldown` and does not say how
  /// long is left; when the player came back from the OTP screen to fix the
  /// number and typed the same one again, the earlier code is still valid and
  /// the time left is known from here.
  final _sent = <String, ({DateTime at, SendOtpResult result})>{};

  PhoneEntryCubit({
    required AuthCubit authCubit,
    this.returnPath,
    DateTime Function()? clock,
  }) : _authCubit = authCubit,
       _clock = clock ?? DateTime.now,
       super(const PhoneEntryState());

  @override
  void emit(PhoneEntryState state) {
    if (!isClosed) super.emit(state);
  }

  void setDigits(String digits) {
    emit(state.copyWith(digits: digits, clearError: true));
  }

  void setReferralCode(String code) => emit(state.copyWith(referralCode: code));

  /// Asks the server to text a code. Returns what the OTP screen needs on
  /// success, or null with the error in the state.
  Future<OtpVerifyArgs?> submit() async {
    if (!state.canSubmit) return null;
    final phone = state.digits;
    emit(state.copyWith(sending: true, clearError: true));
    try {
      final result = await _authCubit.sendOtp(phone: phone);
      _sent[phone] = (at: _clock(), result: result);
      emit(state.copyWith(sending: false));
      return _args(
        phone,
        result.resendCooldownSeconds,
        result.expiresInSeconds,
      );
    } on AuthException catch (e) {
      final earlier = _sent[phone];
      if (e.code == 'resend_cooldown' && earlier != null) {
        final elapsed = _clock().difference(earlier.at).inSeconds;
        final cooldown = earlier.result.resendCooldownSeconds - elapsed;
        final expires = earlier.result.expiresInSeconds - elapsed;
        if (cooldown > 0) {
          emit(state.copyWith(sending: false));
          return _args(phone, cooldown, expires > 0 ? expires : 0);
        }
      }
      emit(
        state.copyWith(
          sending: false,
          errorCode: e.code,
          errorMessage: e.message,
        ),
      );
    } on NetworkException catch (e) {
      emit(
        state.copyWith(
          sending: false,
          errorCode: 'network_error',
          errorMessage: e.message,
        ),
      );
    }
    return null;
  }

  OtpVerifyArgs _args(String phone, int cooldown, int expires) => OtpVerifyArgs(
    phone: phone,
    returnPath: returnPath,
    referralCode: state.referralCode,
    initialCooldownSeconds: cooldown,
    initialExpiresSeconds: expires,
  );
}
