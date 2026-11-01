import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/theme/app_theme.dart';
import 'core/constants/app_constants.dart';
import 'data/database/app_database.dart';
import 'services/api/api_client.dart';
import 'services/sync/sync_service.dart';
import 'features/navigation/main_scaffold.dart';
import 'features/auth/login_screen.dart';
import 'providers/auth_provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize API client
  await ApiClient.instance.init();

  // Initialize local SQLite database
  await AppDatabase.instance.database;

  // Initialize Sync service
  await SyncService.instance.initialize();

  runApp(
    const ProviderScope(
      child: SSSupremeSolutionsApp(),
    ),
  );
}

class SSSupremeSolutionsApp extends ConsumerWidget {
  const SSSupremeSolutionsApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authProvider);

    return MaterialApp(
      title: AppConstants.appName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      home: auth.isAuthenticated ? const MainScaffold() : const LoginScreen(),
    );
  }
}
