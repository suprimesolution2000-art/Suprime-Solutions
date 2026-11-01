import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants/app_colors.dart';
import '../../core/utils/currency_formatter.dart';
import '../../core/utils/date_formatter.dart';
import '../../providers/invoice_provider.dart';
import '../../providers/auth_provider.dart';
import '../../data/models/invoice_model.dart';
import '../../data/repositories/invoice_repository.dart';
import '../../services/pdf/pdf_invoice_service.dart';
import '../../services/api/api_client.dart';
import 'invoice_detail_screen.dart';

class BillsScreen extends ConsumerStatefulWidget {
  const BillsScreen({super.key});

  @override
  ConsumerState<BillsScreen> createState() => _BillsScreenState();
}

class _BillsScreenState extends ConsumerState<BillsScreen> {
  final _searchController = TextEditingController();
  final Set<String> _selectedUuids = {};
  bool _isSharing = false;

  bool get _isSelectionMode => _selectedUuids.isNotEmpty;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _shareSelectedInvoices(List<InvoiceModel> allInvoices) async {
    final selectedInvoices = allInvoices.where((inv) => _selectedUuids.contains(inv.uuid)).toList();
    if (selectedInvoices.isEmpty) return;

    setState(() => _isSharing = true);
    try {
      await PdfInvoiceService.shareMultipleInvoices(selectedInvoices);
      if (mounted) {
        setState(() {
          _selectedUuids.clear();
          _isSharing = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSharing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to share bills: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final invoiceState = ref.watch(invoiceListProvider);
    final notifier = ref.read(invoiceListProvider.notifier);

    return PopScope(
      canPop: !_isSelectionMode,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_isSelectionMode) {
          setState(() => _selectedUuids.clear());
        }
      },
      child: Scaffold(
        appBar: _isSelectionMode
            ? AppBar(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                leading: IconButton(
                  icon: const Icon(Icons.close),
                  tooltip: 'Cancel Selection',
                  onPressed: () => setState(() => _selectedUuids.clear()),
                ),
                title: Text('${_selectedUuids.length} Selected'),
                actions: [
                  IconButton(
                    icon: Icon(
                      _selectedUuids.length == invoiceState.invoices.length
                          ? Icons.deselect
                          : Icons.select_all,
                    ),
                    tooltip: _selectedUuids.length == invoiceState.invoices.length
                        ? 'Deselect All'
                        : 'Select All',
                    onPressed: () {
                      setState(() {
                        if (_selectedUuids.length == invoiceState.invoices.length) {
                          _selectedUuids.clear();
                        } else {
                          _selectedUuids.addAll(invoiceState.invoices.map((e) => e.uuid));
                        }
                      });
                    },
                  ),
                  if (_isSharing)
                    const Center(
                      child: Padding(
                        padding: EdgeInsets.symmetric(horizontal: 16),
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                        ),
                      ),
                    )
                  else
                    IconButton(
                      icon: const Icon(Icons.share),
                      tooltip: 'Share Selected Bills',
                      onPressed: () => _shareSelectedInvoices(invoiceState.invoices),
                    ),
                ],
              )
            : AppBar(
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

  Future<void> _confirmDeleteInvoice(BuildContext context, InvoiceModel inv) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.red, size: 28),
            SizedBox(width: 10),
            Text('Delete Bill?'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Are you sure you want to permanently delete bill ${inv.invoiceNumber}?',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 10),
            Text(
              'Customer: ${inv.customer.name}\nAmount: ${CurrencyFormatter.format(inv.grandTotal)}',
              style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 12),
            const Text(
              'This will remove the bill and update customer outstanding balance. This action cannot be undone.',
              style: TextStyle(fontSize: 12, color: Colors.red),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Yes, Delete Bill'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      try {
        await InvoiceRepository().deleteInvoice(inv.uuid);
        try {
          await ApiClient.instance.deleteInvoice(inv.uuid);
        } catch (_) {}

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Bill ${inv.invoiceNumber} deleted successfully.'),
            backgroundColor: Colors.red.shade700,
          ),
        );
        ref.read(invoiceListProvider.notifier).fetchInvoices();
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to delete bill: $e'),
            backgroundColor: Colors.red.shade700,
          ),
        );
      }
    }
  }

  Widget _buildInvoiceCard(BuildContext context, InvoiceModel inv) {
    final isOwner = ref.watch(authProvider).isOwner;
    final isSelected = _selectedUuids.contains(inv.uuid);

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
      elevation: isSelected ? 3.0 : 1.5,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: isSelected
            ? const BorderSide(color: AppColors.primary, width: 2)
            : BorderSide.none,
      ),
      color: isSelected ? AppColors.primaryContainer.withValues(alpha: 0.15) : null,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onLongPress: () {
          setState(() {
            if (isSelected) {
              _selectedUuids.remove(inv.uuid);
            } else {
              _selectedUuids.add(inv.uuid);
            }
          });
        },
        onTap: () {
          if (_isSelectionMode) {
            setState(() {
              if (isSelected) {
                _selectedUuids.remove(inv.uuid);
              } else {
                _selectedUuids.add(inv.uuid);
              }
            });
          } else {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => InvoiceDetailScreen(invoice: inv),
              ),
            ).then((_) {
              ref.read(invoiceListProvider.notifier).fetchInvoices();
            });
          }
        },
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_isSelectionMode) ...[
                Padding(
                  padding: const EdgeInsets.only(right: 12, top: 4),
                  child: Icon(
                    isSelected ? Icons.check_circle : Icons.radio_button_unchecked,
                    color: isSelected ? AppColors.primary : AppColors.textMuted,
                    size: 24,
                  ),
                ),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Row 1: Invoice No, Payment Badge, & Actions Menu
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Text(
                        inv.invoiceNumber,
                        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: AppColors.primary),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: badgeBg,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          badgeLabel,
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: badgeText),
                        ),
                      ),
                    ],
                  ),
                  PopupMenuButton<String>(
                    icon: const Icon(Icons.more_vert, size: 20, color: AppColors.textSecondary),
                    padding: EdgeInsets.zero,
                    onSelected: (val) {
                      if (val == 'share') {
                        PdfInvoiceService.shareInvoicePdf(inv);
                      } else if (val == 'print') {
                        PdfInvoiceService.printInvoice(inv);
                      } else if (val == 'delete') {
                        _confirmDeleteInvoice(context, inv);
                      }
                    },
                    itemBuilder: (ctx) => [
                      const PopupMenuItem(
                        value: 'share',
                        child: Row(
                          children: [
                            Icon(Icons.share, size: 18),
                            SizedBox(width: 8),
                            Text('Share PDF'),
                          ],
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'print',
                        child: Row(
                          children: [
                            Icon(Icons.print, size: 18),
                            SizedBox(width: 8),
                            Text('Print PDF'),
                          ],
                        ),
                      ),
                      if (isOwner)
                        const PopupMenuItem(
                          value: 'delete',
                          child: Row(
                            children: [
                              Icon(Icons.delete_outline, size: 18, color: Colors.red),
                              SizedBox(width: 8),
                              Text('Delete Bill', style: TextStyle(color: Colors.red)),
                            ],
                          ),
                        ),
                    ],
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
