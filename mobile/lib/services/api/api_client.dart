import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ApiClient {
  static final ApiClient instance = ApiClient._init();
  late final Dio dio;

  // Default development backend URL (works on Android Emulator, physical device via LAN, or custom)
  String _baseUrl = 'http://10.0.2.2:5000/api';

  ApiClient._init() {
    dio = Dio(
      BaseOptions(
        baseUrl: _baseUrl,
        connectTimeout: const Duration(seconds: 8),
        receiveTimeout: const Duration(seconds: 8),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
      ),
    );

    // Add JWT auth token interceptor
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          final prefs = await SharedPreferences.getInstance();
          final token = prefs.getString('access_token');
          if (token != null && token.isNotEmpty) {
            options.headers['Authorization'] = 'Bearer $token';
          }
          return handler.next(options);
        },
        onError: (DioException error, handler) async {
          // If 401 Unauthorized, attempt refresh token
          if (error.response?.statusCode == 401) {
            final refreshed = await _refreshToken();
            if (refreshed) {
              // Retry original request
              final opts = error.requestOptions;
              final prefs = await SharedPreferences.getInstance();
              final newToken = prefs.getString('access_token');
              opts.headers['Authorization'] = 'Bearer $newToken';
              final cloneReq = await dio.request(
                opts.path,
                options: Options(method: opts.method, headers: opts.headers),
                data: opts.data,
                queryParameters: opts.queryParameters,
              );
              return handler.resolve(cloneReq);
            }
          }
          return handler.next(error);
        },
      ),
    );
  }

  Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedUrl = prefs.getString('custom_server_url');
      if (savedUrl != null && savedUrl.isNotEmpty) {
        _baseUrl = savedUrl;
        dio.options.baseUrl = _baseUrl;
      }
    } catch (_) {}
  }

  Future<void> updateBaseUrl(String url) async {
    _baseUrl = url.endsWith('/api') ? url : '$url/api';
    dio.options.baseUrl = _baseUrl;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('custom_server_url', _baseUrl);
    } catch (_) {}
  }

  String get baseUrl => _baseUrl;

  Future<bool> _refreshToken() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final refreshToken = prefs.getString('refresh_token');
      if (refreshToken == null) return false;

      final res = await Dio().post(
        '$_baseUrl/auth/refresh',
        data: {'refreshToken': refreshToken},
      );

      if (res.statusCode == 200 && res.data['success'] == true) {
        await prefs.setString('access_token', res.data['accessToken']);
        if (res.data['refreshToken'] != null) {
          await prefs.setString('refresh_token', res.data['refreshToken']);
        }
        return true;
      }
    } catch (_) {}
    return false;
  }

  // Auth
  Future<Response> login(String username, String password) async {
    return await dio.post('/auth/login', data: {
      'username': username,
      'password': password,
    });
  }

  // Device registration
  Future<Response> registerDevice(String deviceId, String deviceName) async {
    return await dio.post('/sync/device/register', data: {
      'deviceId': deviceId,
      'deviceName': deviceName,
    });
  }

  // Sync Push
  Future<Response> pushSync({
    required String deviceId,
    List<Map<String, dynamic>> customers = const [],
    List<Map<String, dynamic>> invoices = const [],
    List<Map<String, dynamic>> payments = const [],
  }) async {
    return await dio.post('/sync/push', data: {
      'deviceId': deviceId,
      'customers': customers,
      'invoices': invoices,
      'payments': payments,
    });
  }

  // Sync Pull
  Future<Response> pullSync(String? sinceIsoDate) async {
    return await dio.get('/sync/pull', queryParameters: {
      if (sinceIsoDate != null) 'since': sinceIsoDate,
    });
  }
}
