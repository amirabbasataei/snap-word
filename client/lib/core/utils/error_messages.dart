import 'package:dio/dio.dart';
import 'package:wordchain/core/utils/persian_digits.dart';

/// Single source of every user-facing error/success string that originates
/// from an API call. The backend's English `message` is never shown — only
/// its stable `code` is read and translated here.
///
/// Adding a backend `respondError` code? Add it to [_faByCode].
/// `test/core/utils/error_messages_test.dart` fails when a code is missing.

const genericErrorMessage = 'مشکلی پیش آمد، دوباره تلاش کن';
const networkErrorMessage = 'خطا در اتصال به اینترنت';

const networkErrorCode = 'network_error';
const unknownErrorCode = 'unknown_error';

const _faByCode = <String, String>{
  // Client-side pseudo codes.
  networkErrorCode: networkErrorMessage,
  unknownErrorCode: genericErrorMessage,
  'no_refresh_token': 'نشست تو به پایان رسیده؛ دوباره وارد شو',

  // Generic / server.
  'internal_error': genericErrorMessage,
  'invalid_body': 'اطلاعات ارسالی نامعتبر است',
  'validation_error': 'اطلاعات واردشده نامعتبر است',
  'forbidden': 'دسترسی این کار را نداری',
  'invalid_token': 'نشست تو منقضی شده؛ دوباره وارد شو',
  'missing_token': 'نشست تو منقضی شده؛ دوباره وارد شو',

  // Auth / OTP / referral / profile.
  'invalid_phone': 'شماره موبایل معتبر نیست',
  'invalid_code': 'کد وارد شده اشتباه است',
  'code_expired': 'این کد منقضی شده؛ یک کد جدید بگیر',
  'too_many_attempts': 'تعداد تلاش‌هایت زیاد شد؛ یک کد جدید بگیر',
  'otp_not_requested': 'برای این شماره کدی درخواست نشده',
  'resend_cooldown': 'کمی صبر کن و دوباره تلاش کن',
  'rate_limited':
      'درخواست‌های زیادی برای این شماره ثبت شده؛ بعداً دوباره امتحان کن',
  'invalid_username': 'نام کاربری باید ۳ تا ۲۰ حرف، عدد یا _ باشد',
  'username_taken': 'این نام کاربری قبلاً گرفته شده',
  'self_referral': 'نمی‌توانی از کد خودت استفاده کنی',
  'referral_not_found': 'کد دعوت پیدا نشد',
  'referral_already_used': 'قبلاً یک کد دعوت استفاده کرده‌ای',

  // Coins / power-ups / rewards.
  'insufficient_coins': 'سکهٔ کافی نداری',
  'insufficient_powerup': 'این آیتم را نداری و سکه‌ات هم کافی نیست',
  'invalid_powerup_type': 'آیتم نامعتبر است',
  'reward_not_found': 'این جایزه پیدا نشد یا قبلاً دریافت شده',

  // Match / lobby.
  'no_match': 'حریفی پیدا نشد. دوباره تلاش کن.',
  'invalid_mode': 'نوع بازی نامعتبر است',
  'invalid_difficulty': 'سطح بازی نامعتبر است',
  'match_not_found': 'بازی پیدا نشد',

  // Daily challenge.
  'no_daily_challenge': 'چالش امروز هنوز آماده نشده',
  'not_attempted': 'اول باید چالش امروز را انجام بدهی',
  'already_retried': 'تلاش دوبارهٔ امروز را قبلاً استفاده کرده‌ای',
  'daily_attempt_not_allowed': 'تلاش‌های چالش امروز تمام شده',

  // Friends / challenges.
  'user_not_found': 'کاربری با این نام پیدا نشد',
  'self_request': 'نمی‌توانی به خودت درخواست دوستی بدهی',
  'request_exists': 'درخواست دوستی یا دوستی از قبل وجود دارد',
  'request_not_found': 'درخواست دوستی پیدا نشد',
  'not_friends': 'برای چالش دادن باید با این بازیکن دوست باشی',
  'not_challenged': 'این چالش برای تو نیست',
  'invalid_action': 'عملیات نامعتبر است',
  'challenge_not_found': 'این چالش پیدا نشد',
  'challenge_expired': 'این چالش دیگر معتبر نیست',
  'challenger_cannot_afford': 'حریف دیگر سکهٔ کافی برای ورودی بازی ندارد',

  // Leaderboard.
  'leaderboard_error': 'بارگذاری جدول امتیازها ناموفق بود',
};

/// Every code with a dedicated Persian entry (used by the coverage test).
Set<String> get translatedErrorCodes => _faByCode.keys.toSet();

/// Persian message for a backend/client error [code]. Unknown codes fall back
/// to [fallback] (default: [genericErrorMessage]) — never to server text.
String errorMessageFor(String? code, {String? fallback}) =>
    _faByCode[code] ?? fallback ?? genericErrorMessage;

/// Extracts the backend error `code` from a failed request, or
/// [networkErrorCode] for connectivity problems / [unknownErrorCode] when the
/// response carries no code.
String apiErrorCode(DioException e) {
  switch (e.type) {
    case DioExceptionType.connectionTimeout:
    case DioExceptionType.receiveTimeout:
    case DioExceptionType.sendTimeout:
    case DioExceptionType.connectionError:
      return networkErrorCode;
    default:
      final data = e.response?.data;
      if (data is Map) {
        final error = data['error'];
        if (error is Map && error['code'] is String) {
          return error['code'] as String;
        }
      }
      return unknownErrorCode;
  }
}

/// Persian message for a failed request; [fallback] is used when the backend
/// code has no dedicated translation (e.g. "بارگذاری پروفایل ناموفق بود").
String apiErrorMessage(DioException e, {String? fallback}) =>
    errorMessageFor(apiErrorCode(e), fallback: fallback);

// Success messages ---------------------------------------------------------

String friendRequestSentMessage(String username) =>
    'درخواست دوستی برای $username ارسال شد';

const challengeSentMessage = 'چالش ارسال شد';

const usernameChangedMessage = 'نام کاربری تغییر کرد';

String coinsAwardedMessage(int coins) =>
    '${toPersianDigits(coins)} سکه به حسابت اضافه شد!';

// Load-failure fallbacks (used when no code is available or translatable) ----

const loadFriendsFailedMessage = 'بارگذاری دوستان ناموفق بود';
const loadDailyFailedMessage = 'بارگذاری چالش امروز ناموفق بود';
const loadDailyBoardFailedMessage = 'بارگذاری جدول امروز ناموفق بود';
const dailyRetryFailedMessage = 'شروع تلاش دوباره ناموفق بود';
const loadLeaderboardFailedMessage = 'بارگذاری جدول امتیازها ناموفق بود';
const loadProfileFailedMessage = 'بارگذاری پروفایل ناموفق بود';
const loadInventoryFailedMessage = 'بارگذاری آیتم‌ها ناموفق بود';
const resumeMatchNotFoundMessage = 'بازی برای ادامه پیدا نشد';
const gameStartFailedMessage = 'شروع بازی ناموفق بود';
const joinQueueFailedMessage = 'پیوستن به صف ناموفق بود';
