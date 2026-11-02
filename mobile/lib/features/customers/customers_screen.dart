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
                          notifier.setSearchQuery('');
                        },
                      )
                    : null,
              ),
              onChanged: (val) {
                notifier.setSearchQuery(val);
              },
            ),
          ),

          // Customers List
          Expanded(
            child: customerState.isLoading
                ? const Center(child: CircularProgressIndicator())
                : customerState.customers.isEmpty
                    ? RefreshIndicator(
                        onRefresh: () async {
                          await SyncService.instance.synchronize(forceFullSync: true);
                          await notifier.fetchCustomers();
                        },
                        child: SingleChildScrollView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          child: Container(
                            height: 350,
                            alignment: Alignment.center,
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.people_outline, size: 64, color: AppColors.textMuted),
                                const SizedBox(height: 12),
                                Text(
                                  _searchController.text.isNotEmpty
                                      ? 'No customers found matching "${_searchController.text}"'
                                      : 'No customers added yet',
                                  style: const TextStyle(fontSize: 16, color: AppColors.textSecondary),
                                ),
                                const SizedBox(height: 8),
                                const Text(
                                  'Pull down to sync from cloud',
                                  style: TextStyle(fontSize: 12, color: AppColors.textMuted),
                                ),
                              ],
                            ),
                          ),
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: () async {
                          await SyncService.instance.synchronize(forceFullSync: true);
                          await notifier.fetchCustomers();
                        },
                        child: ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          itemCount: customerState.customers.length,
                          itemBuilder: (context, index) {
                            final c = customerState.customers[index];
                            return _buildCustomerCard(context, c);
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
    final hasDue = customer.outstandingBalance > 0;

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
                    Text(
                      customer.name,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
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
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  const Text('Outstanding Due', style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
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
              const SizedBox(width: 4),
              PopupMenuButton<String>(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
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
            Text('Delete Customer?'),
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
