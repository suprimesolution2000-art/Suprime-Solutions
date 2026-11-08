import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:printing/printing.dart';
import '../../core/constants/app_colors.dart';
import '../../core/utils/currency_formatter.dart';
import '../../data/models/invoice_model.dart';
import '../../data/repositories/invoice_repository.dart';
import '../../services/pdf/pdf_invoice_service.dart';
import '../../services/api/api_client.dart';
import '../../providers/auth_provider.dart';
import '../payments/record_payment_dialog.dart';
import '../billing/create_bill_screen.dart';

class InvoiceDetailScreen extends ConsumerStatefulWidget {
  final InvoiceModel invoice;

  const InvoiceDetailScreen({super.key, required this.invoice});

  @override
  ConsumerState<InvoiceDetailScreen> createState() => _InvoiceDetailScreenState();
}

class _InvoiceDetailScreenState extends ConsumerState<InvoiceDetailScreen> {
  late InvoiceModel _currentInvoice;
  late String _previewType;

  @override
  void initState() {
    super.initState();
    _currentInvoice = widget.invoice;
    _previewType = widget.invoice.invoiceType;
  }

  Future<void> _refreshInvoice() async {
    final updated = await InvoiceRepository().getInvoiceByUuid(_currentInvoice.uuid);
    if (updated != null && mounted) {
      setState(() {
        _currentInvoice = updated;
        _previewType = updated.invoiceType;
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

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Bill ${_currentInvoice.invoiceNumber} deleted successfully.'),
            backgroundColor: Colors.red.shade700,
          ),
        );
        Navigator.pop(context, true);
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

  @override
  Widget build(BuildContext context) {
    final isOwner = ref.watch(authProvider).isOwner;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                _currentInvoice.invoiceType == 'temporary' ? 'Temporary Bill' : _currentInvoice.invoiceNumber,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: _previewType == 'temporary' ? const Color(0xFF8B5A2B) : AppColors.primary,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                _previewType == 'temporary' ? 'TEMP' : 'GST',
                style: const TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.bold),
              ),
            ),
            if (_currentInvoice.syncStatus != 'synced') ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.amber.shade700,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.cloud_off, size: 10, color: Colors.white),
                    SizedBox(width: 3),
                    Text(
                      'OFFLINE',
                      style: TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(_previewType == 'temporary' ? Icons.receipt_long : Icons.history_edu),
            tooltip: _previewType == 'temporary' ? 'Switch to GST Bill View' : 'Switch to Temporary Bill View',
            onPressed: () {
              setState(() {
                _previewType = _previewType == 'temporary' ? 'gst' : 'temporary';
              });
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(_previewType == 'temporary'
                      ? 'Displaying Temporary Bill (Wood Theme)'
                      : 'Displaying GST Tax Invoice'),
                  duration: const Duration(seconds: 1),
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.share),
            tooltip: 'Share on WhatsApp',
            onPressed: () => PdfInvoiceService.shareInvoicePdf(_currentInvoice.copyWith(invoiceType: _previewType)),
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, color: Colors.white),
            tooltip: 'More Actions',
            onSelected: (val) async {
              if (val == 'print') {
                PdfInvoiceService.printInvoice(_currentInvoice.copyWith(invoiceType: _previewType));
              } else if (val == 'edit') {
                final result = await Navigator.push<bool>(
                  context,
                  MaterialPageRoute(
                    builder: (_) => CreateBillScreen(invoiceToEdit: _currentInvoice),
                  ),
                );
                if (result == true) {
                  await _refreshInvoice();
                }
              } else if (val == 'delete') {
                _confirmDeleteInvoice(context);
              }
            },
            itemBuilder: (ctx) => [
              const PopupMenuItem(
                value: 'print',
                child: Row(
                  children: [
                    Icon(Icons.print, size: 20, color: AppColors.primary),
                    SizedBox(width: 8),
                    Text('Print Bill'),
                  ],
                ),
              ),
              if (_currentInvoice.status != 'cancelled')
                const PopupMenuItem(
                  value: 'edit',
                  child: Row(
                    children: [
                      Icon(Icons.edit_outlined, size: 20, color: AppColors.primary),
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
                      Icon(Icons.delete_outline, size: 20, color: Colors.red),
                      SizedBox(width: 8),
                      Text('Delete Bill', style: TextStyle(color: Colors.red)),
                    ],
                  ),
                ),
            ],
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
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Grand Total: ${CurrencyFormatter.format(_currentInvoice.grandTotal)}',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
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
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                if (_currentInvoice.balanceDue > 0 && _currentInvoice.status != 'cancelled') ...[
                  const SizedBox(width: 8),
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
              ],
            ),
          ),

          // Interactive PDF View of the Original Invoice Overlay
          Expanded(
            child: PdfPreview(
              build: (format) => PdfInvoiceService.generateInvoicePdfBytes(_currentInvoice, overrideType: _previewType),
              pdfFileName: PdfInvoiceService.getPdfFileName(_currentInvoice),
              canChangeOrientation: false,
              canChangePageFormat: false,
              canDebug: false,
              useActions: false,
            ),
          ),

          // Bottom Action Bar with Large Buttons wrapped in SafeArea
          SafeArea(
            top: false,
            child: Container(
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
                      label: const FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          'WhatsApp Share',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                      ),
                      onPressed: () => PdfInvoiceService.shareInvoicePdf(_currentInvoice.copyWith(invoiceType: _previewType)),
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
                      label: const FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          'Print Bill',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                      ),
                      onPressed: () => PdfInvoiceService.printInvoice(_currentInvoice.copyWith(invoiceType: _previewType)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
