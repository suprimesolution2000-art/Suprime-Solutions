import 'dart:io';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../../data/models/invoice_model.dart';
import '../../core/utils/date_formatter.dart';
import '../../core/utils/currency_formatter.dart';

class PdfInvoiceService {
  // Calibrated exact dimensions matching the vector invoice template
  static const double masterWidth = 492.0;
  static const double masterHeight = 602.0;

  /// Main entry point: Generates either GST Tax Invoice or Temporary Bill depending on invoiceType
  static Future<Uint8List> generateInvoicePdfBytes(InvoiceModel invoice, {String? overrideType}) async {
    final type = overrideType ?? invoice.invoiceType;
    if (type == 'temporary') {
      return generateTemporaryBillPdfBytes(invoice);
    }
    return generateGstInvoicePdfBytes(invoice);
  }

  /// Generate Temporary Bill PDF bytes matching the wooden plank template
  static Future<Uint8List> generateTemporaryBillPdfBytes(InvoiceModel invoice) async {
    final pdf = pw.Document();

    final templateImageBytes = await rootBundle.load('assets/invoice-template/temporary_bill_template_300dpi.jpg');
    final templateImage = pw.MemoryImage(templateImageBytes.buffer.asUint8List());

    final fontBold = await PdfGoogleFonts.robotoBold();
    final fontRegular = await PdfGoogleFonts.robotoRegular();
    final fontMedium = await PdfGoogleFonts.robotoMedium();

    // Theme Colors
    const espressoColor = PdfColor.fromInt(0xFF2A160A);
    const goldCreamColor = PdfColor.fromInt(0xFFFAF0D1);

    String custName = invoice.customer.name.trim().toUpperCase();
    if (custName.isEmpty) custName = 'CUSTOMER';

    pdf.addPage(
      pw.Page(
        pageFormat: const PdfPageFormat(595.28, 841.89, marginAll: 0),
        build: (pw.Context context) {
          return pw.Stack(
            children: [
              // 1. Full-bleed background template
              pw.Positioned(
                left: 0,
                top: 0,
                right: 0,
                bottom: 0,
                child: pw.Image(templateImage, fit: pw.BoxFit.fill),
              ),

              // 1.5. BILL NO. Box (Drawn directly inside the top-right "NO." box above the underline)
              pw.Positioned(
                left: 468.0,
                top: 74.0,
                child: pw.Text(
                  invoice.sequenceNumber > 0
                      ? invoice.sequenceNumber.toString()
                      : invoice.invoiceNumber.replaceAll(RegExp(r'^TEMP-'), ''),
                  style: pw.TextStyle(font: fontBold, fontSize: 13.0, color: espressoColor),
                ),
              ),

              // 2. BILLED TO Box (Only Customer Name, positioned directly above the line)
              pw.Positioned(
                left: 58.0,
                top: 224.0,
                child: pw.SizedBox(
                  width: 275.0,
                  child: pw.Text(
                    custName,
                    maxLines: 1,
                    overflow: pw.TextOverflow.clip,
                    style: pw.TextStyle(font: fontBold, fontSize: 12.0, color: espressoColor),
                  ),
                ),
              ),

              // 3. BILL DATE Box (ONLY DATE, NO "Date:" prefix, positioned directly above the line)
              pw.Positioned(
                left: 385.5,
                top: 224.0,
                child: pw.SizedBox(
                  width: 155.0,
                  child: pw.Text(
                    DateFormatter.format(invoice.invoiceDate),
                    style: pw.TextStyle(font: fontBold, fontSize: 12.0, color: espressoColor),
                  ),
                ),
              ),

              // 4. Items Table (5 columns: NO., PRODUCT, QTY., RATE, TOTAL)
              ...List.generate(
                invoice.items.length > 16 ? 16 : invoice.items.length,
                (idx) {
                  final itm = invoice.items[idx];
                  final rowTop = 328.0 + (idx * 24.62);

                  final qtyStr = itm.quantity > 0
                      ? (itm.quantity % 1 == 0 ? itm.quantity.toInt().toString() : itm.quantity.toString()) + (itm.unit.isNotEmpty ? ' ${itm.unit}' : '')
                      : '';
                  final rateStr = itm.rate > 0 ? CurrencyFormatter.formatWithoutSymbol(itm.rate) : '';
                  final totalStr = CurrencyFormatter.formatWithoutSymbol(itm.totalAmount);

                  return pw.Stack(
                    children: [
                      // Product Description
                      pw.Positioned(
                        left: 86.0,
                        top: rowTop - 1.0,
                        child: pw.SizedBox(
                          width: 190.0,
                          child: pw.Text(
                            itm.description,
                            maxLines: 2,
                            softWrap: true,
                            overflow: pw.TextOverflow.clip,
                            style: pw.TextStyle(font: fontMedium, fontSize: 9.5, color: espressoColor),
                          ),
                        ),
                      ),
                      // QTY.
                      pw.Positioned(
                        left: 282.0,
                        top: rowTop,
                        child: pw.SizedBox(
                          width: 70.0,
                          child: pw.Center(
                            child: pw.Text(
                              qtyStr,
                              style: pw.TextStyle(font: fontMedium, fontSize: 9.5, color: espressoColor),
                            ),
                          ),
                        ),
                      ),
                      // RATE (Rs.)
                      pw.Positioned(
                        left: 357.0,
                        top: rowTop,
                        child: pw.SizedBox(
                          width: 88.0,
                          child: pw.Align(
                            alignment: pw.Alignment.centerRight,
                            child: pw.Text(
                              rateStr,
                              style: pw.TextStyle(font: fontMedium, fontSize: 9.5, color: espressoColor),
                            ),
                          ),
                        ),
                      ),
                      // TOTAL (Rs.)
                      pw.Positioned(
                        left: 452.0,
                        top: rowTop,
                        child: pw.SizedBox(
                          width: 94.0,
                          child: pw.Align(
                            alignment: pw.Alignment.centerRight,
                            child: pw.Text(
                              totalStr,
                              style: pw.TextStyle(font: fontBold, fontSize: 10.0, color: espressoColor),
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),

              // 5. TOTAL AMOUNT Box
              pw.Positioned(
                left: 442.0,
                top: 746.0,
                child: pw.SizedBox(
                  width: 93.0,
                  child: pw.Align(
                    alignment: pw.Alignment.centerRight,
                    child: pw.Text(
                      CurrencyFormatter.formatWithoutSymbol(invoice.grandTotal),
                      style: pw.TextStyle(font: fontBold, fontSize: 14.5, color: goldCreamColor),
                    ),
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
  static Future<Uint8List> generateGstInvoicePdfBytes(InvoiceModel invoice) async {
    final pdf = pw.Document();
    final templateImageBytes = await rootBundle.load('assets/invoice-template/template_hq_300dpi.jpg');
    final templateImage = pw.MemoryImage(templateImageBytes.buffer.asUint8List());
    final fontBold = await PdfGoogleFonts.robotoBold();

    pdf.addPage(buildGstInvoicePage(invoice, templateImage, fontBold));
    return pdf.save();
  }

  /// Feature 1: Generate 1 single combined PDF containing all GST Tax Invoices in sequential date order
  static Future<Uint8List> generateCombinedGstBillsPdf(List<InvoiceModel> invoices) async {
    final pdf = pw.Document();
    final templateImageBytes = await rootBundle.load('assets/invoice-template/template_hq_300dpi.jpg');
    final templateImage = pw.MemoryImage(templateImageBytes.buffer.asUint8List());
    final fontBold = await PdfGoogleFonts.robotoBold();

    // Sort chronologically ascending
    final sorted = List<InvoiceModel>.from(invoices)
      ..sort((a, b) {
        final cmp = a.invoiceDate.compareTo(b.invoiceDate);
        if (cmp != 0) return cmp;
        return a.sequenceNumber.compareTo(b.sequenceNumber);
      });

    for (final inv in sorted) {
      pdf.addPage(buildGstInvoicePage(inv, templateImage, fontBold));
    }

    return pdf.save();
  }

  /// Feature 2: Generate an Excel-Style GSTR-1 Sales Register PDF for CA / Audit filing
  static Future<Uint8List> generateGstSalesRegisterPdf(
    List<InvoiceModel> invoices,
    DateTime fromDate,
    DateTime toDate,
  ) async {
    final pdf = pw.Document();
    final fontBold = await PdfGoogleFonts.robotoBold();
    final fontRegular = await PdfGoogleFonts.robotoRegular();

    // Sort chronologically ascending
    final sorted = List<InvoiceModel>.from(invoices)
      ..sort((a, b) {
        final cmp = a.invoiceDate.compareTo(b.invoiceDate);
        if (cmp != 0) return cmp;
        return a.sequenceNumber.compareTo(b.sequenceNumber);
      });

    final double sumTaxable = sorted.fold(0.0, (acc, i) => acc + i.netAmount);
    final double sumCgst = sorted.fold(0.0, (acc, i) => acc + i.cgstTotal);
    final double sumSgst = sorted.fold(0.0, (acc, i) => acc + i.sgstTotal);
    final double sumIgst = sorted.fold(0.0, (acc, i) => acc + i.igstTotal);
    final double sumTotal = sorted.fold(0.0, (acc, i) => acc + i.grandTotal);

    final List<List<String>> tableData = [];
    for (var i = 0; i < sorted.length; i++) {
      final inv = sorted[i];
      final gstin = inv.customer.gstin.trim().isNotEmpty ? inv.customer.gstin.trim().toUpperCase() : 'Unregistered';
      tableData.add([
        (i + 1).toString(),
        inv.invoiceNumber,
        DateFormatter.format(inv.invoiceDate),
        inv.customer.name.trim(),
        gstin,
        CurrencyFormatter.formatWithoutSymbol(inv.netAmount),
        CurrencyFormatter.formatWithoutSymbol(inv.cgstTotal),
        CurrencyFormatter.formatWithoutSymbol(inv.sgstTotal),
        CurrencyFormatter.formatWithoutSymbol(inv.igstTotal),
        CurrencyFormatter.formatWithoutSymbol(inv.grandTotal),
      ]);
    }

    // Grand Total summary row
    tableData.add([
      'TOTAL',
      '(${sorted.length} Bills)',
      '',
      '',
      '',
      CurrencyFormatter.formatWithoutSymbol(sumTaxable),
      CurrencyFormatter.formatWithoutSymbol(sumCgst),
      CurrencyFormatter.formatWithoutSymbol(sumSgst),
      CurrencyFormatter.formatWithoutSymbol(sumIgst),
      CurrencyFormatter.formatWithoutSymbol(sumTotal),
    ]);

    // Wooden & Parchment palette matching Temporary Bill theme
    const darkWood = PdfColor.fromInt(0xFF2E1A0C);
    const mediumWood = PdfColor.fromInt(0xFF5A321A);
    const amberGold = PdfColor.fromInt(0xFFF0D488);
    const antiqueGold = PdfColor.fromInt(0xFFD9B25F);
    const creamText = PdfColor.fromInt(0xFFF8EFDC);
    const parchmentBg = PdfColor.fromInt(0xFFFBF8F1);
    const zebraBg = PdfColor.fromInt(0xFFF3EADC);
    const gridBorder = PdfColor.fromInt(0xFFC7B397);
    const darkText = PdfColor.fromInt(0xFF2A170B);
    const woodNumber = PdfColor.fromInt(0xFF6B4226);

    pdf.addPage(
      pw.MultiPage(
        pageTheme: pw.PageTheme(
          pageFormat: const PdfPageFormat(841.89, 595.28, marginAll: 22),
          buildBackground: (context) => pw.FullPage(
            ignoreMargins: true,
            child: pw.Container(color: parchmentBg),
          ),
        ),
        header: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            pw.Container(
              padding: const pw.EdgeInsets.all(10),
              decoration: pw.BoxDecoration(
                color: darkWood,
                border: pw.Border.all(color: antiqueGold, width: 1.5),
                borderRadius: const pw.BorderRadius.all(pw.Radius.circular(5)),
              ),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text('SUPRIME SOLUTIONS', style: pw.TextStyle(font: fontBold, fontSize: 15, color: amberGold)),
                      pw.SizedBox(height: 2),
                      pw.Text('Industrial Gaskets, Hydraulics & Industrial Supplies', style: pw.TextStyle(font: fontRegular, fontSize: 8.5, color: antiqueGold)),
                      pw.Text('Mahalaxmi Bole, Beside Yashoda Dairy, Tikrapara, Bilaspur (C.G.) 495001  |  Ph: 9981365878', style: pw.TextStyle(font: fontRegular, fontSize: 8.0, color: creamText)),
                      pw.Text('Company GSTIN: 22FWDPD2626D1Z7  |  State: Chhattisgarh (Code 22)', style: pw.TextStyle(font: fontBold, fontSize: 8.5, color: amberGold)),
                    ],
                  ),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Text('GST SALES REGISTER (FOR CA / AUDIT)', style: pw.TextStyle(font: fontBold, fontSize: 13, color: amberGold)),
                      pw.SizedBox(height: 3),
                      pw.Text('Period: ${DateFormatter.format(fromDate)}  to  ${DateFormatter.format(toDate)}', style: pw.TextStyle(font: fontBold, fontSize: 9.5, color: antiqueGold)),
                      pw.Text('Total Tax Invoices: ${sorted.length} (Excludes Temporary Bills)', style: pw.TextStyle(font: fontRegular, fontSize: 8.5, color: creamText)),
                      pw.Text('Generated On: ${DateFormatter.format(DateTime.now())}', style: pw.TextStyle(font: fontRegular, fontSize: 8.0, color: antiqueGold)),
                    ],
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 8),
          ],
        ),
        footer: (context) => pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text('* Official GSTR-1 Verified Sales Register generated by Suprime Solutions for CA/Audit filing.', style: pw.TextStyle(font: fontRegular, fontSize: 7.5, color: mediumWood)),
            pw.Text('Page ${context.pageNumber} of ${context.pagesCount}', style: pw.TextStyle(font: fontRegular, fontSize: 7.5, color: mediumWood)),
          ],
        ),
        build: (context) => [
          pw.TableHelper.fromTextArray(
            headers: [
              'S.NO.',
              'INVOICE NO.',
              'DATE',
              'PARTY NAME',
              'PARTY GSTIN',
              'TAXABLE (Rs.)',
              'CGST (Rs.)',
              'SGST (Rs.)',
              'IGST (Rs.)',
              'TOTAL (Rs.)',
            ],
            data: tableData,
            headerStyle: pw.TextStyle(font: fontBold, fontSize: 8.0, color: amberGold),
            headerDecoration: const pw.BoxDecoration(color: mediumWood),
            headerAlignment: pw.Alignment.center,
            cellStyle: pw.TextStyle(font: fontRegular, fontSize: 8.0, color: darkText),
            cellAlignments: {
              0: pw.Alignment.center,
              1: pw.Alignment.center,
              2: pw.Alignment.center,
              3: pw.Alignment.centerLeft,
              4: pw.Alignment.center,
              5: pw.Alignment.centerRight,
              6: pw.Alignment.centerRight,
              7: pw.Alignment.centerRight,
              8: pw.Alignment.centerRight,
              9: pw.Alignment.centerRight,
            },
            columnWidths: {
              0: const pw.FixedColumnWidth(30),
              1: const pw.FixedColumnWidth(66),
              2: const pw.FixedColumnWidth(62),
              3: const pw.FlexColumnWidth(3.2),
              4: const pw.FixedColumnWidth(105),
              5: const pw.FixedColumnWidth(78),
              6: const pw.FixedColumnWidth(62),
              7: const pw.FixedColumnWidth(62),
              8: const pw.FixedColumnWidth(52),
              9: const pw.FixedColumnWidth(82),
            },
            rowDecoration: const pw.BoxDecoration(color: PdfColors.white),
            oddRowDecoration: const pw.BoxDecoration(color: zebraBg),
            cellDecoration: (col, data, rowNum) {
              if (rowNum == tableData.length) {
                return const pw.BoxDecoration(color: darkWood);
              }
              final isOdd = (rowNum - 1) % 2 != 0;
              return isOdd ? const pw.BoxDecoration(color: zebraBg) : const pw.BoxDecoration(color: PdfColors.white);
            },
            textStyleBuilder: (col, data, rowNum) {
              if (rowNum == tableData.length) {
                return pw.TextStyle(font: fontBold, fontSize: 8.5, color: amberGold);
              }
              if (col == 0) {
                return pw.TextStyle(font: fontBold, fontSize: 8.0, color: woodNumber);
              }
              if (col == 1 || col == 9) {
                return pw.TextStyle(font: fontBold, fontSize: 8.0, color: darkWood);
              }
              return null;
            },
            border: pw.TableBorder.all(color: gridBorder, width: 0.6),
          ),
        ],
      ),
    );

    return pdf.save();
  }

  static Future<void> shareCombinedBillsPdf(List<InvoiceModel> invoices, DateTime from, DateTime to) async {
    final bytes = await generateCombinedGstBillsPdf(invoices);
    final fromStr = DateFormatter.format(from).replaceAll('/', '-');
    final toStr = DateFormatter.format(to).replaceAll('/', '-');
    final filename = 'Suprime_Solutions_Combined_Bills_${fromStr}_to_${toStr}.pdf';
    await Printing.sharePdf(bytes: bytes, filename: filename);
  }

  static Future<void> shareGstSalesRegisterPdf(List<InvoiceModel> invoices, DateTime from, DateTime to) async {
    final bytes = await generateGstSalesRegisterPdf(invoices, from, to);
    final fromStr = DateFormatter.format(from).replaceAll('/', '-');
    final toStr = DateFormatter.format(to).replaceAll('/', '-');
    final filename = 'Suprime_Solutions_GST_Sales_Register_${fromStr}_to_${toStr}.pdf';
    await Printing.sharePdf(bytes: bytes, filename: filename);
  }

  /// Builds a single full-bleed GST Invoice page on the authentic background template
  static pw.Page buildGstInvoicePage(InvoiceModel invoice, pw.MemoryImage templateImage, pw.Font fontBold) {
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

    return pw.Page(
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
                        top: (itm.description.length > 22) ? (y - 3.5) : y,
                        child: pw.SizedBox(
                          width: 142.0,
                          child: pw.Align(
                            alignment: pw.Alignment.centerLeft,
                            child: pw.Text(
                              itm.description,
                              maxLines: 2,
                              softWrap: true,
                              overflow: pw.TextOverflow.clip,
                              style: pw.TextStyle(
                                font: fontBold,
                                fontSize: 10.5,
                                color: PdfColors.black,
                              ),
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
      );
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
