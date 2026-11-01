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

    final fontNormal = await PdfGoogleFonts.robotoRegular();
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

              // 2. Invoice Number (Enlarged & Bold Pen Ink)
              pw.Positioned(
                left: 395,
                top: 36,
                child: pw.Text(
                  invoice.invoiceNumber,
                  style: pw.TextStyle(font: fontBold, fontSize: 13.5, color: PdfColors.black),
                ),
              ),

              // 3. Invoice Date (Enlarged & Bold Pen Ink)
              pw.Positioned(
                left: 405,
                top: 67,
                child: pw.Text(
                  DateFormatter.format(invoice.invoiceDate),
                  style: pw.TextStyle(font: fontBold, fontSize: 11.5, color: PdfColors.black),
                ),
              ),

              // 4. Customer Name (Line under M/s - Large & Bold)
              pw.Positioned(
                left: 65,
                top: 107,
                child: pw.SizedBox(
                  width: 260,
                  child: pw.Text(
                    invoice.customer.name.toUpperCase(),
                    maxLines: 1,
                    overflow: pw.TextOverflow.clip,
                    style: pw.TextStyle(font: fontBold, fontSize: 12.0, color: PdfColors.black),
                  ),
                ),
              ),

              // 5. Customer Address (Lines 1 & 2 - Bold Pen Ink)
              pw.Positioned(
                left: 42,
                top: 126,
                child: pw.SizedBox(
                  width: 284,
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
                  left: 42,
                  top: 141,
                  child: pw.SizedBox(
                    width: 284,
                    child: pw.Text(
                      addr2,
                      maxLines: 1,
                      overflow: pw.TextOverflow.clip,
                      style: pw.TextStyle(font: fontBold, fontSize: 10.0, color: PdfColors.black),
                    ),
                  ),
                ),

              // 6. State & State Code (Large & Bold Pen Ink)
              pw.Positioned(
                left: 75,
                top: 157,
                child: pw.Text(
                  invoice.customer.state,
                  style: pw.TextStyle(font: fontBold, fontSize: 10.5, color: PdfColors.black),
                ),
              ),
              pw.Positioned(
                left: 260,
                top: 157,
                child: pw.Text(
                  invoice.customer.stateCode,
                  style: pw.TextStyle(font: fontBold, fontSize: 10.5, color: PdfColors.black),
                ),
              ),

              // 7. GSTIN No. (Large & Bold Pen Ink)
              pw.Positioned(
                left: 95,
                top: 174,
                child: pw.Text(
                  invoice.customer.gstin,
                  style: pw.TextStyle(font: fontBold, fontSize: 11.5, color: PdfColors.black),
                ),
              ),

              // 8. P.O. No. & Date
              if (invoice.poNumber.isNotEmpty)
                pw.Positioned(
                  left: 372,
                  top: 131,
                  child: pw.Text(
                    invoice.poNumber,
                    style: pw.TextStyle(font: fontBold, fontSize: 10.5, color: PdfColors.black),
                  ),
                ),
              if (invoice.poDate != null)
                pw.Positioned(
                  left: 372,
                  top: 142,
                  child: pw.Text(
                    DateFormatter.format(invoice.poDate),
                    style: pw.TextStyle(font: fontBold, fontSize: 9.5, color: PdfColors.black),
                  ),
                ),

              // 9. Challan No. & Date
              if (invoice.challanNumber.isNotEmpty)
                pw.Positioned(
                  left: 372,
                  top: 173,
                  child: pw.Text(
                    invoice.challanNumber,
                    style: pw.TextStyle(font: fontBold, fontSize: 10.5, color: PdfColors.black),
                  ),
                ),
              if (invoice.challanDate != null)
                pw.Positioned(
                  left: 372,
                  top: 184,
                  child: pw.Text(
                    DateFormatter.format(invoice.challanDate),
                    style: pw.TextStyle(font: fontBold, fontSize: 9.5, color: PdfColors.black),
                  ),
                ),

              // 10. Table Line Items (Up to 11 rows - All Enlarged & Bold Pen Ink)
              ...List.generate(
                invoice.items.length > 11 ? 11 : invoice.items.length,
                (idx) {
                  final itm = invoice.items[idx];
                  final y = 229.0 + (idx * 19.0);

                  final amount = itm.taxableValue > 0 ? itm.taxableValue : itm.totalAmount;
                  final rupees = amount.floor();
                  final paise = ((amount - rupees) * 100).round();

                  return pw.Stack(
                    children: [
                      // S.No
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
                      // Description
                      pw.Positioned(
                        left: 70.0,
                        top: y,
                        child: pw.SizedBox(
                          width: 139.0,
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
                      // HSN Code
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
                      // Qty
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
                      // Rate
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
                      // Amount Rs
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
                      // Amount Paise
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

              // 11. Net Amount (Y = 445.0)
              ..._buildRupeesPaiseRow(invoice.netAmount, 445.0, fontBold, fontSize: 11.0),

              // 12. Taxes (SGST & CGST or IGST - Large & Bold Pen Ink)
              if (!invoice.isInterState) ...[
                // SGST Rate
                pw.Positioned(
                  left: 288.5,
                  top: 458.5,
                  child: pw.SizedBox(
                    width: 62.0,
                    child: pw.Center(
                      child: pw.Text('${(effectiveGstRate / 2).toStringAsFixed(1)}%', style: pw.TextStyle(font: fontBold, fontSize: 9.5, color: PdfColors.black)),
                    ),
                  ),
                ),
                ..._buildRupeesPaiseRow(invoice.sgstTotal, 458.5, fontBold, fontSize: 10.5),

                // CGST Rate
                pw.Positioned(
                  left: 288.5,
                  top: 470.5,
                  child: pw.SizedBox(
                    width: 62.0,
                    child: pw.Center(
                      child: pw.Text('${(effectiveGstRate / 2).toStringAsFixed(1)}%', style: pw.TextStyle(font: fontBold, fontSize: 9.5, color: PdfColors.black)),
                    ),
                  ),
                ),
                ..._buildRupeesPaiseRow(invoice.cgstTotal, 470.5, fontBold, fontSize: 10.5),

                // IGST (0.0)
                pw.Positioned(
                  left: 288.5,
                  top: 482.5,
                  child: pw.SizedBox(
                    width: 62.0,
                    child: pw.Center(
                      child: pw.Text('0.0%', style: pw.TextStyle(font: fontBold, fontSize: 9.5, color: PdfColors.black)),
                    ),
                  ),
                ),
                ..._buildRupeesPaiseRow(0.0, 482.5, fontBold, fontSize: 10.5),
              ] else ...[
                // Inter-state: SGST 0, CGST 0, IGST Rate
                pw.Positioned(
                  left: 288.5,
                  top: 458.5,
                  child: pw.SizedBox(
                    width: 62.0,
                    child: pw.Center(
                      child: pw.Text('0.0%', style: pw.TextStyle(font: fontBold, fontSize: 9.5, color: PdfColors.black)),
                    ),
                  ),
                ),
                ..._buildRupeesPaiseRow(0.0, 458.5, fontBold, fontSize: 10.5),

                pw.Positioned(
                  left: 288.5,
                  top: 470.5,
                  child: pw.SizedBox(
                    width: 62.0,
                    child: pw.Center(
                      child: pw.Text('0.0%', style: pw.TextStyle(font: fontBold, fontSize: 9.5, color: PdfColors.black)),
                    ),
                  ),
                ),
                ..._buildRupeesPaiseRow(0.0, 470.5, fontBold, fontSize: 10.5),

                // IGST Rate
                pw.Positioned(
                  left: 288.5,
                  top: 482.5,
                  child: pw.SizedBox(
                    width: 62.0,
                    child: pw.Center(
                      child: pw.Text('${effectiveGstRate.toStringAsFixed(1)}%', style: pw.TextStyle(font: fontBold, fontSize: 9.5, color: PdfColors.black)),
                    ),
                  ),
                ),
                ..._buildRupeesPaiseRow(invoice.igstTotal, 482.5, fontBold, fontSize: 10.5),
              ],

              // 13. Round Off (Y = 495.0)
              ..._buildRupeesPaiseRow(invoice.roundOff, 495.0, fontBold, fontSize: 10.0),

              // 14. Grand Total (Y = 508.5 - Large & Prominent Pen Ink)
              ..._buildRupeesPaiseRow(invoice.grandTotal, 508.5, fontBold, fontSize: 14.5),

              // 15. Total Amount in Words (Y = 527.0 - Bold Pen Ink)
              pw.Positioned(
                left: 155,
                top: 527,
                child: pw.SizedBox(
                  width: 320,
                  child: pw.Text(
                    invoice.amountInWords,
                    maxLines: 2,
                    style: pw.TextStyle(font: fontBold, fontSize: 9.5, color: PdfColors.black),
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
    final r = val.floor();
    final p = ((val - r) * 100).round().abs();

    return [
      pw.Positioned(
        left: 356.5,
        top: y,
        child: pw.SizedBox(
          width: 88.0,
          child: pw.Align(
            alignment: pw.Alignment.centerRight,
            child: pw.Text(
              '$r',
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

  /// Formats customer name with date for file export (e.g. Jindal_Steel_01-11-2026.pdf)
  static String getPdfBaseName(InvoiceModel invoice) {
    final rawCustomer = invoice.customer.name.trim();
    final d = invoice.invoiceDate;
    final dateStr = '${d.day.toString().padLeft(2, '0')}-${d.month.toString().padLeft(2, '0')}-${d.year}';

    if (rawCustomer.isEmpty) {
      return 'Invoice_${invoice.invoiceNumber.replaceAll(RegExp(r'[\\/:*?"<>|\s]'), '_')}_$dateStr';
    }

    final safeCustomer = rawCustomer
        .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')
        .replaceAll(RegExp(r'\s+'), '_');
    return '${safeCustomer}_$dateStr';
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
}
