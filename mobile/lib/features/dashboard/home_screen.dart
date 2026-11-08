import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants/app_colors.dart';
import '../../core/utils/currency_formatter.dart';
import '../../providers/dashboard_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/customer_provider.dart';
import '../../providers/invoice_provider.dart';
import '../../services/sync/sync_service.dart';
import '../billing/create_bill_screen.dart';
import '../reports/reports_screen.dart';
import '../products/products_screen.dart';
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
                  errorBuilder: (context, error, stackTrace) => const Icon(Icons.business, color: AppColors.primary, size: 24),
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
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    'Industrial Gaskets & Hydraulics',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.normal, color: Colors.white70),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
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
              String tip = 'All bills synced with cloud';

              if (sync.status == SyncStatus.syncing) {
                icon = Icons.sync;
                color = Colors.amberAccent;
                tip = sync.pendingCount > 0
                    ? 'Syncing ${sync.pendingCount} bills with cloud...'
                    : 'Syncing with cloud...';
              } else if (sync.pendingCount > 0) {
                icon = Icons.cloud_upload_outlined;
                color = Colors.orangeAccent;
                tip = '${sync.pendingCount} ${sync.pendingCount == 1 ? "bill" : "bills"} waiting for internet to upload';
              } else if (sync.status == SyncStatus.offline) {
                icon = Icons.cloud_off;
                color = Colors.grey.shade400;
                tip = 'Offline mode (all local bills synced)';
              }

              return IconButton(
                icon: Icon(icon, color: color),
                tooltip: tip,
                onPressed: () async {
                  if (sync.status == SyncStatus.syncing) return;
                  final ok = await SyncService.instance.synchronize(forceFullSync: true);
                  await SyncService.instance.checkPendingQueue();
                  ref.read(dashboardProvider.notifier).refreshSummary();
                  ref.read(customerListProvider.notifier).fetchCustomers();
                  ref.read(invoiceListProvider.notifier).fetchInvoices();
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          ok
                              ? (sync.pendingCount == 0 ? 'All bills synced successfully!' : '${sync.pendingCount} bills waiting for internet')
                              : 'Offline: bills will upload automatically when connected',
                        ),
                        backgroundColor: ok ? (sync.pendingCount == 0 ? AppColors.paid : Colors.amber.shade800) : Colors.deepOrange,
                        duration: const Duration(seconds: 2),
                      ),
                    );
                  }
                },
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh Figures',
            onPressed: () async {
              await SyncService.instance.synchronize(forceFullSync: true);
              await ref.read(dashboardProvider.notifier).refreshSummary();
              ref.read(customerListProvider.notifier).fetchCustomers();
              ref.read(invoiceListProvider.notifier).fetchInvoices();
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          await SyncService.instance.synchronize(forceFullSync: true);
          await ref.read(dashboardProvider.notifier).refreshSummary();
          ref.read(customerListProvider.notifier).fetchCustomers();
          ref.read(invoiceListProvider.notifier).fetchInvoices();
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
                  Expanded(
                    child: Text(
                      'Namaste, ${auth.user?.name ?? 'User'}',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
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
                label: const FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    'CREATE NEW BILL',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, letterSpacing: 0.8),
                  ),
                ),
                onPressed: () => _openCreateBillWithSelection(context, ref),
              ),

              // Offline Sync Status Banner (Only visible when local bills await cloud upload)
              ListenableBuilder(
                listenable: SyncService.instance,
                builder: (context, _) {
                  final sync = SyncService.instance;
                  if (sync.pendingCount <= 0) return const SizedBox.shrink();

                  return Container(
                    margin: const EdgeInsets.only(top: 14),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.amber.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.amber.shade400, width: 1.2),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          sync.isSyncing ? Icons.sync : Icons.cloud_upload_outlined,
                          color: Colors.amber.shade900,
                          size: 22,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            sync.isSyncing
                                ? 'Uploading ${sync.pendingCount} local ${sync.pendingCount == 1 ? "bill" : "bills"} to cloud...'
                                : '${sync.pendingCount} local ${sync.pendingCount == 1 ? "bill is" : "bills are"} saved offline and waiting to upload to cloud.',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: Colors.amber.shade900,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        if (!sync.isSyncing)
                          TextButton(
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              backgroundColor: Colors.amber.shade700,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              visualDensity: VisualDensity.compact,
                            ),
                            onPressed: () async {
                              final ok = await sync.synchronize(forceFullSync: true);
                              ref.read(invoiceListProvider.notifier).fetchInvoices();
                              ref.read(customerListProvider.notifier).fetchCustomers();
                              ref.read(dashboardProvider.notifier).refreshSummary();
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      sync.pendingCount == 0
                                          ? 'All bills uploaded and synced with cloud!'
                                          : '${sync.pendingCount} bills saved offline. Cloud server is waking up, please tap SYNC again in a few seconds.',
                                    ),
                                    backgroundColor: sync.pendingCount == 0 ? AppColors.paid : Colors.amber.shade900,
                                    duration: const Duration(seconds: 3),
                                  ),
                                );
                              }
                            },
                            child: const Text(
                              'SYNC NOW',
                              style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                            ),
                          )
                        else
                          const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                      ],
                    ),
                  );
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
                  const SizedBox(width: 8),
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
                  const SizedBox(width: 8),
                  Expanded(
                    child: _buildQuickActionButton(
                      icon: Icons.inventory_2,
                      label: 'Products',
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const ProductsScreen()),
                        );
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
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
        border: Border.all(color: color.withValues(alpha: 0.2), width: 1.2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textSecondary),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Icon(icon, color: color, size: 20),
            ],
          ),
          const SizedBox(height: 8),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              amount,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: color,
              ),
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
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          children: [
            Icon(icon, color: AppColors.primary, size: 28),
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  label,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openCreateBillWithSelection(BuildContext context, WidgetRef ref) async {
    final selectedType = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: Container(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
          decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Select Bill Format',
              style: TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            const Text(
              'Choose which type of bill you want to generate:',
              style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),

            // 1. GST Bill Option
            InkWell(
              onTap: () => Navigator.pop(ctx, 'gst'),
              borderRadius: BorderRadius.circular(14),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  border: Border.all(color: AppColors.primary, width: 1.5),
                  borderRadius: BorderRadius.circular(14),
                  color: AppColors.primary.withValues(alpha: 0.04),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.receipt_long, color: AppColors.primary, size: 28),
                    ),
                    const SizedBox(width: 14),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  'GST Bill',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.primary,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              SizedBox(width: 8),
                              Chip(
                                label: Text(
                                  'OFFICIAL TAX',
                                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white),
                                ),
                                backgroundColor: AppColors.primary,
                                padding: EdgeInsets.zero,
                                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                visualDensity: VisualDensity.compact,
                              ),
                            ],
                          ),
                          SizedBox(height: 4),
                          Text(
                            'Official tax invoice with CGST/SGST/IGST breakdown and HSN summary.',
                            style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.arrow_forward_ios, size: 16, color: AppColors.textSecondary),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),

            // 2. Temporary Bill Option
            InkWell(
              onTap: () => Navigator.pop(ctx, 'temporary'),
              borderRadius: BorderRadius.circular(14),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  border: Border.all(color: const Color(0xFF8B5A2B), width: 1.5),
                  borderRadius: BorderRadius.circular(14),
                  color: const Color(0xFF8B5A2B).withValues(alpha: 0.05),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF8B5A2B).withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.history_edu, color: Color(0xFF8B5A2B), size: 28),
                    ),
                    const SizedBox(width: 14),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  'Temporary Bill',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF8B5A2B),
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              SizedBox(width: 8),
                              Chip(
                                label: Text(
                                  'WOOD THEME',
                                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white),
                                ),
                                backgroundColor: Color(0xFF8B5A2B),
                                padding: EdgeInsets.zero,
                                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                visualDensity: VisualDensity.compact,
                              ),
                            ],
                          ),
                          SizedBox(height: 4),
                          Text(
                            'Estimate / Non-GST bill on custom wood-themed template with matched colors.',
                            style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.arrow_forward_ios, size: 16, color: AppColors.textSecondary),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );

    if (selectedType == null || !context.mounted) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CreateBillScreen(initialInvoiceType: selectedType),
      ),
    ).then((_) {
      ref.read(dashboardProvider.notifier).refreshSummary();
      ref.read(customerListProvider.notifier).fetchCustomers();
    });
  }
}
