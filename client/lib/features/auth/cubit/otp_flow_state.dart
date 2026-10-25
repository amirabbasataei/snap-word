part of 'otp_flow_cubit.dart';

class OtpFlowState extends Equatable {
  /// The cubit's last clock reading; the countdown getters are computed from
  /// it, so a screen that was backgrounded catches up on the next tick.
  final DateTime now;

  /// When the server lets this phone ask for another code.
  final DateTime resendAt;

  /// When the code on the phone stops being valid; null when not known.
  final DateTime? expiresAt;
  final bool submitting;
  final bool sendingResend;
  final String? errorCode;
  final String? errorMessage;

  const OtpFlowState({
    required this.now,
    required this.resendAt,
    this.expiresAt,
    this.submitting = false,
    this.sendingResend = false,
    this.errorCode,
    this.errorMessage,
  });

  /// Whole seconds until a resend is allowed, rounded up (0 once it is).
  int get cooldownSecondsRemaining {
    final ms = resendAt.difference(now).inMilliseconds;
    return ms <= 0 ? 0 : (ms / 1000).ceil();
  }

  bool get canResend => cooldownSecondsRemaining <= 0 && !sendingResend;

  /// The code on the phone is past its expiry (the server stays the judge).
  bool get codeExpired => expiresAt != null && !now.isBefore(expiresAt!);

  bool get hasError => errorCode != null;

  OtpFlowState copyWith({
    DateTime? now,
    DateTime? resendAt,
    DateTime? expiresAt,
    bool? submitting,
    bool? sendingResend,
    String? errorCode,
    String? errorMessage,
    bool clearError = false,
  }) {
    return OtpFlowState(
      now: now ?? this.now,
      resendAt: resendAt ?? this.resendAt,
      expiresAt: expiresAt ?? this.expiresAt,
      submitting: submitting ?? this.submitting,
      sendingResend: sendingResend ?? this.sendingResend,
      errorCode: clearError ? null : (errorCode ?? this.errorCode),
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }

  @override
  List<Object?> get props => [
    now,
    resendAt,
    expiresAt,
    submitting,
    sendingResend,
    errorCode,
    errorMessage,
  ];
}
