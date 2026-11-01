import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants/app_colors.dart';
import '../../core/utils/currency_formatter.dart';
import '../../providers/dashboard_provider.dart';
import '../../providers/auth_provider.dart';
import '../../services/sync/sync_service.dart';
import '../billing/create_bill_screen.dart';
import '../reports/reports_screen.dart';
import '../navigation/main_scaffold.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summary = ref.watch(dashboardProvider);
    final auth = ref.watch(authProvider);

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              margin: const EdgeInsets.only(right: 10),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.1),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: ClipOval(
                child: Image.asset(
                  'assets/images/app_logo.png',
                  fit: BoxFit.cover,
                ),
              ),
            ),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Suprime Solutions',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                  ),
                  Text(
                    'Industrial Gaskets & Hydraulics',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.normal, color: Colors.white70),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          // Live Sync Status Button
          ListenableBuilder(
            listenable: SyncService.instance,
            builder: (context, _) {
              final sync = SyncService.instance;
              IconData icon = Icons.cloud_done;
              Color color = Colors.greenAccent;
              String tip = 'Synced with cloud';

              if (sync.status == SyncStatus.syncing) {
                icon = Icons.sync;
                color = Colors.amberAccent;
                tip = 'Syncing...';
              } else if (sync.status == SyncStatus.offline || sync.pendingCount > 0) {
                icon = Icons.cloud_off;
                color = Colors.orangeAccent;
                tip = '${sync.pendingCount} bills waiting for internet';
              }

              return IconButton(
                icon: Icon(icon, color: color),
                tooltip: tip,
                onPressed: () {
                  SyncService.instance.synchronize();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(sync.statusMessage),
                      duration: const Duration(seconds: 2),
                    ),
                  );
                },
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh Figures',
            onPressed: () {
              ref.read(dashboardProvider.notifier).refreshSummary();
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          await ref.read(dashboardProvider.notifier).refreshSummary();
          await SyncService.instance.synchronize();
        },
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // User Greeting & Role Badge
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Namaste, ${auth.user?.name ?? 'Father'}',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: auth.isOwner ? AppColors.primaryContainer : Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      auth.isOwner ? 'OWNER' : 'STAFF',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: auth.isOwner ? AppColors.primary : Colors.blue.shade800,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // THE MOST PROMINENT ACTION: CREATE NEW BILL
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(double.infinity, 64),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  elevation: 3,
                ),
                icon: const Icon(Icons.add_circle, size: 28),
                label: const Text(
                  'CREATE NEW BILL',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, letterSpacing: 0.8),
                ),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const CreateBillScreen()),
                  ).then((_) {
                    ref.read(dashboardProvider.notifier).refreshSummary();
                  });
                },
              ),
              const SizedBox(height: 24),

              // Summary Section Header
              const Text(
                'Business Overview',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 12),

              // Summary Cards
              Row(
                children: [
                  // Today's Sales
                  Expanded(
                    child: _buildSummaryCard(
                      title: "Today's Sales",
                      amount: CurrencyFormatter.format(summary.todaySales),
                      subtext: '${summary.todayCount} Bills today',
                      icon: Icons.today,
                      color: AppColors.primary,
                      bgColor: AppColors.surfaceLight,
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Month's Sales
                  Expanded(
                    child: _buildSummaryCard(
                      title: "Month's Sales",
                      amount: CurrencyFormatter.format(summary.monthlySales),
                      subtext: '${summary.monthlyCount} Bills this month',
                      icon: Icons.calendar_month,
                      color: Colors.blue.shade700,
                      bgColor: Colors.blue.shade50,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Pending Payments Card
              _buildSummaryCard(
                title: 'Pending / Due Payments',
                amount: CurrencyFormatter.format(summary.pendingPayments),
                subtext: '${summary.pendingCount} unpaid / partial invoices',
                icon: Icons.pending_actions,
                color: AppColors.unpaid,
                bgColor: AppColors.unpaidContainer,
              ),
              const SizedBox(height: 24),

              // Quick Actions
              const Text(
                'Quick Actions',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 12),

              Row(
                children: [
                  Expanded(
                    child: _buildQuickActionButton(
                      icon: Icons.receipt_long,
                      label: 'All Bills',
                      onTap: () {
                        Navigator.pushReplacement(
                          context,
                          MaterialPageRoute(builder: (_) => const MainScaffold(initialIndex: 1)),
                        );
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildQuickActionButton(
                      icon: Icons.people,
                      label: 'Customers',
                      onTap: () {
                        Navigator.pushReplacement(
                          context,
                          MaterialPageRoute(builder: (_) => const MainScaffold(initialIndex: 2)),
                        );
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildQuickActionButton(
                      icon: Icons.bar_chart,
                      label: 'Reports',
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const ReportsScreen()),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSummaryCard({
    required String title,
    required String amount,
    required String subtext,
    required IconData icon,
    required Color color,
    required Color bgColor,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.2), width: 1.2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textSecondary),
              ),
              Icon(icon, color: color, size: 20),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            amount,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtext,
            style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickActionButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.border),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.03),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          children: [
            Icon(icon, color: AppColors.primary, size: 28),
            const SizedBox(height: 6),
            Text(
              label,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
            ),
          ],
        ),
      ),
    );
  }
}
