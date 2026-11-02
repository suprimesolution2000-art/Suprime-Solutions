import 'dart:io';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../../data/models/invoice_model.dart';
import '../../core/utils/date_formatter.dart';

class PdfInvoiceService {
  // Calibrated exact dimensions matching the vector invoice template
  static const double masterWidth = 492.0;
  static const double masterHeight = 602.0;

  /// Generate high-precision PDF document bytes matching the authentic paper invoice
  static Future<Uint8List> generateInvoicePdfBytes(InvoiceModel invoice) async {
    final pdf = pw.Document();

    // Load master 300 DPI high-definition scanned template image from assets
    final templateImageBytes = await rootBundle.load('assets/invoice-template/template_hq_300dpi.jpg');
    final templateImage = pw.MemoryImage(templateImageBytes.buffer.asUint8List());

    final fontBold = await PdfGoogleFonts.robotoBold();

    // Prepare address lines
    String addr1 = invoice.customer.address.trim();
    String addr2 = '';
    if (addr1.length > 42) {
      final commaIdx = addr1.lastIndexOf(',', 45);
      if (commaIdx != -1) {
        addr2 = addr1.substring(commaIdx + 1).trim();
        addr1 = addr1.substring(0, commaIdx + 1).trim();
      } else {
        final spaceIdx = addr1.lastIndexOf(' ', 45);
        if (spaceIdx != -1) {
          addr2 = addr1.substring(spaceIdx + 1).trim();
          addr1 = addr1.substring(0, spaceIdx).trim();
        }
      }
    }

    final double effectiveGstRate = invoice.items.isNotEmpty ? invoice.items[0].gstRate : 18.0;

    final wordsLen = invoice.amountInWords.length;
    final double wordsFontSize = wordsLen > 75
        ? 7.2
        : (wordsLen > 60
            ? 7.8
            : (wordsLen > 48
                ? 8.5
                : (wordsLen > 36 ? 9.0 : 9.5)));

    pdf.addPage(
      pw.Page(
        pageFormat: const PdfPageFormat(masterWidth, masterHeight, marginAll: 0),
        build: (pw.Context context) {
          return pw.Stack(
            children: [
              // 1. Full-bleed background template (original scanned invoice with authentic logo, bank details & signature)
              pw.Positioned(
                left: 0,
                top: 0,
                right: 0,
                bottom: 0,
                child: pw.Image(templateImage, fit: pw.BoxFit.fill),
              ),

              // 2. Invoice Number (In designated box below 'Invoice No.' - Large & Bold)
              pw.Positioned(
                left: 382.0,
                top: 48.0,
                child: pw.SizedBox(
                  width: 93.0,
                  child: pw.Align(
                    alignment: pw.Alignment.centerLeft,
                    child: pw.Text(
                      invoice.invoiceNumber,
                      style: pw.TextStyle(font: fontBold, fontSize: 13.0, color: PdfColors.black),
                    ),
                  ),
                ),
              ),

              // 3. Invoice Date (On dotted underline next to 'Date:' - Large & Bold)
              pw.Positioned(
                left: 408.0,
                top: 69.5,
                child: pw.Text(
                  DateFormatter.format(invoice.invoiceDate),
                  style: pw.TextStyle(font: fontBold, fontSize: 11.0, color: PdfColors.black),
                ),
              ),

              // 4. Customer Name (Resting on line y=122 under M/s - Large & Bold)
              pw.Positioned(
                left: 64.0,
                top: 111.0,
                child: pw.SizedBox(
                  width: 260.0,
                  child: pw.Text(
                    invoice.customer.name.toUpperCase(),
                    maxLines: 1,
                    overflow: pw.TextOverflow.clip,
                    style: pw.TextStyle(font: fontBold, fontSize: 11.5, color: PdfColors.black),
                  ),
                ),
              ),

              // 5. Customer Address (Lines 1 & 2 resting on lines y=139 and y=154)
              pw.Positioned(
                left: 42.0,
                top: 129.0,
                child: pw.SizedBox(
                  width: 284.0,
                  child: pw.Text(
                    addr1,
                    maxLines: 1,
                    overflow: pw.TextOverflow.clip,
                    style: pw.TextStyle(font: fontBold, fontSize: 10.0, color: PdfColors.black),
                  ),
                ),
              ),
              if (addr2.isNotEmpty)
                pw.Positioned(
                  left: 42.0,
                  top: 144.0,
                  child: pw.SizedBox(
                    width: 284.0,
                    child: pw.Text(
                      addr2,
                      maxLines: 1,
                      overflow: pw.TextOverflow.clip,
                      style: pw.TextStyle(font: fontBold, fontSize: 10.0, color: PdfColors.black),
                    ),
                  ),
                ),

              // 6. State & State Code (Resting on line y=171)
              pw.Positioned(
                left: 70.0,
                top: 160.5,
                child: pw.Text(
                  invoice.customer.state,
                  style: pw.TextStyle(font: fontBold, fontSize: 10.5, color: PdfColors.black),
                ),
              ),
              pw.Positioned(
                left: 255.0,
                top: 160.5,
                child: pw.Text(
                  invoice.customer.stateCode,
                  style: pw.TextStyle(font: fontBold, fontSize: 10.5, color: PdfColors.black),
                ),
              ),

              // 7. GSTIN No. (Resting on line y=189 starting after 'GSTING No.' label)
              pw.Positioned(
                left: 104.0,
                top: 178.0,
                child: pw.Text(
                  invoice.customer.gstin,
                  style: pw.TextStyle(font: fontBold, fontSize: 11.5, color: PdfColors.black),
                ),
              ),

              // 8. P.O. No. & Date (Row 1: y=113, Row 2 Date: y=136)
              if (invoice.poNumber.isNotEmpty)
                pw.Positioned(
                  left: 378.0,
                  top: 113.0,
                  child: pw.SizedBox(
                    width: 95.0,
                    child: pw.Text(
                      invoice.poNumber,
                      style: pw.TextStyle(font: fontBold, fontSize: 10.5, color: PdfColors.black),
                    ),
                  ),
                ),
              if (invoice.poDate != null)
                pw.Positioned(
                  left: 365.0,
                  top: 136.0,
                  child: pw.Text(
                    DateFormatter.format(invoice.poDate),
                    style: pw.TextStyle(font: fontBold, fontSize: 10.0, color: PdfColors.black),
                  ),
                ),

              // 9. Challan No. & Date (Row 3: y=156, Row 4 Date: y=178)
              if (invoice.challanNumber.isNotEmpty)
                pw.Positioned(
                  left: 392.0,
                  top: 156.0,
                  child: pw.SizedBox(
                    width: 82.0,
                    child: pw.Text(
                      invoice.challanNumber,
                      style: pw.TextStyle(font: fontBold, fontSize: 10.5, color: PdfColors.black),
                    ),
                  ),
                ),
              if (invoice.challanDate != null)
                pw.Positioned(
                  left: 365.0,
                  top: 178.0,
                  child: pw.Text(
                    DateFormatter.format(invoice.challanDate),
                    style: pw.TextStyle(font: fontBold, fontSize: 10.0, color: PdfColors.black),
                  ),
                ),

              // 10. Table Line Items (Up to 11 rows perfectly spaced across 220 pt table height)
              ...List.generate(
                invoice.items.length > 11 ? 11 : invoice.items.length,
                (idx) {
                  final itm = invoice.items[idx];
                  final y = 227.0 + (idx * 19.5);

                  final amount = itm.taxableValue > 0 ? itm.taxableValue : itm.totalAmount;
                  final rupees = amount.floor();
                  final paise = ((amount - rupees) * 100).round();

                  return pw.Stack(
                    children: [
                      // S.No (Col: 27.5 - 66.5)
                      pw.Positioned(
                        left: 27.5,
                        top: y,
                        child: pw.SizedBox(
                          width: 39.0,
                          child: pw.Center(
                            child: pw.Text('${itm.sno}', style: pw.TextStyle(font: fontBold, fontSize: 11.0, color: PdfColors.black)),
                          ),
                        ),
                      ),
                      // Description (Col: 66.5 - 211.0)
                      pw.Positioned(
                        left: 68.0,
                        top: y,
                        child: pw.SizedBox(
                          width: 140.0,
                          child: pw.Align(
                            alignment: pw.Alignment.centerLeft,
                            child: pw.Text(
                              itm.description,
                              maxLines: 1,
                              overflow: pw.TextOverflow.clip,
                              style: pw.TextStyle(font: fontBold, fontSize: 10.5, color: PdfColors.black),
                            ),
                          ),
                        ),
                      ),
                      // HSN Code (Col: 211.0 - 254.0)
                      pw.Positioned(
                        left: 211.0,
                        top: y,
                        child: pw.SizedBox(
                          width: 43.0,
                          child: pw.Center(
                            child: pw.Text(itm.hsnCode, style: pw.TextStyle(font: fontBold, fontSize: 10.0, color: PdfColors.black)),
                          ),
                        ),
                      ),
                      // Qty (Col: 254.0 - 288.5)
                      pw.Positioned(
                        left: 254.0,
                        top: y,
                        child: pw.SizedBox(
                          width: 34.5,
                          child: pw.Center(
                            child: pw.Text(
                              '${itm.quantity.toStringAsFixed(itm.quantity.truncateToDouble() == itm.quantity ? 0 : 2)} ${itm.unit}',
                              style: pw.TextStyle(font: fontBold, fontSize: 9.5, color: PdfColors.black),
                            ),
                          ),
                        ),
                      ),
                      // Rate (Col: 288.5 - 356.5)
                      pw.Positioned(
                        left: 288.5,
                        top: y,
                        child: pw.SizedBox(
                          width: 64.0,
                          child: pw.Align(
                            alignment: pw.Alignment.centerRight,
                            child: pw.Text(itm.rate.toStringAsFixed(2), style: pw.TextStyle(font: fontBold, fontSize: 10.5, color: PdfColors.black)),
                          ),
                        ),
                      ),
                      // Amount Rs (Col: 356.5 - 450.0)
                      pw.Positioned(
                        left: 356.5,
                        top: y,
                        child: pw.SizedBox(
                          width: 88.0,
                          child: pw.Align(
                            alignment: pw.Alignment.centerRight,
                            child: pw.Text('$rupees', style: pw.TextStyle(font: fontBold, fontSize: 11.0, color: PdfColors.black)),
                          ),
                        ),
                      ),
                      // Amount Paise (Col: 450.0 - 479.0)
                      pw.Positioned(
                        left: 450.0,
                        top: y,
                        child: pw.SizedBox(
                          width: 28.0,
                          child: pw.Center(
                            child: pw.Text(paise.toString().padLeft(2, '0'), style: pw.TextStyle(font: fontBold, fontSize: 10.0, color: PdfColors.black)),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),

              // 11. Net Amount (Row: 444.0 - 459.0)
              ..._buildRupeesPaiseRow(invoice.netAmount, 446.0, fontBold, fontSize: 11.0),

              // 12. Taxes (SGST & CGST or IGST)
              if (!invoice.isInterState) ...[
                // SGST Rate (Row: 459.0 - 471.0)
                pw.Positioned(
                  left: 288.5,
                  top: 459.5,
                  child: pw.SizedBox(
                    width: 62.0,
                    child: pw.Center(
                      child: pw.Text('${(effectiveGstRate / 2).toStringAsFixed(1)}%', style: pw.TextStyle(font: fontBold, fontSize: 9.5, color: PdfColors.black)),
                    ),
                  ),
                ),
                ..._buildRupeesPaiseRow(invoice.sgstTotal, 459.5, fontBold, fontSize: 10.5),

                // CGST Rate (Row: 471.0 - 483.0)
                pw.Positioned(
                  left: 288.5,
                  top: 471.5,
                  child: pw.SizedBox(
                    width: 62.0,
                    child: pw.Center(
                      child: pw.Text('${(effectiveGstRate / 2).toStringAsFixed(1)}%', style: pw.TextStyle(font: fontBold, fontSize: 9.5, color: PdfColors.black)),
                    ),
                  ),
                ),
                ..._buildRupeesPaiseRow(invoice.cgstTotal, 471.5, fontBold, fontSize: 10.5),

                // IGST 0.0 (Row: 483.0 - 495.0)
                pw.Positioned(
                  left: 288.5,
                  top: 483.5,
                  child: pw.SizedBox(
                    width: 62.0,
                    child: pw.Center(
                      child: pw.Text('0.0%', style: pw.TextStyle(font: fontBold, fontSize: 9.5, color: PdfColors.black)),
                    ),
                  ),
                ),
                ..._buildRupeesPaiseRow(0.0, 483.5, fontBold, fontSize: 10.5),
              ] else ...[
                // Inter-state: SGST 0, CGST 0, IGST Rate
                pw.Positioned(
                  left: 288.5,
                  top: 459.5,
                  child: pw.SizedBox(
                    width: 62.0,
                    child: pw.Center(
                      child: pw.Text('0.0%', style: pw.TextStyle(font: fontBold, fontSize: 9.5, color: PdfColors.black)),
                    ),
                  ),
                ),
                ..._buildRupeesPaiseRow(0.0, 459.5, fontBold, fontSize: 10.5),

                pw.Positioned(
                  left: 288.5,
                  top: 471.5,
                  child: pw.SizedBox(
                    width: 62.0,
                    child: pw.Center(
                      child: pw.Text('0.0%', style: pw.TextStyle(font: fontBold, fontSize: 9.5, color: PdfColors.black)),
                    ),
                  ),
                ),
                ..._buildRupeesPaiseRow(0.0, 471.5, fontBold, fontSize: 10.5),

                // IGST Rate
                pw.Positioned(
                  left: 288.5,
                  top: 483.5,
                  child: pw.SizedBox(
                    width: 62.0,
                    child: pw.Center(
                      child: pw.Text('${effectiveGstRate.toStringAsFixed(1)}%', style: pw.TextStyle(font: fontBold, fontSize: 9.5, color: PdfColors.black)),
                    ),
                  ),
                ),
                ..._buildRupeesPaiseRow(invoice.igstTotal, 483.5, fontBold, fontSize: 10.5),
              ],

              // 13. Round Off (Row: 495.0 - 508.0)
              ..._buildRupeesPaiseRow(invoice.roundOff, 496.0, fontBold, fontSize: 10.0),

              // 14. Grand Total (Row: 508.0 - 524.0 - Prominent Pen Ink)
              ..._buildRupeesPaiseRow(invoice.grandTotal, 509.5, fontBold, fontSize: 14.0),

              // 15. Total Amount in Words (Row: 524.0 - 541.0, Shifted right to start after 'Invoice Value (in word)' label, utilizing full row width up to right border)
              pw.Positioned(
                left: 168.0,
                top: 526.0,
                child: pw.SizedBox(
                  width: 305.0,
                  child: pw.Text(
                    invoice.amountInWords,
                    maxLines: 2,
                    style: pw.TextStyle(font: fontBold, fontSize: wordsFontSize, color: PdfColors.black),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );

    return pdf.save();
  }

  static List<pw.Widget> _buildRupeesPaiseRow(double val, double y, pw.Font font, {double fontSize = 11.0}) {
    final isNegative = val < 0;
    final absVal = val.abs();
    final r = absVal.truncate();
    final p = ((absVal - r) * 100).round();
    final rText = isNegative && r == 0 ? '-0' : (isNegative ? '-$r' : '$r');

    return [
      pw.Positioned(
        left: 356.5,
        top: y,
        child: pw.SizedBox(
          width: 88.0,
          child: pw.Align(
            alignment: pw.Alignment.centerRight,
            child: pw.Text(
              rText,
              style: pw.TextStyle(font: font, fontSize: fontSize, color: PdfColors.black),
            ),
          ),
        ),
      ),
      pw.Positioned(
        left: 450.0,
        top: y,
        child: pw.SizedBox(
          width: 28.0,
          child: pw.Center(
            child: pw.Text(
              p.toString().padLeft(2, '0'),
              style: pw.TextStyle(font: font, fontSize: fontSize > 12 ? 12.0 : fontSize, color: PdfColors.black),
            ),
          ),
        ),
      ),
    ];
  }

  /// Formats customer name with date for file export (e.g. Jindal_Steel_INV-01_01-11-2026.pdf)
  static String getPdfBaseName(InvoiceModel invoice) {
    final rawCustomer = invoice.customer.name.trim();
    final safeInvoice = invoice.invoiceNumber.replaceAll(RegExp(r'[\\/:*?"<>|\s]'), '_');
    final d = invoice.invoiceDate;
    final dateStr = '${d.day.toString().padLeft(2, '0')}-${d.month.toString().padLeft(2, '0')}-${d.year}';

    if (rawCustomer.isEmpty) {
      return 'Invoice_${safeInvoice}_$dateStr';
    }

    final safeCustomer = rawCustomer
        .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')
        .replaceAll(RegExp(r'\s+'), '_');
    return '${safeCustomer}_${safeInvoice}_$dateStr';
  }

  static String getPdfFileName(InvoiceModel invoice) {
    return '${getPdfBaseName(invoice)}.pdf';
  }

  /// 1-Tap Print invoice on Android
  static Future<void> printInvoice(InvoiceModel invoice) async {
    final pdfBytes = await generateInvoicePdfBytes(invoice);
    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdfBytes,
      name: getPdfBaseName(invoice),
    );
  }

  /// 1-Tap Share invoice PDF via WhatsApp, Email, etc.
  static Future<void> shareInvoicePdf(InvoiceModel invoice) async {
    final pdfBytes = await generateInvoicePdfBytes(invoice);
    final tempDir = await getTemporaryDirectory();
    final fileName = getPdfFileName(invoice);
    final file = File('${tempDir.path}/$fileName');
    await file.writeAsBytes(pdfBytes);

    await Share.shareXFiles(
      [XFile(file.path)],
      text: 'Tax Invoice for ${invoice.customer.name}: ${invoice.invoiceNumber}',
    );
  }

  /// Share multiple invoice PDFs simultaneously via WhatsApp, Email, Drive, etc.
  static Future<void> shareMultipleInvoices(List<InvoiceModel> invoices) async {
    if (invoices.isEmpty) return;

    if (invoices.length == 1) {
      await shareInvoicePdf(invoices.first);
      return;
    }

    final tempDir = await getTemporaryDirectory();
    final List<XFile> xFiles = [];

    for (final inv in invoices) {
      final pdfBytes = await generateInvoicePdfBytes(inv);
      final fileName = getPdfFileName(inv);
      final file = File('${tempDir.path}/$fileName');
      await file.writeAsBytes(pdfBytes);
      xFiles.add(XFile(file.path));
    }

    final names = invoices.map((e) => e.invoiceNumber).join(', ');
    await Share.shareXFiles(
      xFiles,
      text: 'Tax Invoices from Suprime Solutions (${invoices.length} bills: $names)',
    );
  }
}
