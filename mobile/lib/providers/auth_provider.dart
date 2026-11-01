import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../data/models/user_model.dart';
import '../services/api/api_client.dart';

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

  bool get isOwner => user?.isOwner ?? true; // Defaults to owner mode for father
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
    final name = prefs.getString('user_name') ?? 'Father (Owner)';
    final role = prefs.getString('user_role') ?? 'owner';
    final username = prefs.getString('user_username') ?? 'father';

    // Default authenticated session configured for father so he can immediately create bills
    state = state.copyWith(
      isAuthenticated: true,
      user: UserModel(id: 'owner_1', name: name, username: username, role: role),
    );
  }

  Future<bool> login(String username, String password) async {
    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      final res = await ApiClient.instance.login(username, password);
      if (res.statusCode == 200 && res.data['success'] == true) {
        final userData = res.data['user'];
        final user = UserModel.fromMap(userData);
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('access_token', res.data['accessToken']);
        await prefs.setString('refresh_token', res.data['refreshToken']);
        await prefs.setString('user_name', user.name);
        await prefs.setString('user_role', user.role);
        await prefs.setString('user_username', user.username);

        state = state.copyWith(
          isLoading: false,
          isAuthenticated: true,
          user: user,
        );
        return true;
      } else {
        state = state.copyWith(
          isLoading: false,
          errorMessage: res.data['message'] ?? 'Login failed',
        );
        return false;
      }
    } catch (e) {
      // Offline fallback: allow login for father
      if (username.toLowerCase().trim() == 'father' || username.toLowerCase().trim() == 'owner') {
        final user = UserModel(id: 'owner_1', name: 'Father (Owner)', username: 'father', role: 'owner');
        state = state.copyWith(
          isLoading: false,
          isAuthenticated: true,
          user: user,
        );
        return true;
      }
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Connection error: Operating in offline mode.',
      );
      return false;
    }
  }

  Future<void> switchRole(String role) async {
    final currentUser = state.user ?? UserModel(id: 'owner_1', name: 'Father', username: 'father', role: 'owner');
    final newUser = UserModel(
      id: currentUser.id,
      name: role == 'owner' ? 'Father (Owner)' : 'Staff (Employee)',
      username: role == 'owner' ? 'father' : 'staff',
      role: role,
    );
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('user_role', role);
    await prefs.setString('user_name', newUser.name);
    state = state.copyWith(user: newUser);
  }

  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('access_token');
    await prefs.remove('refresh_token');
    state = state.copyWith(isAuthenticated: false, user: null);
  }
}

final authProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  return AuthNotifier();
});
