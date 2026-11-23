import 'dart:async';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ApiClient {
  static final ApiClient instance = ApiClient._init();
  late final Dio dio;

  // Production Render live cloud backend URL
  static const String defaultBaseUrl = 'https://ss-supreme-solutions-backend.onrender.com/api';
  static void Function()? onAuthSessionExpired;
  String _baseUrl = defaultBaseUrl;
  String? _cachedToken;
  Completer<bool>? _refreshCompleter;

  void updateCachedToken(String? token) {
    _cachedToken = token;
  }

  void updateToken(String? token) {
    _cachedToken = token;
  }

  ApiClient._init() {
    dio = Dio(
      BaseOptions(
        baseUrl: _baseUrl,
        connectTimeout: const Duration(seconds: 45),
        receiveTimeout: const Duration(seconds: 45),
        sendTimeout: const Duration(seconds: 45),
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
          // AUTH-01: Wait if token refresh is already in-flight to prevent sending expired tokens
          if (_refreshCompleter != null) {
            try {
              await _refreshCompleter!.future;
            } catch (_) {}
          }
          if (_cachedToken == null) {
            final prefs = await SharedPreferences.getInstance();
            _cachedToken = prefs.getString('access_token');
          }
          if (_cachedToken != null && _cachedToken!.isNotEmpty) {
            options.headers['Authorization'] = 'Bearer $_cachedToken';
          }
          return handler.next(options);
        },
        onError: (DioException error, handler) async {
          // If 401 Unauthorized, attempt refresh token with retry guard
          final isAuthEndpoint = error.requestOptions.path.contains('/auth/refresh') ||
              error.requestOptions.path.contains('/auth/login');
          if (error.response?.statusCode == 401 &&
              !isAuthEndpoint &&
              error.requestOptions.extra['isRetry'] != true) {
            error.requestOptions.extra['isRetry'] = true;
            final refreshed = await _refreshToken();
            if (refreshed) {
              // Retry original request
              final opts = error.requestOptions;
              opts.headers['Authorization'] = 'Bearer $_cachedToken';
              try {
                final cloneReq = await dio.request(
                  opts.path,
                  options: Options(
                    method: opts.method,
                    headers: opts.headers,
                    extra: opts.extra,
                    responseType: opts.responseType,
                    contentType: opts.contentType,
                  ),
                  data: opts.data,
                  queryParameters: opts.queryParameters,
                );
                return handler.resolve(cloneReq);
              } catch (retryErr) {
                if (retryErr is DioException) {
                  return handler.next(retryErr);
                }
              }
            }
          }
          return handler.next(error);
        },
      ),
    );
  }

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final customUrl = prefs.getString('custom_backend_url');
    _baseUrl = (customUrl != null && customUrl.isNotEmpty) ? customUrl : defaultBaseUrl;
    dio.options.baseUrl = _baseUrl;
  }

  String get baseUrl => _baseUrl;

  Future<bool> _refreshToken() async {
    if (_refreshCompleter != null) {
      return _refreshCompleter!.future;
    }
    _refreshCompleter = Completer<bool>();
    try {
      final prefs = await SharedPreferences.getInstance();
      final refreshToken = prefs.getString('refresh_token');
      if (refreshToken == null) {
        _refreshCompleter!.complete(false);
        _refreshCompleter = null;
        return false;
      }

      final refreshDio = Dio(
        BaseOptions(
          connectTimeout: const Duration(seconds: 15),
          sendTimeout: const Duration(seconds: 15),
          receiveTimeout: const Duration(seconds: 15),
        ),
      );

      final res = await refreshDio.post(
        '$_baseUrl/auth/refresh',
        data: {'refreshToken': refreshToken},
      );

      if (res.statusCode == 200 && res.data['success'] == true) {
        _cachedToken = res.data['accessToken'];
        await prefs.setString('access_token', res.data['accessToken']);
        if (res.data['refreshToken'] != null) {
          await prefs.setString('refresh_token', res.data['refreshToken']);
        }
        _refreshCompleter!.complete(true);
        _refreshCompleter = null;
        return true;
      }
    } on DioException catch (dioErr) {
      final status = dioErr.response?.statusCode;
      if (status == 400 || status == 401 || status == 403) {
        _cachedToken = null;
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove('access_token');
        await prefs.remove('refresh_token');
        onAuthSessionExpired?.call();
      }
    } catch (_) {}
    _refreshCompleter?.complete(false);
    _refreshCompleter = null;
    return false;
  }

  // Auth: Login
  Future<Response> login(String username, String password) async {
    return await dio.post('/auth/login', data: {
      'username': username,
      'password': password,
    });
  }

  // Auth: Register
  Future<Response> register({
    required String name,
    required String username,
    required String password,
    String? phone,
    String role = 'owner',
  }) async {
    return await dio.post('/auth/register', data: {
      'name': name,
      'username': username,
      'password': password,
      if (phone != null && phone.isNotEmpty) 'phone': phone,
      'role': role,
    });
  }

  // Admin: Get all staff users
  Future<Response> getAdminUsers() async {
    return await dio.get('/admin/users');
  }

  // Admin: Create staff user
  Future<Response> createAdminUser({
    required String name,
    required String username,
    required String password,
    String? phone,
    String role = 'employee',
  }) async {
    return await dio.post('/admin/users', data: {
      'name': name,
      'username': username,
      'password': password,
      if (phone != null && phone.isNotEmpty) 'phone': phone,
      'role': role,
    });
  }

  // Admin: Reset user password
  Future<Response> resetAdminUserPassword(String userId, String newPassword) async {
    final encodedId = Uri.encodeComponent(userId);
    return await dio.put('/admin/users/$encodedId/password', data: {
      'newPassword': newPassword,
    });
  }

  // Admin: Delete user
  Future<Response> deleteAdminUser(String userId) async {
    final encodedId = Uri.encodeComponent(userId);
    return await dio.delete('/admin/users/$encodedId');
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
    List<Map<String, dynamic>> products = const [],
  }) async {
    return await dio.post('/sync/push', data: {
      'deviceId': deviceId,
      'customers': customers,
      'invoices': invoices,
      'payments': payments,
      'products': products,
    });
  }

  // Sync Pull
  Future<Response> pullSync([String? sinceIsoDate]) async {
    final Map<String, dynamic> query = {};
    if (sinceIsoDate != null && sinceIsoDate.trim().isNotEmpty && sinceIsoDate != 'null') {
      query['since'] = sinceIsoDate;
    }
    return await dio.get('/sync/pull', queryParameters: query);
  }

  // Invoice Update
  Future<Response> updateInvoice(String id, Map<String, dynamic> invoiceData) async {
    return await dio.put('/invoices/$id', data: invoiceData);
  }

  // Invoice Delete
  Future<Response> deleteInvoice(String id) async {
    return await dio.delete('/invoices/$id');
  }

  // Customer Delete
  Future<Response> deleteCustomer(String id) async {
    return await dio.delete('/customers/$id');
  }

  // Product Delete
  Future<Response> deleteProduct(String id) async {
    return await dio.delete('/products/$id');
  }
}
