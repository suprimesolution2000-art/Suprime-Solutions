import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_constants.dart';
import '../../core/utils/currency_formatter.dart';
import '../../data/models/invoice_model.dart';
import '../../data/models/payment_model.dart';
import '../../data/repositories/payment_repository.dart';
import '../../data/repositories/invoice_repository.dart';
import '../../data/repositories/customer_repository.dart';
import '../../services/sync/sync_service.dart';

class RecordPaymentDialog extends StatefulWidget {
  final InvoiceModel invoice;
  final VoidCallback onPaymentSaved;

  const RecordPaymentDialog({
    super.key,
    required this.invoice,
    required this.onPaymentSaved,
  });

  @override
  State<RecordPaymentDialog> createState() => _RecordPaymentDialogState();
}

class _RecordPaymentDialogState extends State<RecordPaymentDialog> {
  late final TextEditingController _amountController;
  final _refController = TextEditingController();
  final _notesController = TextEditingController();
  String _selectedMethod = 'UPI';
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _amountController = TextEditingController(text: widget.invoice.balanceDue.toStringAsFixed(2));
  }

  @override
  void dispose() {
    _amountController.dispose();
    _refController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _submitPayment() async {
    final amount = double.tryParse(_amountController.text) ?? 0.0;
    if (amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Payment amount must be greater than zero')),
      );
      return;
    }
    if (amount > widget.invoice.balanceDue + 0.001) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Payment amount cannot exceed balance due of ${CurrencyFormatter.format(widget.invoice.balanceDue)}'),
        ),
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      final paymentUuid = const Uuid().v4();
      final prefs = await SharedPreferences.getInstance();
      final loggedInName = prefs.getString('user_name') ?? 'Admin';
      final payment = PaymentModel(
        uuid: paymentUuid,
        invoiceId: widget.invoice.uuid,
        invoiceNumber: widget.invoice.invoiceNumber,
        customerId: widget.invoice.customer.uuid,
        customerName: widget.invoice.customer.name,
        amount: amount,
        paymentMethod: _selectedMethod,
        referenceNumber: _refController.text.trim(),
        paymentDate: DateTime.now(),
        notes: _notesController.text.trim(),
        receivedBy: loggedInName,
      );

      // 1. Save payment
      await PaymentRepository().savePayment(payment);

      // 2. Update Invoice
      final newTotalPaid = widget.invoice.totalPaid + amount;
      final newBalanceDue = (widget.invoice.grandTotal - newTotalPaid).clamp(0.0, double.infinity);
      final newStatus = newBalanceDue == 0.0 ? 'paid' : 'partially_paid';
      await InvoiceRepository().updatePaymentStatus(
        widget.invoice.uuid,
        newTotalPaid,
        newBalanceDue,
        newStatus,
      );

      // 3. Update Customer Balance
      await CustomerRepository().updateCustomerBalance(
        widget.invoice.customer.uuid,
        0.0,
        amount,
      );

      // 4. Trigger sync
      SyncService.instance.synchronize();

      if (mounted) {
        widget.onPaymentSaved();
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Payment of ${CurrencyFormatter.format(amount)} recorded successfully'),
            backgroundColor: AppColors.paid,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error saving payment: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 480),
        padding: const EdgeInsets.all(20),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Record Payment',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const Divider(),
              const SizedBox(height: 8),

              // Invoice summary pill
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.surfaceLight,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.border),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(widget.invoice.invoiceNumber, style: const TextStyle(fontWeight: FontWeight.bold)),
                          Text(
                            widget.invoice.customer.name,
                            style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        'Due: ${CurrencyFormatter.format(widget.invoice.balanceDue)}',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: AppColors.unpaid),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Amount
              TextField(
                controller: _amountController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Payment Amount (₹) *',
                  prefixIcon: Icon(Icons.currency_rupee),
                ),
              ),
              const SizedBox(height: 12),

              // Payment Method
              DropdownButtonFormField<String>(
                initialValue: _selectedMethod,
                decoration: const InputDecoration(
                  labelText: 'Payment Mode *',
                  prefixIcon: Icon(Icons.account_balance_wallet_outlined),
                ),
                items: AppConstants.paymentMethods.map((m) {
                  return DropdownMenuItem(value: m, child: Text(m));
                }).toList(),
                onChanged: (val) {
                  if (val != null) setState(() => _selectedMethod = val);
                },
              ),
              const SizedBox(height: 12),

              // Reference / UTR Number
              TextField(
                controller: _refController,
                decoration: const InputDecoration(
                  labelText: 'UTR / Cheque / Transaction No. (Optional)',
                  hintText: 'e.g. UPI Ref: 320148...',
                ),
              ),
              const SizedBox(height: 12),

              // Notes
              TextField(
                controller: _notesController,
                decoration: const InputDecoration(
                  labelText: 'Notes (Optional)',
                  hintText: 'e.g. Received by Mohan',
                ),
              ),
              const SizedBox(height: 20),

              // Submit Button
              ElevatedButton(
                onPressed: _isSaving ? null : _submitPayment,
                child: _isSaving
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Text('Save Payment & Update Balance'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
