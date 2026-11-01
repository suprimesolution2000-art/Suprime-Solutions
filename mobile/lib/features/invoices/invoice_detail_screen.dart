import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:printing/printing.dart';
import '../../core/constants/app_colors.dart';
import '../../core/utils/currency_formatter.dart';
import '../../data/models/invoice_model.dart';
import '../../data/repositories/invoice_repository.dart';
import '../../services/pdf/pdf_invoice_service.dart';
import '../../services/api/api_client.dart';
import '../payments/record_payment_dialog.dart';

class InvoiceDetailScreen extends ConsumerStatefulWidget {
  final InvoiceModel invoice;

  const InvoiceDetailScreen({super.key, required this.invoice});

  @override
  ConsumerState<InvoiceDetailScreen> createState() => _InvoiceDetailScreenState();
}

class _InvoiceDetailScreenState extends ConsumerState<InvoiceDetailScreen> {
  late InvoiceModel _currentInvoice;

  @override
  void initState() {
    super.initState();
    _currentInvoice = widget.invoice;
  }

  Future<void> _refreshInvoice() async {
    final updated = await InvoiceRepository().getInvoiceByUuid(_currentInvoice.uuid);
    if (updated != null && mounted) {
      setState(() {
        _currentInvoice = updated;
      });
    }
  }

  Future<void> _confirmDeleteInvoice(BuildContext context) async {
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
              'Are you sure you want to permanently delete bill ${_currentInvoice.invoiceNumber}?',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 10),
            Text(
              'Customer: ${_currentInvoice.customer.name}\nAmount: ${CurrencyFormatter.format(_currentInvoice.grandTotal)}',
              style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 12),
            const Text(
              'This will remove the bill from the system and update the customer balance. This action cannot be undone.',
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
        await InvoiceRepository().deleteInvoice(_currentInvoice.uuid);
        try {
          await ApiClient.instance.deleteInvoice(_currentInvoice.uuid);
        } catch (_) {
          // If offline, local deletion already completed
        }

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Bill ${_currentInvoice.invoiceNumber} deleted successfully.'),
              backgroundColor: Colors.red.shade700,
            ),
          );
          Navigator.pop(context, true);
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to delete bill: $e'),
              backgroundColor: Colors.red.shade700,
            ),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_currentInvoice.invoiceNumber),
        actions: [
          IconButton(
            icon: const Icon(Icons.share),
            tooltip: 'Share on WhatsApp',
            onPressed: () => PdfInvoiceService.shareInvoicePdf(_currentInvoice),
          ),
          IconButton(
            icon: const Icon(Icons.print),
            tooltip: 'Print Invoice',
            onPressed: () => PdfInvoiceService.printInvoice(_currentInvoice),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline, color: Colors.white),
            tooltip: 'Delete Bill',
            onPressed: () => _confirmDeleteInvoice(context),
          ),
        ],
      ),
      body: Column(
        children: [
          // Top Payment Status Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            color: _currentInvoice.paymentStatus == 'paid'
                ? AppColors.paidContainer
                : _currentInvoice.paymentStatus == 'partially_paid'
                    ? AppColors.partialContainer
                    : AppColors.unpaidContainer,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Grand Total: ${CurrencyFormatter.format(_currentInvoice.grandTotal)}',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                    ),
                    Text(
                      _currentInvoice.balanceDue > 0
                          ? 'Balance Due: ${CurrencyFormatter.format(_currentInvoice.balanceDue)}'
                          : 'Fully Paid',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: _currentInvoice.balanceDue > 0 ? AppColors.unpaid : AppColors.paid,
                      ),
                    ),
                  ],
                ),
                if (_currentInvoice.balanceDue > 0 && _currentInvoice.status != 'cancelled')
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      minimumSize: const Size(130, 38),
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                    ),
                    icon: const Icon(Icons.payment, size: 18),
                    label: const Text('Add Payment', style: TextStyle(fontSize: 13)),
                    onPressed: () {
                      showDialog(
                        context: context,
                        builder: (_) => RecordPaymentDialog(
                          invoice: _currentInvoice,
                          onPaymentSaved: _refreshInvoice,
                        ),
                      );
                    },
                  ),
              ],
            ),
          ),

          // Interactive PDF View of the Original Invoice Overlay
          Expanded(
            child: PdfPreview(
              build: (format) => PdfInvoiceService.generateInvoicePdfBytes(_currentInvoice),
              pdfFileName: PdfInvoiceService.getPdfFileName(_currentInvoice),
              canChangeOrientation: false,
              canChangePageFormat: false,
              canDebug: false,
              useActions: false,
            ),
          ),

          // Bottom Action Bar with Large Buttons
          Container(
            padding: const EdgeInsets.all(12),
            decoration: const BoxDecoration(
              color: Colors.white,
              border: Border(top: BorderSide(color: AppColors.divider)),
            ),
            child: Row(
              children: [
                // 1. Share on WhatsApp Button (Large Green)
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF25D366),
                      foregroundColor: Colors.white,
                      minimumSize: const Size(double.infinity, 52),
                    ),
                    icon: const Icon(Icons.share, size: 22),
                    label: const Text(
                      'WhatsApp Share',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    onPressed: () => PdfInvoiceService.shareInvoicePdf(_currentInvoice),
                  ),
                ),
                const SizedBox(width: 12),

                // 2. Print Button (Large Primary)
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      minimumSize: const Size(double.infinity, 52),
                    ),
                    icon: const Icon(Icons.print, size: 22),
                    label: const Text(
                      'Print Bill',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    onPressed: () => PdfInvoiceService.printInvoice(_currentInvoice),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
