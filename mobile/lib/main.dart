import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/theme/app_theme.dart';
import 'core/constants/app_constants.dart';
import 'data/database/app_database.dart';
import 'services/api/api_client.dart';
import 'services/sync/sync_service.dart';
import 'features/navigation/main_scaffold.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize saved server URL
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

class SSSupremeSolutionsApp extends StatelessWidget {
  const SSSupremeSolutionsApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AppConstants.appName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      home: const MainScaffold(),
    );
  }
}
