import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wordchain/core/network/api_endpoints.dart';

class AuthException implements Exception {
  final String code;
  final String message;

  const AuthException({required this.code, required this.message});

  @override
  String toString() => 'AuthException($code): $message';
}

class NetworkException implements Exception {
  final String message;

  const NetworkException(this.message);

  @override
  String toString() => 'NetworkException: $message';
}

class SendOtpResult {
  final int expiresInSeconds;
  final int resendCooldownSeconds;

  const SendOtpResult({
    required this.expiresInSeconds,
    required this.resendCooldownSeconds,
  });
}

class AuthResult {
  final String userId;
  final String username;
  final int coins;
  final bool isNewUser;

  /// "referral_not_found" if a referral code was supplied at signup but
  /// didn't resolve — signup still succeeded, this is informational only.
  final String? referralWarning;

  const AuthResult({
    required this.userId,
    required this.username,
    required this.coins,
    required this.isNewUser,
    this.referralWarning,
  });
}

class AuthRepository {
  final Dio _dio;
  final SharedPreferences _prefs;

  AuthRepository({required Dio dio, required SharedPreferences prefs})
      : _dio = dio,
        _prefs = prefs;

  bool get hasAccessToken => _prefs.getString('jwt_access_token') != null;
  bool get hasRefreshToken => _prefs.getString('jwt_refresh_token') != null;
  String? get storedUserId => _prefs.getString('user_id');
  String? get storedUsername => _prefs.getString('username');
  int get storedCoins => _prefs.getInt('coins') ?? 0;

  Future<SendOtpResult> sendOtp({required String phone, bool voice = false}) async {
    try {
      final response = await _dio.post(
        ApiEndpoints.sendOtp,
        data: {'phone': phone, 'voice': voice},
        options: Options(headers: {'Authorization': null}),
      );
      final data = response.data['data'] as Map<String, dynamic>;
      return SendOtpResult(
        expiresInSeconds: data['expires_in_seconds'] as int,
        resendCooldownSeconds: data['resend_cooldown_seconds'] as int,
      );
    } on DioException catch (e) {
      throw _mapError(e);
    }
  }

  Future<AuthResult> verifyOtp({
    required String phone,
    required String code,
    String? referralCode,
  }) async {
    try {
      final response = await _dio.post(
        ApiEndpoints.verifyOtp,
        data: {
          'phone': phone,
          'code': code,
          if (referralCode != null && referralCode.isNotEmpty)
            'referral_code': referralCode,
        },
        options: Options(headers: {'Authorization': null}),
      );
      final data = response.data['data'] as Map<String, dynamic>;
      await _saveSession(data);
      return AuthResult(
        userId: data['user_id'] as String,
        username: data['username'] as String,
        coins: data['coins'] as int? ?? 0,
        isNewUser: data['is_new_user'] as bool? ?? false,
        referralWarning: data['referral_warning'] as String?,
      );
    } on DioException catch (e) {
      throw _mapError(e);
    }
  }

  /// Entry point (b): an already-authenticated user submitting a referral
  /// code after the fact. One-time per account — the server rejects reuse.
  Future<int> redeemReferral(String code) async {
    try {
      final response = await _dio.post(
        ApiEndpoints.referralRedeem,
        data: {'referral_code': code},
      );
      final data = response.data['data'] as Map<String, dynamic>;
      final awarded = data['coins_awarded'] as int;
      await _prefs.setInt('coins', storedCoins + awarded);
      return awarded;
    } on DioException catch (e) {
      throw _mapError(e);
    }
  }

  Future<void> refreshToken() async {
    final token = _prefs.getString('jwt_refresh_token');
    if (token == null) {
      throw const AuthException(
        code: 'no_refresh_token',
        message: 'No refresh token available',
      );
    }
    try {
      final response = await _dio.post(
        ApiEndpoints.refresh,
        data: {'refresh_token': token},
        options: Options(headers: {'Authorization': null}),
      );
      final data = response.data['data'] as Map<String, dynamic>;
      await _prefs.setString('jwt_access_token', data['access_token'] as String);
    } on DioException catch (e) {
      throw _mapError(e);
    }
  }

  Future<void> logout() async {
    await Future.wait([
      _prefs.remove('jwt_access_token'),
      _prefs.remove('jwt_refresh_token'),
      _prefs.remove('user_id'),
      _prefs.remove('username'),
      _prefs.remove('coins'),
    ]);
  }

  Future<void> _saveSession(Map<String, dynamic> data) async {
    await Future.wait([
      _prefs.setString('jwt_access_token', data['access_token'] as String),
      _prefs.setString('jwt_refresh_token', data['refresh_token'] as String),
      _prefs.setString('user_id', data['user_id'] as String),
      _prefs.setString('username', data['username'] as String),
      _prefs.setInt('coins', data['coins'] as int? ?? 0),
    ]);
  }

  Exception _mapError(DioException e) {
    if (e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.receiveTimeout ||
        e.type == DioExceptionType.sendTimeout ||
        e.type == DioExceptionType.connectionError) {
      return const NetworkException(
        'Connection error. Please check your internet connection.',
      );
    }
    final body = e.response?.data;
    final code = body?['error']?['code'] as String? ?? 'unknown_error';
    final message =
        body?['error']?['message'] as String? ?? 'An error occurred.';
    return AuthException(code: code, message: message);
  }
}
