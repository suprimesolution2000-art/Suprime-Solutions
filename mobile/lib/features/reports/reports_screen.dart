import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../../core/utils/currency_formatter.dart';
import '../../data/repositories/invoice_repository.dart';
import '../../data/repositories/customer_repository.dart';
import '../../data/models/customer_model.dart';

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  bool _isLoading = true;
  Map<String, dynamic> _summary = {};
  List<CustomerModel> _outstandingParties = [];

  @override
  void initState() {
    super.initState();
    _loadReports();
  }

  Future<void> _loadReports() async {
    setState(() => _isLoading = true);
    final sum = await InvoiceRepository().getDashboardSummary();
    final allCust = await CustomerRepository().getAllCustomers();
    final outstanding = allCust.where((c) => c.outstandingBalance > 0).toList();
    outstanding.sort((a, b) => b.outstandingBalance.compareTo(a.outstandingBalance));

    if (mounted) {
      setState(() {
        _summary = sum;
        _outstandingParties = outstanding;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sales & Dues Reports'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadReports,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadReports,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Period Totals
                    const Text(
                      'Sales Summary',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                    ),
                    const SizedBox(height: 12),

                    _buildReportItem(
                      title: "Today's Total Sales",
                      value: CurrencyFormatter.format((_summary['todaySales'] as num?)?.toDouble() ?? 0.0),
                      sub: '${_summary['todayCount'] ?? 0} bills issued today',
                      icon: Icons.today,
                      color: AppColors.primary,
                    ),
                    const SizedBox(height: 10),

                    _buildReportItem(
                      title: "This Month's Total Sales",
                      value: CurrencyFormatter.format((_summary['monthlySales'] as num?)?.toDouble() ?? 0.0),
                      sub: '${_summary['monthlyCount'] ?? 0} bills issued this month',
                      icon: Icons.calendar_month,
                      color: Colors.blue.shade700,
                    ),
                    const SizedBox(height: 10),

                    _buildReportItem(
                      title: "Total Outstanding Receivables",
                      value: CurrencyFormatter.format((_summary['pendingPayments'] as num?)?.toDouble() ?? 0.0),
                      sub: 'Across ${_summary['pendingCount'] ?? 0} unpaid / partial bills',
                      icon: Icons.pending_actions,
                      color: AppColors.unpaid,
                    ),
                  const SizedBox(height: 24),

                  // Top Outstanding Customers
                  const Text(
                    'Top Pending Receivables by Customer',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                  ),
                  const SizedBox(height: 12),

                  if (_outstandingParties.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(24),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: AppColors.surfaceLight,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Column(
                        children: [
                          Icon(Icons.check_circle_outline, color: AppColors.paid, size: 48),
                          SizedBox(height: 8),
                          Text('All bills are paid! Zero outstanding dues.', style: TextStyle(fontWeight: FontWeight.bold)),
                        ],
                      ),
                    )
                  else
                    ..._outstandingParties.take(10).map((c) {
                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          title: Text(c.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                          subtitle: Text('Phone: ${c.phone}'),
                          trailing: Text(
                            CurrencyFormatter.format(c.outstandingBalance),
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.unpaid),
                          ),
                        ),
                      );
                    }),
                ],
              ),
            ),
          ),
    );
  }

  Widget _buildReportItem({
    required String title,
    required String value,
    required String sub,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: color.withValues(alpha: 0.12),
            radius: 24,
            child: Icon(icon, color: color, size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
                const SizedBox(height: 4),
                Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: color)),
                const SizedBox(height: 2),
                Text(sub, style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
