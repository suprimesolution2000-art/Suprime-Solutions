import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dio/dio.dart';
import '../data/models/user_model.dart';
import '../services/api/api_client.dart';
import '../services/sync/sync_service.dart';

class AuthState {
  final UserModel? user;
  final bool isLoading;
  final String? errorMessage;
  final bool isAuthenticated;

  AuthState({
    this.user,
    this.isLoading = false,
    this.errorMessage,
    this.isAuthenticated = false,
  });

  bool get isOwner => user?.isOwner ?? false;
  bool get isEmployee => user?.isEmployee ?? false;

  AuthState copyWith({
    UserModel? user,
    bool? isLoading,
    String? errorMessage,
    bool? isAuthenticated,
  }) {
    return AuthState(
      user: user ?? this.user,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: errorMessage,
      isAuthenticated: isAuthenticated ?? this.isAuthenticated,
    );
  }
}

class AuthNotifier extends StateNotifier<AuthState> {
  AuthNotifier() : super(AuthState()) {
    checkSavedSession();
  }

  Future<void> checkSavedSession() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('access_token');
    final name = prefs.getString('user_name');
    final username = prefs.getString('user_username');
    final role = prefs.getString('user_role') ?? 'owner';
    final userId = prefs.getString('user_id') ?? 'user_1';

    if (token != null && token.isNotEmpty && name != null && name.isNotEmpty) {
      state = state.copyWith(
        isAuthenticated: true,
        user: UserModel(id: userId, name: name, username: username ?? '', role: role),
      );
    } else {
      state = state.copyWith(
        isAuthenticated: false,
        user: null,
      );
    }
  }

  Future<bool> login(String username, String password) async {
    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      final res = await ApiClient.instance.login(username.trim(), password);
      if (res.statusCode == 200 && res.data['success'] == true) {
        final userData = res.data['user'];
        final user = UserModel.fromMap(userData);
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('access_token', res.data['accessToken']);
        if (res.data['refreshToken'] != null) {
          await prefs.setString('refresh_token', res.data['refreshToken']);
        }
        await prefs.setString('user_id', user.id);
        await prefs.setString('user_name', user.name);
        await prefs.setString('user_role', user.role);
        await prefs.setString('user_username', user.username);

        state = state.copyWith(
          isLoading: false,
          isAuthenticated: true,
          user: user,
          errorMessage: null,
        );

        // Immediate background sync on successful login
        SyncService.instance.synchronize();
        return true;
      } else {
        state = state.copyWith(
          isLoading: false,
          errorMessage: res.data['message'] ?? 'Login failed. Please check credentials.',
        );
        return false;
      }
    } on DioException catch (dioErr) {
      String msg = 'Could not connect to server.';
      if (dioErr.response?.data != null && dioErr.response?.data is Map) {
        msg = dioErr.response?.data['message'] ?? msg;
      } else if (dioErr.type == DioExceptionType.connectionTimeout ||
          dioErr.type == DioExceptionType.receiveTimeout) {
        msg = 'Connection timed out. Render backend may be waking up, please retry.';
      }
      state = state.copyWith(
        isLoading: false,
        errorMessage: msg,
      );
      return false;
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'An error occurred during login: $e',
      );
      return false;
    }
  }

  Future<bool> register({
    required String name,
    required String username,
    required String password,
    String? phone,
  }) async {
    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      final res = await ApiClient.instance.register(
        name: name.trim(),
        username: username.trim(),
        password: password,
        phone: phone?.trim(),
        role: 'owner',
      );
      if ((res.statusCode == 200 || res.statusCode == 201) && res.data['success'] == true) {
        final userData = res.data['user'];
        final user = UserModel.fromMap(userData);
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('access_token', res.data['accessToken']);
        if (res.data['refreshToken'] != null) {
          await prefs.setString('refresh_token', res.data['refreshToken']);
        }
        await prefs.setString('user_id', user.id);
        await prefs.setString('user_name', user.name);
        await prefs.setString('user_role', user.role);
        await prefs.setString('user_username', user.username);

        state = state.copyWith(
          isLoading: false,
          isAuthenticated: true,
          user: user,
          errorMessage: null,
        );

        // Immediate background sync on successful register
        SyncService.instance.synchronize();
        return true;
      } else {
        state = state.copyWith(
          isLoading: false,
          errorMessage: res.data['message'] ?? 'Registration failed',
        );
        return false;
      }
    } on DioException catch (dioErr) {
      String msg = 'Could not connect to server.';
      if (dioErr.response?.data != null && dioErr.response?.data is Map) {
        msg = dioErr.response?.data['message'] ?? msg;
      }
      state = state.copyWith(
        isLoading: false,
        errorMessage: msg,
      );
      return false;
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'An error occurred during registration: $e',
      );
      return false;
    }
  }

  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('access_token');
    await prefs.remove('refresh_token');
    await prefs.remove('user_id');
    await prefs.remove('user_name');
    await prefs.remove('user_role');
    await prefs.remove('user_username');
    state = AuthState(isAuthenticated: false, user: null);
  }
}

final authProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  return AuthNotifier();
});
