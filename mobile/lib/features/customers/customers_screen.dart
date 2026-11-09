import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants/app_colors.dart';
import '../../core/utils/currency_formatter.dart';
import '../../providers/customer_provider.dart';
import '../../providers/dashboard_provider.dart';
import '../../data/models/customer_model.dart';
import '../../data/repositories/customer_repository.dart';
import '../../services/api/api_client.dart';
import '../../services/sync/sync_service.dart';
import 'customer_ledger_screen.dart';
import 'add_customer_dialog.dart';

class CustomersScreen extends ConsumerStatefulWidget {
  const CustomersScreen({super.key});

  @override
  ConsumerState<CustomersScreen> createState() => _CustomersScreenState();
}

class _CustomersScreenState extends ConsumerState<CustomersScreen> {
  final _searchController = TextEditingController();
  String _paymentFilter = 'all'; // 'all', 'due', 'cleared'

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final customerState = ref.watch(customerListProvider);
    final notifier = ref.read(customerListProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Customer Directory'),
        actions: [
          IconButton(
            icon: const Icon(Icons.person_add),
            tooltip: 'Add Customer',
            onPressed: () {
              showDialog(
                context: context,
                builder: (_) => AddCustomerDialog(
                  onCustomerAdded: (newCust) {
                    notifier.fetchCustomers();
                  },
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Sync & Refresh',
            onPressed: () async {
              await SyncService.instance.synchronize(forceFullSync: true);
              await notifier.fetchCustomers();
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Search Bar
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search customer name, phone, GSTIN…',
                prefixIcon: const Icon(Icons.search, color: AppColors.primary),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          setState(() {});
                          notifier.setSearchQuery('');
                        },
                      )
                    : null,
              ),
              onChanged: (val) {
                setState(() {});
                notifier.setSearchQuery(val);
              },
            ),
          ),

          // Payment Status Filter Chips
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
            child: Row(
              children: [
                FilterChip(
                  label: Text('All (${customerState.customers.length})'),
                  selected: _paymentFilter == 'all',
                  onSelected: (_) => setState(() => _paymentFilter = 'all'),
                  selectedColor: AppColors.primaryContainer,
                  checkmarkColor: AppColors.primary,
                  labelStyle: TextStyle(
                    fontWeight: _paymentFilter == 'all' ? FontWeight.bold : FontWeight.normal,
                    color: _paymentFilter == 'all' ? AppColors.primary : AppColors.textPrimary,
                  ),
                ),
                const SizedBox(width: 8),
                FilterChip(
                  label: Text('With Due (${customerState.customers.where((c) => c.outstandingBalance > 0.005).length})'),
                  selected: _paymentFilter == 'due',
                  onSelected: (_) => setState(() => _paymentFilter = 'due'),
                  selectedColor: AppColors.unpaidContainer,
                  checkmarkColor: AppColors.unpaid,
                  labelStyle: TextStyle(
                    fontWeight: _paymentFilter == 'due' ? FontWeight.bold : FontWeight.normal,
                    color: _paymentFilter == 'due' ? AppColors.unpaid : AppColors.textPrimary,
                  ),
                ),
                const SizedBox(width: 8),
                FilterChip(
                  label: Text('Paid / Clear (${customerState.customers.where((c) => c.outstandingBalance <= 0.005).length})'),
                  selected: _paymentFilter == 'cleared',
                  onSelected: (_) => setState(() => _paymentFilter = 'cleared'),
                  selectedColor: AppColors.paidContainer,
                  checkmarkColor: AppColors.paid,
                  labelStyle: TextStyle(
                    fontWeight: _paymentFilter == 'cleared' ? FontWeight.bold : FontWeight.normal,
                    color: _paymentFilter == 'cleared' ? AppColors.paid : AppColors.textPrimary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),

          // Customers List
          Expanded(
            child: customerState.isLoading
                ? const Center(child: CircularProgressIndicator())
                : customerState.customers.isEmpty
                    ? RefreshIndicator(
                        onRefresh: () async {
                          await CustomerRepository().recalculateCustomerBalances();
                          await SyncService.instance.synchronize(forceFullSync: true);
                          await notifier.fetchCustomers();
                        },
                        child: SingleChildScrollView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
                          child: Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.people_outline, size: 64, color: AppColors.textMuted),
                                const SizedBox(height: 12),
                                Text(
                                  _searchController.text.isNotEmpty
                                      ? 'No customers found matching "${_searchController.text}"'
                                      : 'No customers added yet',
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(fontSize: 16, color: AppColors.textSecondary),
                                ),
                                const SizedBox(height: 8),
                                const Text(
                                  'Pull down to sync from cloud',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(fontSize: 12, color: AppColors.textMuted),
                                ),
                              ],
                            ),
                          ),
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: () async {
                          await CustomerRepository().recalculateCustomerBalances();
                          await SyncService.instance.synchronize(forceFullSync: true);
                          await notifier.fetchCustomers();
                        },
                        child: Builder(
                          builder: (context) {
                            final filteredList = customerState.customers.where((c) {
                              if (_paymentFilter == 'due') return c.outstandingBalance > 0.005;
                              if (_paymentFilter == 'cleared') return c.outstandingBalance <= 0.005;
                              return true;
                            }).toList();

                            if (filteredList.isEmpty) {
                              return Center(
                                child: Padding(
                                  padding: const EdgeInsets.all(24),
                                  child: Text(
                                    'No customers found in this payment filter',
                                    style: const TextStyle(fontSize: 15, color: AppColors.textSecondary),
                                  ),
                                ),
                              );
                            }

                            return ListView.builder(
                              padding: const EdgeInsets.symmetric(horizontal: 16),
                              itemCount: filteredList.length,
                              itemBuilder: (context, index) {
                                final c = filteredList[index];
                                return _buildCustomerCard(context, c);
                              },
                            );
                          },
                        ),
                      ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('Add Customer'),
        onPressed: () {
          showDialog(
            context: context,
            builder: (_) => AddCustomerDialog(
              onCustomerAdded: (newCust) {
                notifier.fetchCustomers();
              },
            ),
          );
        },
      ),
    );
  }

