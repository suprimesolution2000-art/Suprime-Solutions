import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants/app_colors.dart';
import '../../core/utils/currency_formatter.dart';
import '../../core/utils/date_formatter.dart';
import '../../providers/invoice_provider.dart';
import '../../data/models/invoice_model.dart';
import 'invoice_detail_screen.dart';

class BillsScreen extends ConsumerStatefulWidget {
  const BillsScreen({super.key});

  @override
  ConsumerState<BillsScreen> createState() => _BillsScreenState();
}

class _BillsScreenState extends ConsumerState<BillsScreen> {
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final invoiceState = ref.watch(invoiceListProvider);
    final notifier = ref.read(invoiceListProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        title: const Text('All Invoices & Bills'),
        actions: [
          IconButton(
            icon: const Icon(Icons.date_range),
            tooltip: 'Filter by Date',
            onPressed: () => _showDateRangePicker(context, notifier),
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: () => notifier.fetchInvoices(),
          ),
        ],
      ),
      body: Column(
        children: [
          // 1. One Prominent Universal Search Bar
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search bill, customer, phone number…',
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

          // 2. Quick Filter Chips
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Row(
              children: [
                _buildFilterChip('All', 'all', invoiceState.filterChip, notifier),
                const SizedBox(width: 8),
                _buildFilterChip('Unpaid', 'unpaid', invoiceState.filterChip, notifier),
                const SizedBox(width: 8),
                _buildFilterChip('Partial', 'partial', invoiceState.filterChip, notifier),
                const SizedBox(width: 8),
                _buildFilterChip('Paid', 'paid', invoiceState.filterChip, notifier),
                const SizedBox(width: 8),
                _buildFilterChip('Overdue', 'overdue', invoiceState.filterChip, notifier),
              ],
            ),
          ),
          const Divider(height: 16),

          // 3. Invoices List
          Expanded(
            child: invoiceState.isLoading
                ? const Center(child: CircularProgressIndicator())
                : invoiceState.invoices.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.receipt_long_outlined, size: 64, color: AppColors.textMuted),
                            const SizedBox(height: 12),
                            Text(
                              _searchController.text.isNotEmpty
                                  ? 'No bills found matching "${_searchController.text}"'
                                  : 'No bills found in this filter',
                              style: const TextStyle(fontSize: 16, color: AppColors.textSecondary),
                            ),
                          ],
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: () async => notifier.fetchInvoices(),
                        child: ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          itemCount: invoiceState.invoices.length,
                          itemBuilder: (context, index) {
                            final inv = invoiceState.invoices[index];
                            return _buildInvoiceCard(context, inv);
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String label, String value, String currentVal, InvoiceListNotifier notifier) {
    final isSelected = currentVal == value;
    return FilterChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (_) => notifier.setFilterChip(value),
      selectedColor: AppColors.primaryContainer,
      checkmarkColor: AppColors.primary,
      labelStyle: TextStyle(
        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        color: isSelected ? AppColors.primary : AppColors.textPrimary,
      ),
    );
  }

  Widget _buildInvoiceCard(BuildContext context, InvoiceModel inv) {
    Color badgeBg;
    Color badgeText;
    String badgeLabel;

    if (inv.status == 'cancelled') {
      badgeBg = Colors.grey.shade200;
      badgeText = Colors.grey.shade700;
      badgeLabel = 'CANCELLED';
    } else if (inv.paymentStatus == 'paid') {
      badgeBg = AppColors.paidContainer;
      badgeText = AppColors.paid;
      badgeLabel = 'PAID';
    } else if (inv.paymentStatus == 'partially_paid') {
      badgeBg = AppColors.partialContainer;
      badgeText = AppColors.partial;
      badgeLabel = 'PARTIAL';
    } else {
      badgeBg = AppColors.unpaidContainer;
      badgeText = AppColors.unpaid;
      badgeLabel = 'UNPAID';
    }

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
              builder: (_) => InvoiceDetailScreen(invoice: inv),
            ),
          ).then((_) {
            ref.read(invoiceListProvider.notifier).fetchInvoices();
          });
        },
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Row 1: Invoice No & Payment Badge
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    inv.invoiceNumber,
                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: AppColors.primary),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                    decoration: BoxDecoration(
                      color: badgeBg,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      badgeLabel,
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: badgeText),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),

              // Row 2: Customer Name & Date
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      inv.customer.name,
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Text(
                    DateFormatter.format(inv.invoiceDate),
                    style: const TextStyle(fontSize: 13, color: AppColors.textMuted),
                  ),
                ],
              ),
              const SizedBox(height: 6),

              // Row 3: Items summary & Grand Total
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '${inv.items.length} ${inv.items.length == 1 ? 'item' : 'items'} • ${inv.customer.phone}',
                    style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
                  ),
                  Text(
                    CurrencyFormatter.format(inv.grandTotal),
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showDateRangePicker(BuildContext context, InvoiceListNotifier notifier) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Filter by Date Range', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              ListTile(
                leading: const Icon(Icons.today),
                title: const Text('Today'),
                onTap: () {
                  final now = DateTime.now();
                  notifier.setDateRange(DateTime(now.year, now.month, now.day), now);
                  Navigator.pop(context);
                },
              ),
              ListTile(
                leading: const Icon(Icons.view_week),
                title: const Text('Last 7 Days'),
                onTap: () {
                  final now = DateTime.now();
                  notifier.setDateRange(now.subtract(const Duration(days: 7)), now);
                  Navigator.pop(context);
                },
              ),
              ListTile(
                leading: const Icon(Icons.calendar_month),
                title: const Text('This Month'),
                onTap: () {
                  final now = DateTime.now();
                  notifier.setDateRange(DateTime(now.year, now.month, 1), now);
                  Navigator.pop(context);
                },
              ),
              ListTile(
                leading: const Icon(Icons.clear_all),
                title: const Text('Clear Date Filters'),
                onTap: () {
                  notifier.setDateRange(null, null);
                  Navigator.pop(context);
                },
              ),
            ],
          ),
        );
      },
    );
  }
}
