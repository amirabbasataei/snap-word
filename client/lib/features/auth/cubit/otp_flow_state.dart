part of 'otp_flow_cubit.dart';

class OtpFlowState extends Equatable {
  final int cooldownSecondsRemaining;
  final bool submitting;
  final bool sendingResend;
  final String? errorCode;
  final String? errorMessage;

  const OtpFlowState({
    this.cooldownSecondsRemaining = 0,
    this.submitting = false,
    this.sendingResend = false,
    this.errorCode,
    this.errorMessage,
  });

  /// Both a fresh resend and the voice-call fallback are gated on the same
  /// cooldown — matches the design's single "ارسال دوباره تا ۰۰:۴۲" timer.
  bool get canResend => cooldownSecondsRemaining <= 0 && !sendingResend;

  OtpFlowState copyWith({
    int? cooldownSecondsRemaining,
    bool? submitting,
    bool? sendingResend,
    String? errorCode,
    String? errorMessage,
    bool clearError = false,
  }) {
    return OtpFlowState(
      cooldownSecondsRemaining: cooldownSecondsRemaining ?? this.cooldownSecondsRemaining,
      submitting: submitting ?? this.submitting,
      sendingResend: sendingResend ?? this.sendingResend,
      errorCode: clearError ? null : (errorCode ?? this.errorCode),
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }

  @override
  List<Object?> get props => [
        cooldownSecondsRemaining,
        submitting,
        sendingResend,
        errorCode,
        errorMessage,
      ];
}
