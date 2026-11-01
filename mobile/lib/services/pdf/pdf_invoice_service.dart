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
  static const double masterWidth = 817.0;
  static const double masterHeight = 1000.0;
  static const double sourcePixelWidth = 2296.0;
  static const double sourcePixelHeight = 2809.0;

  static double _ptX(double pxX) => (pxX / sourcePixelWidth) * masterWidth;
  static double _ptY(double pxY) => (pxY / sourcePixelHeight) * masterHeight;

  /// Generate high-precision PDF document bytes matching the original paper invoice
  static Future<Uint8List> generateInvoicePdfBytes(InvoiceModel invoice) async {
    final pdf = pw.Document();

    // Load master 300 DPI high-definition scanned template image from assets
    final templateImageBytes = await rootBundle.load('assets/invoice-template/template_hq_300dpi.jpg');
    final templateImage = pw.MemoryImage(templateImageBytes.buffer.asUint8List());

    final fontNormal = await PdfGoogleFonts.robotoRegular();
    final fontBold = await PdfGoogleFonts.robotoBold();

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

              // 2. Invoice Number (Enlarged & High Visibility)
              pw.Positioned(
                left: _ptX(1820),
                top: _ptY(255),
                child: pw.Text(
                  invoice.invoiceNumber,
                  style: pw.TextStyle(font: fontBold, fontSize: 18, color: PdfColors.black),
                ),
              ),

              // 3. Invoice Date (Enlarged & Bold)
              pw.Positioned(
                left: _ptX(1915),
                top: _ptY(348),
                child: pw.Text(
                  DateFormatter.format(invoice.invoiceDate),
                  style: pw.TextStyle(font: fontBold, fontSize: 14, color: PdfColors.black),
                ),
              ),

              // 4. Customer Name (Line 1 under M/s - Large & Bold)
              pw.Positioned(
                left: _ptX(280),
                top: _ptY(535),
                child: pw.Text(
                  invoice.customer.name.toUpperCase(),
                  style: pw.TextStyle(font: fontBold, fontSize: 16, color: PdfColors.black),
                ),
              ),

              // 5. Customer Address (Line 2 - Clear & Large)
              pw.Positioned(
                left: _ptX(200),
                top: _ptY(635),
                child: pw.SizedBox(
                  width: _ptX(1300),
                  child: pw.Text(
                    invoice.customer.address,
                    style: pw.TextStyle(font: fontNormal, fontSize: 13.5, color: PdfColors.black),
                  ),
                ),
              ),

              // 6. State & State Code (Large & Bold)
              pw.Positioned(
                left: _ptX(340),
                top: _ptY(780),
                child: pw.Text(
                  invoice.customer.state,
                  style: pw.TextStyle(font: fontBold, fontSize: 14, color: PdfColors.black),
                ),
              ),
              pw.Positioned(
                left: _ptX(1200),
                top: _ptY(780),
                child: pw.Text(
                  invoice.customer.stateCode,
                  style: pw.TextStyle(font: fontBold, fontSize: 14, color: PdfColors.black),
                ),
              ),

              // 7. GSTIN No. (Large & Bold)
              pw.Positioned(
                left: _ptX(520),
                top: _ptY(868),
                child: pw.Text(
                  invoice.customer.gstin,
                  style: pw.TextStyle(font: fontBold, fontSize: 15.5, color: PdfColors.black),
                ),
              ),

              // 8. P.O. No. & Date (Large & Bold)
              if (invoice.poNumber.isNotEmpty)
                pw.Positioned(
                  left: _ptX(1750),
                  top: _ptY(555),
                  child: pw.Text(
                    invoice.poNumber,
                    style: pw.TextStyle(font: fontBold, fontSize: 13.5, color: PdfColors.black),
                  ),
                ),
              if (invoice.poDate != null)
                pw.Positioned(
                  left: _ptX(1720),
                  top: _ptY(660),
                  child: pw.Text(
                    DateFormatter.format(invoice.poDate),
                    style: pw.TextStyle(font: fontBold, fontSize: 13.5, color: PdfColors.black),
                  ),
                ),

              // 9. Challan No. & Date (Large & Bold)
              if (invoice.challanNumber.isNotEmpty)
                pw.Positioned(
                  left: _ptX(1870),
                  top: _ptY(760),
                  child: pw.Text(
                    invoice.challanNumber,
                    style: pw.TextStyle(font: fontBold, fontSize: 13.5, color: PdfColors.black),
                  ),
                ),
              if (invoice.challanDate != null)
                pw.Positioned(
                  left: _ptX(1720),
                  top: _ptY(870),
                  child: pw.Text(
                    DateFormatter.format(invoice.challanDate),
                    style: pw.TextStyle(font: fontBold, fontSize: 13.5, color: PdfColors.black),
                  ),
                ),

              // 10. Table Line Items (Up to 11 rows - All Enlarged & Bold)
              ...List.generate(
                invoice.items.length > 11 ? 11 : invoice.items.length,
                (idx) {
                  final itm = invoice.items[idx];
                  final y = _ptY(1120.0 + (idx * 75.0));

                  final amount = itm.taxableValue > 0 ? itm.taxableValue : itm.totalAmount;
                  final rupees = amount.floor();
                  final paise = ((amount - rupees) * 100).round();

                  return pw.Stack(
                    children: [
                      // S.No (Center at 235)
                      pw.Positioned(
                        left: _ptX(210),
                        top: y,
                        child: pw.SizedBox(
                          width: _ptX(50),
                          child: pw.Center(
                            child: pw.Text('${itm.sno}', style: pw.TextStyle(font: fontBold, fontSize: 14)),
                          ),
                        ),
                      ),
                      // Description (Left at 335 - Bold & Prominent)
                      pw.Positioned(
                        left: _ptX(335),
                        top: y,
                        child: pw.SizedBox(
                          width: _ptX(630),
                          child: pw.Text(
                            itm.description,
                            maxLines: 1,
                            overflow: pw.TextOverflow.clip,
                            style: pw.TextStyle(font: fontBold, fontSize: 13),
                          ),
                        ),
                      ),
                      // HSN Code (Center at 1080)
                      pw.Positioned(
                        left: _ptX(1020),
                        top: y,
                        child: pw.SizedBox(
                          width: _ptX(120),
                          child: pw.Center(
                            child: pw.Text(itm.hsnCode, style: pw.TextStyle(font: fontBold, fontSize: 13)),
                          ),
                        ),
                      ),
                      // Qty (Center at 1260)
                      pw.Positioned(
                        left: _ptX(1190),
                        top: y,
                        child: pw.SizedBox(
                          width: _ptX(140),
                          child: pw.Center(
                            child: pw.Text('${itm.quantity.toStringAsFixed(itm.quantity.truncateToDouble() == itm.quantity ? 0 : 2)} ${itm.unit}', style: pw.TextStyle(font: fontBold, fontSize: 13.5)),
                          ),
                        ),
                      ),
                      // Rate (Right at 1630)
                      pw.Positioned(
                        left: _ptX(1350),
                        top: y,
                        child: pw.SizedBox(
                          width: _ptX(280),
                          child: pw.Align(
                            alignment: pw.Alignment.centerRight,
                            child: pw.Text(itm.rate.toStringAsFixed(2), style: pw.TextStyle(font: fontBold, fontSize: 13.5)),
                          ),
                        ),
                      ),
                      // Amount Rs (Right at 2060)
                      pw.Positioned(
                        left: _ptX(1660),
                        top: y,
                        child: pw.SizedBox(
                          width: _ptX(400),
                          child: pw.Align(
                            alignment: pw.Alignment.centerRight,
                            child: pw.Text('$rupees', style: pw.TextStyle(font: fontBold, fontSize: 14)),
                          ),
                        ),
                      ),
                      // Amount P (Center at 2135)
                      pw.Positioned(
                        left: _ptX(2085),
                        top: y,
                        child: pw.SizedBox(
                          width: _ptX(100),
                          child: pw.Center(
                            child: pw.Text(paise.toString().padLeft(2, '0'), style: pw.TextStyle(font: fontBold, fontSize: 13.5)),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),

              // 11. Net Amount (Y = 2110)
              ..._buildRupeesPaiseRow(invoice.netAmount, 2110.0, fontBold, isBold: true, fontSize: 14.5),

              // 12. Taxes (SGST & CGST or IGST - Large & Bold)
              if (!invoice.isInterState) ...[
                // SGST Rate
                pw.Positioned(
                  left: _ptX(1420),
                  top: _ptY(2175),
                  child: pw.SizedBox(
                    width: _ptX(80),
                    child: pw.Center(
                      child: pw.Text(((invoice.items.isNotEmpty ? invoice.items[0].gstRate : 18.0) / 2).toStringAsFixed(1), style: pw.TextStyle(font: fontBold, fontSize: 13.5)),
                    ),
                  ),
                ),
                ..._buildRupeesPaiseRow(invoice.sgstTotal, 2175.0, fontBold, isBold: true, fontSize: 14),

                // CGST Rate
                pw.Positioned(
                  left: _ptX(1420),
                  top: _ptY(2235),
                  child: pw.SizedBox(
                    width: _ptX(80),
                    child: pw.Center(
                      child: pw.Text(((invoice.items.isNotEmpty ? invoice.items[0].gstRate : 18.0) / 2).toStringAsFixed(1), style: pw.TextStyle(font: fontBold, fontSize: 13.5)),
                    ),
                  ),
                ),
                ..._buildRupeesPaiseRow(invoice.cgstTotal, 2235.0, fontBold, isBold: true, fontSize: 14),

                // IGST 0
                pw.Positioned(
                  left: _ptX(1420),
                  top: _ptY(2295),
                  child: pw.SizedBox(
                    width: _ptX(80),
                    child: pw.Center(
                      child: pw.Text('0.0', style: pw.TextStyle(font: fontBold, fontSize: 13.5)),
                    ),
                  ),
                ),
                ..._buildRupeesPaiseRow(0.0, 2295.0, fontBold, isBold: true, fontSize: 14),
              ] else ...[
                // Intra-state 0
                pw.Positioned(left: _ptX(1420), top: _ptY(2175), child: pw.Text('0.0', style: pw.TextStyle(font: fontBold, fontSize: 13.5))),
                ..._buildRupeesPaiseRow(0.0, 2175.0, fontBold, isBold: true, fontSize: 14),
                pw.Positioned(left: _ptX(1420), top: _ptY(2235), child: pw.Text('0.0', style: pw.TextStyle(font: fontBold, fontSize: 13.5))),
                ..._buildRupeesPaiseRow(0.0, 2235.0, fontBold, isBold: true, fontSize: 14),

                // IGST
                pw.Positioned(
                  left: _ptX(1420),
                  top: _ptY(2295),
                  child: pw.SizedBox(
                    width: _ptX(80),
                    child: pw.Center(
                      child: pw.Text((invoice.items.isNotEmpty ? invoice.items[0].gstRate : 18.0).toStringAsFixed(1), style: pw.TextStyle(font: fontBold, fontSize: 13.5)),
                    ),
                  ),
                ),
                ..._buildRupeesPaiseRow(invoice.igstTotal, 2295.0, fontBold, isBold: true, fontSize: 14),
              ],

              // 13. Round Off (Y = 2355)
              ..._buildRupeesPaiseRow(invoice.roundOff, 2355.0, fontBold, isBold: true, fontSize: 13.5),

              // 14. Grand Total (Y = 2420 - Huge & Extra Bold)
              ..._buildRupeesPaiseRow(invoice.grandTotal, 2420.0, fontBold, isBold: true, fontSize: 18),

              // 15. Invoice Value in Words (Y = 2498, X = 765 - Large & Bold)
              pw.Positioned(
                left: _ptX(765),
                top: _ptY(2498),
                child: pw.SizedBox(
                  width: _ptX(1400),
                  child: pw.Text(
                    invoice.amountInWords,
                    style: pw.TextStyle(font: fontBold, fontSize: 13.5, color: PdfColors.black),
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

  static List<pw.Widget> _buildRupeesPaiseRow(double val, double yPx, pw.Font font, {bool isBold = false, double fontSize = 14.0}) {
    final r = val.floor();
    final p = ((val - r) * 100).round().abs();

    return [
      pw.Positioned(
        left: _ptX(1660),
        top: _ptY(yPx),
        child: pw.SizedBox(
          width: _ptX(400),
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
        left: _ptX(2085),
        top: _ptY(yPx),
        child: pw.SizedBox(
          width: _ptX(100),
          child: pw.Center(
            child: pw.Text(
              p.toString().padLeft(2, '0'),
              style: pw.TextStyle(font: font, fontSize: fontSize, color: PdfColors.black),
            ),
          ),
        ),
      ),
    ];
  }

  /// 1-Tap Print invoice on Android
  static Future<void> printInvoice(InvoiceModel invoice) async {
    final pdfBytes = await generateInvoicePdfBytes(invoice);
    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdfBytes,
      name: 'Invoice_${invoice.invoiceNumber.replaceAll('/', '_')}',
    );
  }

  /// 1-Tap Share invoice PDF via WhatsApp, Email, etc.
  static Future<void> shareInvoicePdf(InvoiceModel invoice) async {
    final pdfBytes = await generateInvoicePdfBytes(invoice);
    final tempDir = await getTemporaryDirectory();
    final fileName = 'Invoice_${invoice.invoiceNumber.replaceAll('/', '_')}.pdf';
    final file = File('${tempDir.path}/$fileName');
    await file.writeAsBytes(pdfBytes);

    await Share.shareXFiles(
      [XFile(file.path)],
      text: 'Tax Invoice from SS Supreme Solutions: ${invoice.invoiceNumber}',
    );
  }
}
