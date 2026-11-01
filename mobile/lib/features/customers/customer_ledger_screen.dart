import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../../core/utils/currency_formatter.dart';
import '../../core/utils/date_formatter.dart';
import '../../data/models/customer_model.dart';
import '../../data/models/invoice_model.dart';
import '../../data/models/payment_model.dart';
import '../../data/repositories/invoice_repository.dart';
import '../../data/repositories/payment_repository.dart';
import '../invoices/invoice_detail_screen.dart';

class CustomerLedgerScreen extends StatefulWidget {
  final CustomerModel customer;

  const CustomerLedgerScreen({super.key, required this.customer});

  @override
  State<CustomerLedgerScreen> createState() => _CustomerLedgerScreenState();
}

class _CustomerLedgerScreenState extends State<CustomerLedgerScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<InvoiceModel> _invoices = [];
  List<PaymentModel> _payments = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadLedgerData();
  }

  Future<void> _loadLedgerData() async {
    setState(() => _isLoading = true);
    final invList = await InvoiceRepository().getInvoices(customerUuid: widget.customer.uuid);
    final payList = await PaymentRepository().getPaymentsByCustomer(widget.customer.uuid);

    if (mounted) {
      setState(() {
        _invoices = invList;
        _payments = payList;
        _isLoading = false;
      });
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.customer;
    final totalBilled = _invoices.fold(0.0, (acc, inv) => acc + (inv.status != 'cancelled' ? inv.grandTotal : 0.0));
    final totalPaid = _payments.fold(0.0, (acc, p) => acc + p.amount);
    final outstanding = (totalBilled - totalPaid).clamp(0.0, double.infinity);

    return Scaffold(
      appBar: AppBar(
        title: Text(c.name),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // Customer Profile Header Card
                Container(
                  color: AppColors.surfaceLight,
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.business, color: AppColors.primary, size: 28),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  c.name,
                                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                                ),
                                Text(
                                  'Phone: ${c.phone}  •  GSTIN: ${c.gstin.isNotEmpty ? c.gstin : "Unregistered"}',
                                  style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),

                      // 3 Summary Boxes: Billed, Paid, Balance
                      Row(
                        children: [
                          Expanded(
                            child: _buildSummaryBox('Total Billed', CurrencyFormatter.format(totalBilled), AppColors.primary),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _buildSummaryBox('Total Paid', CurrencyFormatter.format(totalPaid), AppColors.paid),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _buildSummaryBox('Balance Due', CurrencyFormatter.format(outstanding), outstanding > 0 ? AppColors.unpaid : AppColors.paid),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                // Tab Bar
                TabBar(
                  controller: _tabController,
                  labelColor: AppColors.primary,
                  indicatorColor: AppColors.primary,
                  unselectedLabelColor: AppColors.textSecondary,
                  tabs: [
                    Tab(text: 'Invoices (${_invoices.length})'),
                    Tab(text: 'Payments (${_payments.length})'),
                  ],
                ),

                // Tab Views
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      // Invoices Tab
                      _invoices.isEmpty
                          ? const Center(child: Text('No invoices issued to this customer'))
                          : ListView.builder(
                              padding: const EdgeInsets.all(16),
                              itemCount: _invoices.length,
                              itemBuilder: (context, index) {
                                final inv = _invoices[index];
                                return Card(
                                  margin: const EdgeInsets.only(bottom: 10),
                                  child: ListTile(
                                    title: Text(inv.invoiceNumber, style: const TextStyle(fontWeight: FontWeight.bold)),
                                    subtitle: Text('${DateFormatter.format(inv.invoiceDate)} • Status: ${inv.paymentStatus.toUpperCase()}'),
                                    trailing: Text(
                                      CurrencyFormatter.format(inv.grandTotal),
                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                    ),
                                    onTap: () {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) => InvoiceDetailScreen(invoice: inv),
                                        ),
                                      ).then((_) => _loadLedgerData());
                                    },
                                  ),
                                );
                              },
                            ),

                      // Payments Tab
                      _payments.isEmpty
                          ? const Center(child: Text('No payments recorded for this customer'))
                          : ListView.builder(
                              padding: const EdgeInsets.all(16),
                              itemCount: _payments.length,
                              itemBuilder: (context, index) {
                                final p = _payments[index];
                                return Card(
                                  margin: const EdgeInsets.only(bottom: 10),
                                  child: ListTile(
                                    leading: const CircleAvatar(
                                      backgroundColor: AppColors.paidContainer,
                                      child: Icon(Icons.check, color: AppColors.paid),
                                    ),
                                    title: Text(
                                      '${CurrencyFormatter.format(p.amount)} (${p.paymentMethod})',
                                      style: const TextStyle(fontWeight: FontWeight.bold),
                                    ),
                                    subtitle: Text(
                                      'Against: ${p.invoiceNumber}  •  ${DateFormatter.format(p.paymentDate)}' +
                                          (p.referenceNumber.isNotEmpty ? '\nRef: ${p.referenceNumber}' : ''),
                                    ),
                                  ),
                                );
                              },
                            ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildSummaryBox(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: color),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
