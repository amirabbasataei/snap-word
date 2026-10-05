import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wordchain/core/network/api_endpoints.dart';

class DioClient {
  // Defaults to the production server. For a local backend run with
  // --dart-define=API_BASE_URL=http://10.0.2.2:8080 (Android emulator) or
  // http://localhost:8080 (iOS Simulator).
  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://185.110.191.158:8080',
  );
  static String get _baseUrl => baseUrl;

  late final Dio dio;

  DioClient(SharedPreferences prefs) {
    dio = Dio(
      BaseOptions(
        baseUrl: _baseUrl,
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 10),
        headers: {'Content-Type': 'application/json'},
      ),
    );

    dio.interceptors.add(_AuthInterceptor(prefs, dio));
    dio.interceptors.add(
      LogInterceptor(
        requestBody: true,
        responseBody: true,
        // logPrint: (obj) => Logger().d(obj.toString()),
      ),
    );
  }
}

class _AuthInterceptor extends Interceptor {
  final SharedPreferences _prefs;
  final Dio _dio;

  // Shared by every 401 that arrives while a refresh is already in flight —
  // e.g. SyncService.sync() fires several requests in parallel on startup,
  // and they all fail together on one stale token. Without sharing this
  // future, only the first request's onError would refresh+retry; the rest
  // would see the old boolean-flag guard as "busy" and fail permanently even
  // though a valid new token lands moments later.
  Future<String?>? _refreshFuture;

  _AuthInterceptor(this._prefs, this._dio);

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final token = _prefs.getString('jwt_access_token');
    if (token != null) {
      options.headers['Authorization'] = 'Bearer $token';
    }
    handler.next(options);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    final alreadyRetried =
        err.requestOptions.extra['retriedAfterRefresh'] == true;
    final isRefreshCall = err.requestOptions.extra['isAuthRefresh'] == true;
    if (err.response?.statusCode != 401 || alreadyRetried || isRefreshCall) {
      // The refresh call's own errors must not re-enter this dance: it would
      // await _refreshFuture while still being the request _refreshFuture is
      // suspended on, deadlocking forever. Let it surface to _performRefresh's
      // own try/catch instead.
      handler.next(err);
      return;
    }

    final refreshToken = _prefs.getString('jwt_refresh_token');
    if (refreshToken == null) {
      handler.next(err);
      return;
    }

    final newToken = await (_refreshFuture ??= _performRefresh(refreshToken));
    if (newToken == null) {
      handler.next(err);
      return;
    }

    try {
      final retryOptions =
          err.requestOptions
            ..headers['Authorization'] = 'Bearer $newToken'
            ..extra['retriedAfterRefresh'] = true;
      final retryResponse = await _dio.fetch(retryOptions);
      handler.resolve(retryResponse);
    } catch (_) {
      handler.next(err);
    }
  }

  /// Performs a single refresh call regardless of how many concurrent 401s
  /// asked for one. Only a definitive rejection from the refresh endpoint
  /// (the refresh token really is invalid or expired) clears stored
  /// credentials — a network blip or server error leaves them intact so the
  /// session survives and a later retry can still succeed.
  Future<String?> _performRefresh(String refreshToken) async {
    try {
      final response = await _dio.post(
        ApiEndpoints.refresh,
        data: {'refresh_token': refreshToken},
        options: Options(
          headers: {'Authorization': null},
          extra: {'isAuthRefresh': true},
        ),
      );
      final newToken = response.data['data']['access_token'] as String;
      await _prefs.setString('jwt_access_token', newToken);
      return newToken;
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) {
        await _prefs.remove('jwt_access_token');
        await _prefs.remove('jwt_refresh_token');
      }
      return null;
    } finally {
      _refreshFuture = null;
    }
  }
}
