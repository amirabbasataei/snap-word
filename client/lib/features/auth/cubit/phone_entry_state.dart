part of 'phone_entry_cubit.dart';

class PhoneEntryState extends Equatable {
  /// The normalised number typed so far: `09` + up to nine digits, ASCII.
  final String digits;
  final bool sending;
  final String? errorCode;
  final String? errorMessage;

  /// A referral code stashed from the teaser card, forwarded into verify-otp.
  final String? referralCode;

  const PhoneEntryState({
    this.digits = '',
    this.sending = false,
    this.errorCode,
    this.errorMessage,
    this.referralCode,
  });

  bool get phoneValid => digits.length == 11 && digits.startsWith('09');
  bool get canSubmit => phoneValid && !sending;
  bool get hasError => errorCode != null;

  PhoneEntryState copyWith({
    String? digits,
    bool? sending,
    String? errorCode,
    String? errorMessage,
    String? referralCode,
    bool clearError = false,
  }) {
    return PhoneEntryState(
      digits: digits ?? this.digits,
      sending: sending ?? this.sending,
      errorCode: clearError ? null : (errorCode ?? this.errorCode),
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      referralCode: referralCode ?? this.referralCode,
    );
  }

  @override
  List<Object?> get props => [
    digits,
    sending,
    errorCode,
    errorMessage,
    referralCode,
  ];
}
