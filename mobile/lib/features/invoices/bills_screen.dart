import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants/app_colors.dart';
import '../../core/utils/currency_formatter.dart';
import '../../core/utils/city_helper.dart';
import '../../core/utils/date_formatter.dart';
import '../../providers/invoice_provider.dart';
import '../../providers/customer_provider.dart';
import '../../providers/dashboard_provider.dart';
import '../../providers/auth_provider.dart';
import '../../data/models/invoice_model.dart';
import '../../data/repositories/invoice_repository.dart';
import '../../services/pdf/pdf_invoice_service.dart';
import '../../services/api/api_client.dart';
import '../../services/sync/sync_service.dart';
import '../billing/create_bill_screen.dart';
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

    // City selection is handled via _showCitySearchSheet with keyboard search and frequency sorting

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
                    icon: const Icon(Icons.assessment_outlined),
                    tooltip: 'CA & Audit Reports',
                    onPressed: () => _showCaReportsDialog(context),
                  ),
                  IconButton(
                    icon: const Icon(Icons.date_range),
                    tooltip: 'Filter by Date',
                    onPressed: () => _showDateRangePicker(context, notifier),
                  ),
                  IconButton(
                    icon: const Icon(Icons.refresh),
                    tooltip: 'Sync & Refresh',
                    onPressed: () async {
                      await SyncService.instance.synchronize(forceFullSync: true);
                      await notifier.fetchInvoices();
                    },
                  ),
                ],
              ),
        body: Column(
        children: [
          // 0. Section Switcher: GST Tax Bills vs Temporary Bills
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Container(
              height: 46,
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: Colors.grey.shade200,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: InkWell(
                      borderRadius: BorderRadius.circular(9),
                      onTap: () {
                        if (invoiceState.invoiceType != 'gst') {
                          setState(() => _selectedUuids.clear());
                          notifier.setInvoiceType('gst');
                        }
                      },
                      child: Container(
                        decoration: BoxDecoration(
                          color: invoiceState.invoiceType == 'gst'
                              ? AppColors.primary
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(9),
                          boxShadow: invoiceState.invoiceType == 'gst'
                              ? [
                                  BoxShadow(
                                    color: AppColors.primary.withValues(alpha: 0.25),
                                    blurRadius: 4,
                                    offset: const Offset(0, 2),
                                  ),
                                ]
                              : null,
                        ),
                        alignment: Alignment.center,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.receipt_long,
                              size: 18,
                              color: invoiceState.invoiceType == 'gst'
                                  ? Colors.white
                                  : AppColors.textSecondary,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'GST Tax Bills',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: invoiceState.invoiceType == 'gst'
                                    ? Colors.white
                                    : AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: InkWell(
                      borderRadius: BorderRadius.circular(9),
                      onTap: () {
                        if (invoiceState.invoiceType != 'temporary') {
                          setState(() => _selectedUuids.clear());
                          notifier.setInvoiceType('temporary');
                        }
                      },
                      child: Container(
                        decoration: BoxDecoration(
                          color: invoiceState.invoiceType == 'temporary'
                              ? const Color(0xFF8B5A2B)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(9),
                          boxShadow: invoiceState.invoiceType == 'temporary'
                              ? [
                                  BoxShadow(
                                    color: const Color(0xFF8B5A2B).withValues(alpha: 0.25),
                                    blurRadius: 4,
                                    offset: const Offset(0, 2),
                                  ),
                                ]
                              : null,
                        ),
                        alignment: Alignment.center,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.description_outlined,
                              size: 18,
                              color: invoiceState.invoiceType == 'temporary'
                                  ? Colors.white
                                  : AppColors.textSecondary,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Temporary Bills',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: invoiceState.invoiceType == 'temporary'
                                    ? Colors.white
                                    : AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // 1. One Prominent Universal Search Bar
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 8),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: invoiceState.invoiceType == 'temporary'
                    ? 'Search temporary bill, customer, phone…'
                    : 'Search bill, customer, phone number…',
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

          // City Filter & Direct Sorting Row
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Row(
              children: [
                // 1. Searchable City Filter Button
                Expanded(
                  flex: 5,
                  child: InkWell(
                    onTap: () => _showCitySearchSheet(context, notifier, invoiceState),
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      height: 38,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      decoration: BoxDecoration(
                        color: invoiceState.selectedCity != 'all'
                            ? AppColors.primaryContainer.withValues(alpha: 0.35)
                            : AppColors.surfaceLight,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: invoiceState.selectedCity != 'all' ? AppColors.primary : AppColors.border,
                          width: invoiceState.selectedCity != 'all' ? 1.5 : 1,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.location_on,
                            size: 16,
                            color: invoiceState.selectedCity != 'all' ? AppColors.primary : AppColors.textSecondary,
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              invoiceState.selectedCity != 'all' ? '📍 ${invoiceState.selectedCity}' : '📍 All Cities',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: invoiceState.selectedCity != 'all' ? FontWeight.bold : FontWeight.w600,
                                color: invoiceState.selectedCity != 'all' ? AppColors.primary : AppColors.textPrimary,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Icon(
                            Icons.arrow_drop_down,
                            size: 20,
                            color: invoiceState.selectedCity != 'all' ? AppColors.primary : AppColors.textSecondary,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // 2. Direct Sorting Dropdown (Newest, Oldest, Unpaid First, Paid First, Amount)
                Expanded(
                  flex: 6,
                  child: Container(
                    height: 38,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceLight,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: const [
                          'date_desc',
                          'date_asc',
                          'unpaid_first',
                          'paid_first',
                          'amount_desc',
                          'amount_asc',
                        ].contains(invoiceState.sortBy)
                            ? invoiceState.sortBy
                            : 'date_desc',
                        isExpanded: true,
                        icon: const Icon(Icons.swap_vert, size: 18, color: AppColors.textSecondary),
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                        items: const [
                          DropdownMenuItem(value: 'date_desc', child: Text('Date: Newest First', overflow: TextOverflow.ellipsis)),
                          DropdownMenuItem(value: 'date_asc', child: Text('Date: Oldest First', overflow: TextOverflow.ellipsis)),
                          DropdownMenuItem(value: 'unpaid_first', child: Text('Unpaid First', overflow: TextOverflow.ellipsis)),
                          DropdownMenuItem(value: 'paid_first', child: Text('Paid First', overflow: TextOverflow.ellipsis)),
                          DropdownMenuItem(value: 'amount_desc', child: Text('Amount: High to Low', overflow: TextOverflow.ellipsis)),
                          DropdownMenuItem(value: 'amount_asc', child: Text('Amount: Low to High', overflow: TextOverflow.ellipsis)),
                        ],
                        onChanged: (val) {
                          if (val != null) {
                            notifier.setSortBy(val);
                          }
                        },
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 12),

          // Offline bills banner if pendingCount > 0
          ListenableBuilder(
            listenable: SyncService.instance,
            builder: (context, _) {
              final sync = SyncService.instance;
              if (sync.pendingCount <= 0) return const SizedBox.shrink();
              return Container(
                margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.amber.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.amber.shade300),
                ),
                child: Row(
                  children: [
                    Icon(
                      sync.isSyncing ? Icons.sync : Icons.cloud_off,
                      color: Colors.amber.shade900,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        sync.isSyncing
                            ? 'Syncing ${sync.pendingCount} local bills with cloud...'
                            : '${sync.pendingCount} local ${sync.pendingCount == 1 ? "bill is" : "bills are"} waiting for internet to upload',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Colors.amber.shade900,
                        ),
                      ),
                    ),
                    if (!sync.isSyncing)
                      InkWell(
                        onTap: () async {
                          await sync.synchronize(forceFullSync: true);
                          ref.read(invoiceListProvider.notifier).fetchInvoices();
                          ref.read(customerListProvider.notifier).fetchCustomers();
                          ref.read(dashboardProvider.notifier).refreshSummary();
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          child: Text(
                            'SYNC NOW',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: Colors.amber.shade900,
                              decoration: TextDecoration.underline,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              );
            },
          ),

          // 3. Invoices List
          Expanded(
            child: invoiceState.isLoading
                ? const Center(child: CircularProgressIndicator())
                : invoiceState.invoices.isEmpty
                    ? RefreshIndicator(
                        onRefresh: () async {
                          await SyncService.instance.synchronize(forceFullSync: true);
                          await notifier.fetchInvoices();
                        },
                        child: SingleChildScrollView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
                          child: Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  invoiceState.invoiceType == 'temporary'
                                      ? Icons.description_outlined
                                      : Icons.receipt_long_outlined,
                                  size: 64,
                                  color: AppColors.textMuted,
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  _searchController.text.isNotEmpty
                                      ? 'No ${invoiceState.invoiceType == "temporary" ? "temporary bills" : "GST bills"} found matching "${_searchController.text}"'
                                      : 'No ${invoiceState.invoiceType == "temporary" ? "temporary bills" : "GST bills"} found in this filter',
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
                          await SyncService.instance.synchronize(forceFullSync: true);
                          await notifier.fetchInvoices();
                        },
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
        ref.read(customerListProvider.notifier).fetchCustomers();
        ref.read(dashboardProvider.notifier).refreshSummary();
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
        ref.read(customerListProvider.notifier).fetchCustomers();
        ref.read(dashboardProvider.notifier).refreshSummary();
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
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          inv.invoiceType == 'temporary'
                              ? 'Temp Bill #${inv.invoiceNumber.isNotEmpty ? inv.invoiceNumber : inv.sequenceNumber}'
                              : inv.invoiceNumber,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: inv.invoiceType == 'temporary' ? const Color(0xFF8B5A2B) : AppColors.primary,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                          decoration: BoxDecoration(
                            color: inv.invoiceType == 'temporary' ? const Color(0xFFFAF0E6) : Colors.blue.shade50,
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(
                              color: inv.invoiceType == 'temporary' ? const Color(0xFFD8BD91) : Colors.blue.shade200,
                            ),
                          ),
                          child: Text(
                            inv.invoiceType == 'temporary' ? 'TEMP' : 'GST',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: inv.invoiceType == 'temporary' ? const Color(0xFF8B5A2B) : Colors.blue.shade800,
                            ),
                          ),
                        ),
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
                        if (inv.syncStatus != 'synced')
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.amber.shade100,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: Colors.amber.shade600, width: 0.8),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.cloud_off, size: 10, color: Colors.amber.shade900),
                                const SizedBox(width: 3),
                                Text(
                                  'OFFLINE',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.amber.shade900,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                  SizedBox(
                    width: 44,
                    height: 44,
                    child: PopupMenuButton<String>(
                      icon: const Icon(Icons.more_vert, size: 20, color: AppColors.textSecondary),
                      padding: EdgeInsets.zero,
                    onSelected: (val) {
                      if (val == 'share') {
                        PdfInvoiceService.shareInvoicePdf(inv);
                      } else if (val == 'print') {
                        PdfInvoiceService.printInvoice(inv);
                      } else if (val == 'edit') {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => CreateBillScreen(invoiceToEdit: inv),
                          ),
                        ).then((_) {
                          ref.read(invoiceListProvider.notifier).fetchInvoices();
        ref.read(customerListProvider.notifier).fetchCustomers();
        ref.read(dashboardProvider.notifier).refreshSummary();
                        });
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
                      if (inv.status != 'cancelled')
                        const PopupMenuItem(
                          value: 'edit',
                          child: Row(
                            children: [
                              Icon(Icons.edit_outlined, size: 18, color: AppColors.primary),
                              SizedBox(width: 8),
                              Text('Edit Bill'),
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
                ),
              ],
            ),
              const SizedBox(height: 6),

              // Row 2: Customer Name, City Tag & Date
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        Flexible(
                          child: Text(
                            inv.customer.name,
                            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: Colors.grey.shade300, width: 0.8),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.location_on_outlined, size: 10, color: AppColors.textMuted),
                              const SizedBox(width: 2),
                              Text(
                                inv.customer.city.trim().isNotEmpty ? inv.customer.city.trim() : 'Bilaspur',
                                style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: AppColors.textSecondary),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
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
                  Expanded(
                    child: Text(
                      '${inv.items.length} ${inv.items.length == 1 ? 'item' : 'items'} • ${inv.customer.phone}',
                      style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      CurrencyFormatter.format(inv.grandTotal),
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                    ),
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

  Future<void> _showCitySearchSheet(
    BuildContext context,
    InvoiceListNotifier notifier,
    InvoiceListState invoiceState,
  ) async {
    final counts = await InvoiceRepository().getCityBillCounts();
    final totalBills = counts.values.fold<int>(0, (sum, c) => sum + c);

    // Active cities sorted by frequency (number of bills) descending
    final activeCities = counts.keys.toList()
      ..sort((a, b) {
        final countCmp = (counts[b] ?? 0).compareTo(counts[a] ?? 0);
        if (countCmp != 0) return countCmp;
        return a.compareTo(b);
      });

    // Zero-bill commercial cities sorted alphabetically
    final zeroBillCities = <String>[];
    for (final c in CityHelper.commercialCities) {
      if (!counts.containsKey(c)) {
        zeroBillCities.add(c);
      }
    }
    zeroBillCities.sort();

    final allDisplayCities = [...activeCities, ...zeroBillCities];

    if (!context.mounted) return;

    final searchController = TextEditingController();

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (sheetContext, setModalState) {
            final query = searchController.text.trim().toLowerCase();
            final filteredCities = allDisplayCities.where((c) {
              if (query.isEmpty) return true;
              return c.toLowerCase().contains(query);
            }).toList();

            final showAllCitiesOption = query.isEmpty || 'all cities'.contains(query) || 'all'.contains(query);

            return Padding(
              padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
              child: Container(
                height: MediaQuery.of(ctx).size.height * 0.72,
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                ),
                child: Column(
                  children: [
                    // Drag Handle
                    Container(
                      margin: const EdgeInsets.only(top: 10, bottom: 6),
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),

                    // Header Row
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                      child: Row(
                        children: [
                          const Icon(Icons.location_city, color: AppColors.primary, size: 22),
                          const SizedBox(width: 8),
                          const Expanded(
                            child: Text(
                              'Select City',
                              style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.bold,
                                color: AppColors.textPrimary,
                              ),
                            ),
                          ),
                          if (invoiceState.selectedCity != 'all')
                            TextButton.icon(
                              icon: const Icon(Icons.refresh, size: 16),
                              label: const Text('Reset', style: TextStyle(fontSize: 13)),
                              style: TextButton.styleFrom(
                                foregroundColor: AppColors.error,
                                padding: const EdgeInsets.symmetric(horizontal: 8),
                              ),
                              onPressed: () {
                                notifier.setSelectedCity('all');
                                Navigator.pop(ctx);
                              },
                            ),
                          IconButton(
                            icon: const Icon(Icons.close),
                            tooltip: 'Close',
                            onPressed: () => Navigator.pop(ctx),
                          ),
                        ],
                      ),
                    ),

                    // Search Box with Automatic Keyboard Focus
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 2, 16, 8),
                      child: TextField(
                        controller: searchController,
                        autofocus: true,
                        decoration: InputDecoration(
                          hintText: 'Search city name (e.g. Raipur, Korba)...',
                          hintStyle: TextStyle(fontSize: 13, color: Colors.grey.shade500),
                          prefixIcon: const Icon(Icons.search, color: AppColors.primary, size: 20),
                          suffixIcon: searchController.text.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.clear, size: 18),
                                  onPressed: () {
                                    searchController.clear();
                                    setModalState(() {});
                                  },
                                )
                              : null,
                          contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide(color: Colors.grey.shade300),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide(color: Colors.grey.shade300),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: const BorderSide(color: AppColors.primary, width: 2),
                          ),
                          filled: true,
                          fillColor: AppColors.surfaceLight,
                        ),
                        onChanged: (_) => setModalState(() {}),
                      ),
                    ),

                    const Divider(height: 1),

                    // City List ordered by bill frequency
                    Expanded(
                      child: ListView.separated(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        itemCount: (showAllCitiesOption ? 1 : 0) + filteredCities.length,
                        separatorBuilder: (c, i) => const Divider(height: 1, indent: 56),
                        itemBuilder: (c, index) {
                          if (showAllCitiesOption && index == 0) {
                            final isSelected = invoiceState.selectedCity == 'all';
                            return ListTile(
                              dense: true,
                              leading: Container(
                                padding: const EdgeInsets.all(7),
                                decoration: BoxDecoration(
                                  color: isSelected ? AppColors.primary : Colors.grey.shade100,
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  Icons.public,
                                  size: 18,
                                  color: isSelected ? Colors.white : AppColors.primary,
                                ),
                              ),
                              title: const Text(
                                'All Cities',
                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                              ),
                              subtitle: Text(
                                'Show bills from all locations ($totalBills total bills)',
                                style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                              ),
                              trailing: isSelected
                                  ? const Icon(Icons.check_circle, color: AppColors.primary, size: 22)
                                  : Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: Colors.grey.shade100,
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Text(
                                        '$totalBills bills',
                                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.grey.shade700),
                                      ),
                                    ),
                              onTap: () {
                                notifier.setSelectedCity('all');
                                Navigator.pop(ctx);
                              },
                            );
                          }

                          final cityIndex = showAllCitiesOption ? index - 1 : index;
                          final cityName = filteredCities[cityIndex];
                          final count = counts[cityName] ?? 0;
                          final isSelected = invoiceState.selectedCity.trim().toLowerCase() == cityName.trim().toLowerCase();

                          return ListTile(
                            dense: true,
                            leading: Container(
                              padding: const EdgeInsets.all(7),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? AppColors.primary
                                    : (count > 0 ? AppColors.primaryContainer.withValues(alpha: 0.35) : Colors.grey.shade100),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                Icons.location_on,
                                size: 18,
                                color: isSelected
                                    ? Colors.white
                                    : (count > 0 ? AppColors.primary : Colors.grey.shade400),
                              ),
                            ),
                            title: Text(
                              cityName,
                              style: TextStyle(
                                fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                                fontSize: 14,
                                color: isSelected ? AppColors.primary : AppColors.textPrimary,
                              ),
                            ),
                            subtitle: count > 0
                                ? Text(
                                    '$count bill${count == 1 ? '' : 's'} recorded',
                                    style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                                  )
                                : null,
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (count > 0)
                                  Container(
                                    margin: const EdgeInsets.only(right: 6),
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: AppColors.primary.withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Text(
                                      '$count bills',
                                      style: const TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                        color: AppColors.primary,
                                      ),
                                    ),
                                  ),
                                if (isSelected)
                                  const Icon(Icons.check_circle, color: AppColors.primary, size: 22),
                              ],
                            ),
                            onTap: () {
                              notifier.setSelectedCity(cityName);
                              Navigator.pop(ctx);
                            },
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
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

  void _showCaReportsDialog(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        DateTime fromDate = DateTime(DateTime.now().year, DateTime.now().month, 1);
        DateTime toDate = DateTime.now();
        bool isGenerating = false;
        String statusText = '';

        return StatefulBuilder(
          builder: (context, setModalState) {
            return SingleChildScrollView(
              child: Padding(
                padding: EdgeInsets.only(
                  left: 20,
                  right: 20,
                  top: 20,
                  bottom: MediaQuery.of(context).viewInsets.bottom + 24,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                  // Title Header
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: AppColors.primaryContainer,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.assessment, color: AppColors.primary, size: 24),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'CA & Audit GST Export',
                              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                            ),
                            Text(
                              'Official GST Tax Invoices only (No temporary bills)',
                              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                  const Divider(height: 24),

                  // Quick Date Preset Chips
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        ActionChip(
                          label: const Text('This Month'),
                          onPressed: () {
                            final now = DateTime.now();
                            setModalState(() {
                              fromDate = DateTime(now.year, now.month, 1);
                              toDate = now;
                            });
                          },
                        ),
                        const SizedBox(width: 8),
                        ActionChip(
                          label: const Text('Last Month'),
                          onPressed: () {
                            final now = DateTime.now();
                            final lastMonth = DateTime(now.year, now.month - 1, 1);
                            final lastDay = DateTime(now.year, now.month, 0);
                            setModalState(() {
                              fromDate = lastMonth;
                              toDate = lastDay;
                            });
                          },
                        ),
                        const SizedBox(width: 8),
                        ActionChip(
                          label: const Text('This Financial Year'),
                          onPressed: () {
                            final now = DateTime.now();
                            final fyStart = now.month >= 4 ? DateTime(now.year, 4, 1) : DateTime(now.year - 1, 4, 1);
                            setModalState(() {
                              fromDate = fyStart;
                              toDate = now;
                            });
                          },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Date Range Picker Row
                  Row(
                    children: [
                      Expanded(
                        child: InkWell(
                          borderRadius: BorderRadius.circular(10),
                          onTap: () async {
                            final picked = await showDatePicker(
                              context: context,
                              initialDate: fromDate,
                              firstDate: DateTime(2020),
                              lastDate: DateTime(2035),
                            );
                            if (picked != null) {
                              setModalState(() => fromDate = picked);
                            }
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            decoration: BoxDecoration(
                              border: Border.all(color: Colors.grey.shade300),
                              borderRadius: BorderRadius.circular(10),
                              color: Colors.grey.shade50,
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('From Date', style: TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                                const SizedBox(height: 2),
                                Row(
                                  children: [
                                    const Icon(Icons.calendar_today, size: 14, color: AppColors.primary),
                                    const SizedBox(width: 6),
                                    Text(
                                      DateFormatter.format(fromDate),
                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 8),
                        child: Icon(Icons.arrow_forward, size: 16, color: Colors.grey),
                      ),
                      Expanded(
                        child: InkWell(
                          borderRadius: BorderRadius.circular(10),
                          onTap: () async {
                            final picked = await showDatePicker(
                              context: context,
                              initialDate: toDate,
                              firstDate: DateTime(2020),
                              lastDate: DateTime(2035),
                            );
                            if (picked != null) {
                              setModalState(() => toDate = picked);
                            }
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            decoration: BoxDecoration(
                              border: Border.all(color: Colors.grey.shade300),
                              borderRadius: BorderRadius.circular(10),
                              color: Colors.grey.shade50,
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('To Date', style: TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                                const SizedBox(height: 2),
                                Row(
                                  children: [
                                    const Icon(Icons.calendar_today, size: 14, color: AppColors.primary),
                                    const SizedBox(width: 6),
                                    Text(
                                      DateFormatter.format(toDate),
                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  if (statusText.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(
                        statusText,
                        style: const TextStyle(color: Colors.red, fontSize: 12),
                        textAlign: TextAlign.center,
                      ),
                    ),

                  if (isGenerating)
                    const Center(
                      child: Padding(
                        padding: EdgeInsets.symmetric(vertical: 20),
                        child: Column(
                          children: [
                            CircularProgressIndicator(),
                            SizedBox(height: 12),
                            Text('Generating CA PDF Document...', style: TextStyle(fontSize: 13)),
                          ],
                        ),
                      ),
                    )
                  else ...[
                    // Option 1: Combined Full Bills PDF
                    Card(
                      elevation: 1,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(color: Colors.blue.shade200),
                      ),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () async {
                          setModalState(() {
                            isGenerating = true;
                            statusText = '';
                          });
                          try {
                            final invoices = await InvoiceRepository().getGstInvoicesForDateRange(fromDate, toDate);
                            if (invoices.isEmpty) {
                              setModalState(() {
                                isGenerating = false;
                                statusText = 'No GST invoices found in selected date range.';
                              });
                              return;
                            }
                            await PdfInvoiceService.shareCombinedBillsPdf(invoices, fromDate, toDate);
                            if (context.mounted) Navigator.pop(context);
                          } catch (e) {
                            setModalState(() {
                              isGenerating = false;
                              statusText = 'Error generating combined bills: $e';
                            });
                          }
                        },
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: Colors.blue.shade50,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Icon(Icons.picture_as_pdf, color: AppColors.primary, size: 28),
                              ),
                              const SizedBox(width: 14),
                              const Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Combined Bills (Single PDF)',
                                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                    ),
                                    SizedBox(height: 2),
                                    Text(
                                      '1 multi-page PDF of all full GST bills sequentially date-wise',
                                      style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
                                    ),
                                  ],
                                ),
                              ),
                              const Icon(Icons.chevron_right, color: Colors.grey),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),

                    // Option 2: Excel-Style GST Statement PDF
                    Card(
                      elevation: 1,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(color: Colors.green.shade200),
                      ),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () async {
                          setModalState(() {
                            isGenerating = true;
                            statusText = '';
                          });
                          try {
                            final invoices = await InvoiceRepository().getGstInvoicesForDateRange(fromDate, toDate);
                            if (invoices.isEmpty) {
                              setModalState(() {
                                isGenerating = false;
                                statusText = 'No GST invoices found in selected date range.';
                              });
                              return;
                            }
                            await PdfInvoiceService.shareGstSalesRegisterPdf(invoices, fromDate, toDate);
                            if (context.mounted) Navigator.pop(context);
                          } catch (e) {
                            setModalState(() {
                              isGenerating = false;
                              statusText = 'Error generating GST statement: $e';
                            });
                          }
                        },
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: Colors.green.shade50,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Icon(Icons.table_chart, color: Color(0xFF15803D), size: 28),
                              ),
                              const SizedBox(width: 14),
                              const Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Excel-Style Sales Statement',
                                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                    ),
                                    SizedBox(height: 2),
                                    Text(
                                      'Tabular statement with Taxable, CGST, SGST, IGST & Totals',
                                      style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
                                    ),
                                  ],
                                ),
                              ),
                              const Icon(Icons.chevron_right, color: Colors.grey),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      );
      },
    );
  }
}
