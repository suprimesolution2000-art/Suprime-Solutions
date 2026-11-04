import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../../services/sync/sync_service.dart';
import '../../services/updater/app_update_service.dart';
import '../dashboard/home_screen.dart';
import '../invoices/bills_screen.dart';
import '../customers/customers_screen.dart';
import '../settings/settings_screen.dart';

class MainScaffold extends StatefulWidget {
  final int initialIndex;
  const MainScaffold({super.key, this.initialIndex = 0});

  @override
  State<MainScaffold> createState() => _MainScaffoldState();
}

class _MainScaffoldState extends State<MainScaffold> {
  late int _currentIndex;

  final List<Widget> _screens = const [
    HomeScreen(),
    BillsScreen(),
    CustomersScreen(),
    SettingsScreen(),
  ];

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    // Auto-sync in background whenever MainScaffold loads
    WidgetsBinding.instance.addPostFrameCallback((_) {
      SyncService.instance.synchronize();
      Future.delayed(const Duration(seconds: 3), () {
        if (mounted) {
          AppUpdateService.instance.checkForUpdate(context: context, silent: true);
        }
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: _screens,
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
        backgroundColor: Colors.white,
        indicatorColor: AppColors.primaryContainer,
        elevation: 6,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined, size: 26),
            selectedIcon: Icon(Icons.home, color: AppColors.primary, size: 28),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.receipt_long_outlined, size: 26),
            selectedIcon: Icon(Icons.receipt_long, color: AppColors.primary, size: 28),
            label: 'Bills',
          ),
          NavigationDestination(
            icon: Icon(Icons.people_outline, size: 26),
            selectedIcon: Icon(Icons.people, color: AppColors.primary, size: 28),
            label: 'Customers',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined, size: 26),
            selectedIcon: Icon(Icons.settings, color: AppColors.primary, size: 28),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}