  Widget _buildCustomerCard(BuildContext context, CustomerModel customer) {
    final hasDue = customer.outstandingBalance > 0.005;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 1.5,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => CustomerLedgerScreen(customer: customer),
            ),
          ).then((_) {
            ref.read(customerListProvider.notifier).fetchCustomers();
          });
        },
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: hasDue ? AppColors.unpaidContainer : AppColors.primaryContainer,
                child: Text(
                  customer.name.isNotEmpty ? customer.name[0].toUpperCase() : 'C',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: hasDue ? AppColors.unpaid : AppColors.primary,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            customer.name,
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: hasDue ? AppColors.unpaidContainer : AppColors.paidContainer,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            hasDue ? 'DUE' : 'CLEAR',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: hasDue ? AppColors.unpaid : AppColors.paid,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      customer.phone + (customer.gstin.isNotEmpty ? ' • ${customer.gstin}' : ''),
                      style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (customer.address.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        customer.address,
                        style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 105),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    const Text('Outstanding Due', style: TextStyle(fontSize: 11, color: AppColors.textMuted), overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 2),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        CurrencyFormatter.format(customer.outstandingBalance),
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: hasDue ? AppColors.unpaid : AppColors.paid,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 4),
              SizedBox(
                width: 44,
                height: 44,
                child: PopupMenuButton<String>(
                  padding: EdgeInsets.zero,
                  icon: const Icon(Icons.more_vert, size: 20, color: AppColors.textMuted),
                  onSelected: (val) {
                    if (val == 'ledger') {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => CustomerLedgerScreen(customer: customer),
                        ),
                      ).then((_) {
                        ref.read(customerListProvider.notifier).fetchCustomers();
                      });
                    } else if (val == 'delete') {
                      _confirmDeleteCustomer(context, customer);
                    }
                  },
                  itemBuilder: (context) => [
                    const PopupMenuItem(
                      value: 'ledger',
                      child: Row(
                        children: [
                          Icon(Icons.receipt_long, size: 18, color: AppColors.primary),
                          SizedBox(width: 8),
                          Text('View Ledger'),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'delete',
                      child: Row(
                        children: [
                          Icon(Icons.delete_outline, size: 18, color: Colors.red),
                          SizedBox(width: 8),
                          Text('Delete Customer', style: TextStyle(color: Colors.red)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _confirmDeleteCustomer(BuildContext context, CustomerModel customer) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.red, size: 28),
            SizedBox(width: 10),
            Expanded(
              child: Text('Delete Customer?', overflow: TextOverflow.ellipsis),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Are you sure you want to delete "${customer.name}"?',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 10),
            if (customer.outstandingBalance > 0)
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red.shade200),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline, color: Colors.red, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Warning: Customer has outstanding balance of ${CurrencyFormatter.format(customer.outstandingBalance)}.',
                        style: TextStyle(color: Colors.red.shade800, fontSize: 13, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 10),
            const Text(
              'This customer will be removed from your active directory across all synced devices. Prior invoices remain for accounting/GST records.',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      await CustomerRepository().deleteCustomer(customer.uuid);
      try {
        await ApiClient.instance.deleteCustomer(customer.uuid);
      } catch (_) {}
      ref.read(customerListProvider.notifier).fetchCustomers();
      ref.read(dashboardProvider.notifier).refreshSummary();
      SyncService.instance.synchronize();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Customer "${customer.name}" deleted.'),
            backgroundColor: Colors.black87,
          ),
        );
      }
    }
  }
}
