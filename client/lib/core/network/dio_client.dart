import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wordchain/core/network/api_endpoints.dart';

class DioClient {
  static const String _baseUrl = 'http://10.0.2.2:8080';

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
    dio.interceptors.add(LogInterceptor(
      requestBody: true,
      responseBody: true,
      // logPrint: (obj) => Logger().d(obj.toString()),
    ));
  }
}

class _AuthInterceptor extends Interceptor {
  final SharedPreferences _prefs;
  final Dio _dio;
  bool _refreshing = false;

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
    if (err.response?.statusCode == 401 && !_refreshing) {
      final refreshToken = _prefs.getString('jwt_refresh_token');
      if (refreshToken == null) {
        handler.next(err);
        return;
      }
      _refreshing = true;
      try {
        final response = await _dio.post(
          ApiEndpoints.refresh,
          data: {'refresh_token': refreshToken},
          options: Options(headers: {'Authorization': null}),
        );
        final newToken = response.data['data']['access_token'] as String;
        await _prefs.setString('jwt_access_token', newToken);

        final retryOptions = err.requestOptions;
        retryOptions.headers['Authorization'] = 'Bearer $newToken';
        final retryResponse = await _dio.fetch(retryOptions);
        handler.resolve(retryResponse);
        return;
      } catch (_) {
        await _prefs.remove('jwt_access_token');
        await _prefs.remove('jwt_refresh_token');
      } finally {
        _refreshing = false;
      }
    }
    handler.next(err);
  }
}
