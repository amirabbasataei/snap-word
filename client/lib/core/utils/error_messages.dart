import 'package:dio/dio.dart';
import 'package:wordchain/core/utils/persian_digits.dart';

/// Single source of every user-facing error/success string that originates
/// from an API call. The backend's English `message` is never shown — only
/// its stable `code` is read and translated here.
///
/// Adding a backend `respondError` code? Add it to [_faByCode].
/// `test/core/utils/error_messages_test.dart` fails when a code is missing.

const genericErrorMessage = 'یه مشکلی پیش اومد، دوباره امتحان کن';
const networkErrorMessage = 'وصل نشد، اینترنتت رو چک کن';

const networkErrorCode = 'network_error';
const unknownErrorCode = 'unknown_error';

const _faByCode = <String, String>{
  // Client-side pseudo codes.
  networkErrorCode: networkErrorMessage,
  unknownErrorCode: genericErrorMessage,
  'no_refresh_token': 'نشستت تموم شده، دوباره وارد شو',

  // Generic / server.
  'internal_error': genericErrorMessage,
  'invalid_body': 'اطلاعات درست نیست',
  'validation_error': 'اطلاعاتی که وارد کردی درست نیست',
  'forbidden': 'اجازهٔ این کار رو نداری',
  'invalid_token': 'نشستت تموم شده، دوباره وارد شو',
  'missing_token': 'نشستت تموم شده، دوباره وارد شو',
  'account_banned': 'حسابت مسدود شده',

  // Auth / OTP / referral / profile.
  'invalid_phone': 'شمارهٔ موبایل درست نیست',
  'invalid_code': 'کد اشتباهه',
  'code_expired': 'این کد منقضی شده، یه کد جدید بگیر',
  'too_many_attempts': 'خیلی تلاش کردی، یه کد جدید بگیر',
  'otp_not_requested': 'هنوز برای این شماره کد نخواستی',
  'sms_failed': 'پیامک نرفت، چند لحظه بعد دوباره امتحان کن',
  'resend_cooldown': 'کمی صبر کن و دوباره امتحان کن',
  'rate_limited': 'برای این شماره خیلی کد خواستی، بعداً دوباره امتحان کن',
  'invalid_username': 'نام کاربری باید ۳ تا ۲۰ حرف، عدد یا _ باشه',
  'username_taken': 'این نام کاربری قبلاً گرفته شده',
  'premium_required': 'این فقط برای اشتراک ویژه‌ست',
  'invalid_avatar': 'این آواتار وجود نداره',
  'self_referral': 'نمی‌تونی از کد خودت استفاده کنی',
  'referral_not_found': 'کد دعوت پیدا نشد',
  'referral_already_used': 'قبلاً یه کد دعوت استفاده کردی',

  // Coins / power-ups / rewards.
  'insufficient_coins': 'سکهٔ کافی نداری',
  'insufficient_powerup': 'این آیتم رو نداری و سکه‌ات هم کافی نیست',
  'invalid_powerup_type': 'این آیتم وجود نداره',
  'reward_not_found': 'این جایزه پیدا نشد یا قبلاً گرفته شده',

  // Store purchases (Cafe Bazaar).
  'login_required': 'برای خرید باید وارد حسابت بشی',
  'store_missing': 'برای خرید باید کافه‌بازار روی گوشیت نصب باشه',
  'purchase_failed': 'خرید انجام نشد، دوباره امتحان کن',
  'purchase_invalid': 'این خرید تأیید نشد',
  'purchase_already_claimed': 'این خرید قبلاً برای یه حساب دیگه ثبت شده',
  'unknown_product': 'این بسته در دسترس نیست',
  'payments_unavailable': 'خرید فعلاً کار نمی‌کنه، بعداً امتحان کن',
  'store_unavailable': 'خرید بررسی نشد، کمی بعد دوباره امتحان کن',
  'purchase_not_delivered':
      'پرداخت انجام شد ولی هنوز ثبت نشده. با اینترنت وصل، برنامه رو دوباره باز کن تا ثبت بشه',

  // Match / lobby.
  'no_match': 'حریفی پیدا نشد. دوباره امتحان کن.',
  'invalid_mode': 'این نوع بازی وجود نداره',
  'invalid_difficulty': 'این سطح وجود نداره',
  'match_not_found': 'بازی پیدا نشد',

  // Daily challenge.
  'no_daily_challenge': 'چالش امروز هنوز آماده نشده',
  'not_attempted': 'اول باید چالش امروز رو بازی کنی',
  'already_retried': 'تلاش دوبارهٔ امروزت رو قبلاً استفاده کردی',
  'daily_attempt_not_allowed': 'تلاش‌های امروزت تموم شده',
  'invalid_daily_chain': 'نتیجهٔ چالش روزانه تأیید نشد',

  // Friends / challenges.
  'user_not_found': 'کاربری با این نام پیدا نشد',
  'avatar_not_found': 'آواتار پیدا نشد',
  'self_request': 'نمی‌تونی به خودت درخواست دوستی بدی',
  'request_exists': 'درخواست دوستی یا دوستی از قبل هست',
  'request_not_found': 'درخواست دوستی پیدا نشد',
  'not_friends': 'برای چالش دادن باید با این بازیکن دوست باشی',
  'not_challenged': 'این چالش برای تو نیست',
  'invalid_action': 'این کار ممکن نیست',
  'challenge_not_found': 'این چالش پیدا نشد',
  'challenge_expired': 'این چالش دیگه معتبر نیست',
  'challenger_cannot_afford': 'حریف دیگه سکهٔ کافی برای ورودی بازی نداره',

  // Word suggestions (Phase 24).
  'invalid_word': 'این کلمه رو نمی‌شه گزارش داد. فقط حروف فارسی و حداقل ۲ حرف',
  'word_in_dictionary': 'این کلمه از قبل در دیکشنری هست',
  'word_unknown': 'این کلمه در دیکشنری نیست',
  'word_already_reviewed': 'این کلمه قبلاً بررسی شده',

  // Leaderboard.
  'leaderboard_error': 'جدول امتیازها لود نشد',
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
    'درخواست دوستی برای $username فرستاده شد';

const challengeSentMessage = 'چالش فرستاده شد';

/// Toast when the rewarded-ad SDK has nothing to show right now.
const legalPageOpenFailedMessage = 'صفحه باز نشد، دوباره امتحان کن';

/// Profile → «اعلان‌ها» switch.
const notificationsEnabledTitle = 'اعلان‌ها روشن شد';
const notificationsEnabledMessage =
    'از این به بعد درخواست دوستی، چالش و جایزه‌هات رو سریع می‌فهمی.';
const notificationsOffTitle = 'اعلان‌ها خاموش شد';
const notificationsBlockedTitle = 'اعلان‌ها هنوز خاموشه';
const notificationsBlockedMessage =
    'از تنظیمات گوشی اعلان‌های زنجیر رو روشن کن و برگرد.';

const adUnavailableMessage = 'الان تبلیغی نیست، بعداً دوباره امتحان کن';

/// Lobby invite toast. The name sits in a bidi isolate so a Latin username
/// can't reorder the Persian around it.
String friendInviteSentMessage(String username) =>
    'دعوت برای \u2068$username\u2069 فرستاده شد';

const usernameChangedMessage = 'نام کاربری تغییر کرد';

const purchaseCancelledMessage = 'خرید لغو شد.';
const premiumActivatedMessage = 'اشتراک ویژه فعال شد!';

String coinsAwardedMessage(int coins) =>
    '${toPersianDigits(coins)} سکه به حسابت اضافه شد!';

/// Sign-up toast: a new account starts at 0, so its balance is the gift.
String welcomeBonusMessage(int coins) =>
    'خوش اومدی! ${toPersianDigits(coins)} سکه هدیه گرفتی';

const referralNotFoundAtSignupMessage = 'حسابت ساخته شد، ولی کد دعوت پیدا نشد';

const referralNeedsNewAccountMessage =
    'کد دعوت فقط برای حساب تازه‌ست، از پروفایل هم می‌تونی واردش کنی';

// Load-failure fallbacks (used when no code is available or translatable) ----

const loadFriendsFailedMessage = 'دوستات لود نشدن';
const loadDailyFailedMessage = 'چالش امروز لود نشد';
const loadDailyBoardFailedMessage = 'جدول امروز لود نشد';
const dailyRetryFailedMessage = 'تلاش دوباره شروع نشد';
const loadLeaderboardFailedMessage = 'جدول امتیازها لود نشد';
const loadProfileFailedMessage = 'پروفایل لود نشد';
const loadInventoryFailedMessage = 'آیتم‌ها لود نشدن';
const resumeMatchNotFoundMessage = 'بازی برای ادامه پیدا نشد';
const gameStartFailedMessage = 'بازی شروع نشد';
const joinQueueFailedMessage = 'وارد صف نشد';
