import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants/app_colors.dart';
import '../../core/utils/currency_formatter.dart';
import '../../providers/customer_provider.dart';
import '../../data/models/customer_model.dart';
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
                    ),
                    const SizedBox(height: 2),
                    Text(
                      customer.phone + (customer.gstin.isNotEmpty ? ' • ${customer.gstin}' : ''),
                      style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
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
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  const Text('Outstanding Due', style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
                  const SizedBox(height: 2),
                  Text(
                    CurrencyFormatter.format(customer.outstandingBalance),
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: hasDue ? AppColors.unpaid : AppColors.paid,
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
}
