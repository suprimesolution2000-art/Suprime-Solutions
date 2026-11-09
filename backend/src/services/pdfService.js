const { PDFDocument, rgb, StandardFonts } = require('pdf-lib');
const fs = require('fs');
const path = require('path');

const TEMPLATE_PATH = path.join(__dirname, '../../../assets/invoice-template/master_invoice.pdf');
const COORDS_PATH = path.join(__dirname, '../../../assets/invoice-template/overlay_coordinates.json');
const TEMP_TEMPLATE_PATH = path.join(__dirname, '../../../assets/invoice-template/temporary_bill_template.pdf');

let cachedTemplateBytes = null;
let cachedCoords = null;
let cachedTempTemplateBytes = null;

function loadTemplateData() {
  if (!cachedTemplateBytes) {
    cachedTemplateBytes = fs.readFileSync(TEMPLATE_PATH);
  }
  if (!cachedCoords) {
    cachedCoords = JSON.parse(fs.readFileSync(COORDS_PATH, 'utf8'));
  }
  return { templateBytes: cachedTemplateBytes, coords: cachedCoords };
}

function loadTempTemplateData() {
  if (!cachedTempTemplateBytes) {
    cachedTempTemplateBytes = fs.readFileSync(TEMP_TEMPLATE_PATH);
  }
  return cachedTempTemplateBytes;
}

/**
 * Generate Temporary Bill PDF buffer using the wood-themed template
 * @param {Object} invoice
 */
async function generateTemporaryBillPdf(invoice) {
  const templateBytes = loadTempTemplateData();
  const pdfDoc = await PDFDocument.load(templateBytes);
  const page = pdfDoc.getPages()[0];
  const { height } = page.getSize();

  const font = await pdfDoc.embedFont(StandardFonts.Helvetica);
  const fontBold = await pdfDoc.embedFont(StandardFonts.HelveticaBold);

  function toPdfY(topY) {
    return height - topY;
  }

  // Matching Theme Colors
  const espressoColor = rgb(0.165, 0.086, 0.039); // #2A160A deep rich espresso
  const goldCreamColor = rgb(0.98, 0.93, 0.82);   // #FAF0D1 warm golden cream

  const cust = invoice.customer || {};
  const custName = (cust.name || cust.businessName || 'Customer').toUpperCase();

  // Bill Number (Drawn directly inside the top-right "NO." box above the underline)
  const billNoStr = invoice.sequenceNumber ? String(invoice.sequenceNumber) : (invoice.invoiceNumber || '').replace(/^TEMP-/, '');
  if (billNoStr) {
    page.drawText(billNoStr, {
      x: 468.0,
      y: toPdfY(88.0),
      size: 14.0,
      font: fontBold,
      color: espressoColor,
    });
  }

  // Billed To (Customer Name only, directly above line)
  page.drawText(custName, {
    x: 58.0,
    y: toPdfY(237.0),
    size: 12.0,
    font: fontBold,
    color: espressoColor,
  });

  // Bill Date (ONLY DATE, NO "Date:" prefix, directly above line)
  const formattedDate = invoice.invoiceDate ? new Date(invoice.invoiceDate).toLocaleDateString('en-GB') : '';
  page.drawText(formattedDate, {
    x: 385.5,
    y: toPdfY(237.0),
    size: 12.0,
    font: fontBold,
    color: espressoColor,
  });

  // Table items (5 columns: NO., PRODUCT, QTY., RATE, TOTAL)
  const items = Array.isArray(invoice.items) ? invoice.items.slice(0, 16) : [];
  items.forEach((itm, idx) => {
    const yTop = 338.0 + (idx * 24.62);

    let desc = itm.description || '';
    if (desc.length > 32) {
      desc = desc.substring(0, 30) + '...';
    }
    // Product
    page.drawText(desc, {
      x: 86.0,
      y: toPdfY(yTop),
      size: 9.5,
      font: font,
      color: espressoColor,
    });

    // Qty
    const qtyStr = itm.quantity ? `${itm.quantity} ${itm.unit || 'PCS'}` : '';
    const qtyWidth = font.widthOfTextAtSize(qtyStr, 9.5);
    page.drawText(qtyStr, {
      x: 317.0 - (qtyWidth / 2),
      y: toPdfY(yTop),
      size: 9.5,
      font: font,
      color: espressoColor,
    });

    // Rate
    const rateStr = itm.rate ? Number(itm.rate).toFixed(2) : '';
    const rateWidth = font.widthOfTextAtSize(rateStr, 9.5);
    page.drawText(rateStr, {
      x: 444.0 - rateWidth,
      y: toPdfY(yTop),
      size: 9.5,
      font: font,
      color: espressoColor,
    });

    // Total Amount
    const totStr = Number(itm.totalAmount || (itm.quantity * itm.rate) || 0).toFixed(2);
    const totWidth = fontBold.widthOfTextAtSize(totStr, 10.0);
    page.drawText(totStr, {
      x: 546.0 - totWidth,
      y: toPdfY(yTop),
      size: 10.0,
      font: fontBold,
      color: espressoColor,
    });
  });

  // Grand Total
  const totalStr = Number(invoice.grandTotal || 0).toFixed(2);
  const totWidth = fontBold.widthOfTextAtSize(totalStr, 14.5);
  page.drawText(totalStr, {
    x: 535.0 - totWidth,
    y: toPdfY(762.0),
    size: 14.5,
    font: fontBold,
    color: goldCreamColor,
  });

  const pdfBytes = await pdfDoc.save();
  return Buffer.from(pdfBytes);
}

/**
 * Generate PDF buffer for an invoice overlaid on the original scanned template
 * @param {Object} invoice
 */
async function generateGstInvoicePdf(invoice) {
  const { templateBytes, coords } = loadTemplateData();

  const pdfDoc = await PDFDocument.load(templateBytes);
  const pages = pdfDoc.getPages();
  const page = pages[0];
  const { width, height } = page.getSize();

  const font = await pdfDoc.embedFont(StandardFonts.Helvetica);
  const fontBold = await pdfDoc.embedFont(StandardFonts.HelveticaBold);

  // In pdf-lib, (0,0) is BOTTOM-LEFT!
  // In PyMuPDF / standard image coordinates, (0,0) is TOP-LEFT!
  // Conversion:
  // x_pdf = (px_x / 2296) * width
  // y_pdf = height - ((px_y / 2809) * height)
  function toPdfX(pxX) {
    return (pxX / coords.pageSize.sourcePixelWidth) * width;
  }

  function toPdfY(pxY) {
    return height - ((pxY / coords.pageSize.sourcePixelHeight) * height);
  }

  const textColor = rgb(0.05, 0.05, 0.05);

  function drawText(text, pxX, pxY, size = 10, isBold = false) {
    if (!text) return;
    const f = isBold ? fontBold : font;
    page.drawText(String(text), {
      x: toPdfX(pxX),
      y: toPdfY(pxY),
      size: size,
      font: f,
      color: textColor
    });
  }

  function drawRightText(text, rightPxX, pxY, size = 10, isBold = false) {
    if (!text) return;
    const f = isBold ? fontBold : font;
    const str = String(text);
    const textWidth = f.widthOfTextAtSize(str, size);
    page.drawText(str, {
      x: toPdfX(rightPxX) - textWidth,
      y: toPdfY(pxY),
      size: size,
      font: f,
      color: textColor
    });
  }

  function drawCenteredText(text, centerPxX, pxY, size = 10, isBold = false) {
    if (!text) return;
    const f = isBold ? fontBold : font;
    const str = String(text);
    const textWidth = f.widthOfTextAtSize(str, size);
    page.drawText(str, {
      x: toPdfX(centerPxX) - (textWidth / 2),
      y: toPdfY(pxY),
      size: size,
      font: f,
      color: textColor
    });
  }

  // 1. Header Details (Enlarged & Bold for High Visibility)
  drawText(invoice.invoiceNumber, coords.fields.invoiceNo.pxX, coords.fields.invoiceNo.pxY, 18, true);

  const formattedDate = invoice.invoiceDate ? new Date(invoice.invoiceDate).toLocaleDateString('en-GB') : '';
  drawText(formattedDate, coords.fields.invoiceDate.pxX, coords.fields.invoiceDate.pxY, 14, true);

  // 2. Customer Details (Enlarged & Bold)
  const cust = invoice.customer || {};
  drawText(cust.name || cust.businessName || '', coords.fields.customerName.pxX, coords.fields.customerName.pxY, 16, true);
  drawText(cust.address || '', coords.fields.customerAddress.pxX, coords.fields.customerAddress.pxY, 13.5, false);
  drawText(cust.state || 'Chhattisgarh', coords.fields.state.pxX, coords.fields.state.pxY, 14, true);
  drawText(cust.stateCode || '22', coords.fields.stateCode.pxX, coords.fields.stateCode.pxY, 14, true);
  drawText(cust.gstin || '', coords.fields.gstin.pxX, coords.fields.gstin.pxY, 15.5, true);

  // PO & Challan
  if (invoice.poNumber) drawText(invoice.poNumber, coords.fields.poNo.pxX, coords.fields.poNo.pxY, 13.5, true);
  if (invoice.poDate) drawText(new Date(invoice.poDate).toLocaleDateString('en-GB'), coords.fields.poDate.pxX, coords.fields.poDate.pxY, 13.5, true);
  if (invoice.challanNumber) drawText(invoice.challanNumber, coords.fields.challanNo.pxX, coords.fields.challanNo.pxY, 13.5, true);
  if (invoice.challanDate) drawText(new Date(invoice.challanDate).toLocaleDateString('en-GB'), coords.fields.challanDate.pxX, coords.fields.challanDate.pxY, 13.5, true);

  // 3. Table Rows (Enlarged & High-Legibility)
  const items = invoice.items || [];
  const startY = coords.table.startY;
  const rowGap = coords.table.rowGap;

  items.slice(0, coords.table.maxRowsPerPage).forEach((item, idx) => {
    const y = startY + (idx * rowGap);
    const amountVal = item.taxableValue || item.totalAmount || 0;
    const rupees = Math.floor(amountVal);
    const paise = Math.round((amountVal - rupees) * 100);

    drawCenteredText(item.sno || idx + 1, coords.table.columns.sno.centerPx, y, 14, true);
    const desc = item.description || '';
    if (desc.length > 25) {
      const splitIdx = desc.lastIndexOf(' ', 25);
      const line1 = splitIdx !== -1 ? desc.substring(0, splitIdx) : desc.substring(0, 25);
      const line2 = splitIdx !== -1 ? desc.substring(splitIdx + 1) : desc.substring(25);
      drawText(line1, coords.table.columns.description.leftPx, y - 10, 13, true);
      drawText(line2, coords.table.columns.description.leftPx, y + 12, 13, true);
    } else {
      drawText(desc, coords.table.columns.description.leftPx, y, 13, true);
    }
    drawCenteredText(item.hsnCode || '', coords.table.columns.hsn.centerPx, y, 13, true);
    drawCenteredText(`${item.quantity} ${item.unit || 'PCS'}`, coords.table.columns.qty.centerPx, y, 13.5, true);
    drawRightText(Number(item.rate).toFixed(2), coords.table.columns.rate.rightPx, y, 13.5, true);
    drawRightText(String(rupees), coords.table.columns.amountRs.rightPx, y, 14, true);
    drawCenteredText(String(paise).padStart(2, '0'), coords.table.columns.amountP.centerPx, y, 13.5, true);
  });

  // 4. Summary & Tax Rows
  function splitRupeesPaise(val) {
    const v = Number(val) || 0;
    const sign = v < 0 ? '-' : '';
    const absV = Math.abs(v);
    const r = Math.floor(absV);
    const p = Math.round((absV - r) * 100);
    return { rs: (sign && r === 0 ? '-0' : sign + r), p: String(p).padStart(2, '0') };
  }

  // Net Amount
  const netParts = splitRupeesPaise(invoice.netAmount);
  drawRightText(netParts.rs, coords.summary.netAmount.rsRightPx, coords.summary.netAmount.y, 14.5, true);
  drawCenteredText(netParts.p, coords.summary.netAmount.pCenterPx, coords.summary.netAmount.y, 13.5, true);

  // SGST & CGST or IGST
  if (!invoice.isInterState) {
    const sgstRate = ((invoice.items && invoice.items[0] && invoice.items[0].gstRate) || 18) / 2;
    drawCenteredText(sgstRate.toFixed(1), coords.summary.sgst.rateCenterPx, coords.summary.sgst.y, 13.5, true);
    const sgstParts = splitRupeesPaise(invoice.sgstTotal);
    drawRightText(sgstParts.rs, coords.summary.sgst.rsRightPx, coords.summary.sgst.y, 14, true);
    drawCenteredText(sgstParts.p, coords.summary.sgst.pCenterPx, coords.summary.sgst.y, 13.5, true);

    drawCenteredText(sgstRate.toFixed(1), coords.summary.cgst.rateCenterPx, coords.summary.cgst.y, 13.5, true);
    const cgstParts = splitRupeesPaise(invoice.cgstTotal);
    drawRightText(cgstParts.rs, coords.summary.cgst.rsRightPx, coords.summary.cgst.y, 14, true);
    drawCenteredText(cgstParts.p, coords.summary.cgst.pCenterPx, coords.summary.cgst.y, 13.5, true);

    // IGST 0
    drawCenteredText('0.0', coords.summary.igst.rateCenterPx, coords.summary.igst.y, 13.5, true);
    drawRightText('0', coords.summary.igst.rsRightPx, coords.summary.igst.y, 14, true);
    drawCenteredText('00', coords.summary.igst.pCenterPx, coords.summary.igst.y, 13.5, true);
  } else {
    const igstRate = (invoice.items && invoice.items[0] && invoice.items[0].gstRate) || 18;
    drawCenteredText('0.0', coords.summary.sgst.rateCenterPx, coords.summary.sgst.y, 13.5, true);
    drawRightText('0', coords.summary.sgst.rsRightPx, coords.summary.sgst.y, 14, true);
    drawCenteredText('00', coords.summary.sgst.pCenterPx, coords.summary.sgst.y, 13.5, true);

    drawCenteredText('0.0', coords.summary.cgst.rateCenterPx, coords.summary.cgst.y, 13.5, true);
    drawRightText('0', coords.summary.cgst.rsRightPx, coords.summary.cgst.y, 14, true);
    drawCenteredText('00', coords.summary.cgst.pCenterPx, coords.summary.cgst.y, 13.5, true);

    drawCenteredText(igstRate.toFixed(1), coords.summary.igst.rateCenterPx, coords.summary.igst.y, 13.5, true);
    const igstParts = splitRupeesPaise(invoice.igstTotal);
    drawRightText(igstParts.rs, coords.summary.igst.rsRightPx, coords.summary.igst.y, 14, true);
    drawCenteredText(igstParts.p, coords.summary.igst.pCenterPx, coords.summary.igst.y, 13.5, true);
  }

  // Round off
  const roundParts = splitRupeesPaise(invoice.roundOff);
  drawRightText(roundParts.rs, coords.summary.roundOff.rsRightPx, coords.summary.roundOff.y, 13.5, true);
  drawCenteredText(roundParts.p, coords.summary.roundOff.pCenterPx, coords.summary.roundOff.y, 13.5, true);

  // Grand Total (Extra Large & Bold for Maximum Readability)
  const totalParts = splitRupeesPaise(invoice.grandTotal);
  drawRightText(totalParts.rs, coords.summary.totalAmount.rsRightPx, coords.summary.totalAmount.y, 18, true);
  drawCenteredText(totalParts.p, coords.summary.totalAmount.pCenterPx, coords.summary.totalAmount.y, 16, true);

  // Amount in words
  drawText(invoice.amountInWords || '', coords.fields.amountInWords.pxX, coords.fields.amountInWords.pxY, 13.5, true);

  const pdfBytes = await pdfDoc.save();
  return Buffer.from(pdfBytes);
}

/**
 * Generate Excel-Style GSTR-1 Sales Register Statement PDF for CA / Audit
 */
async function generateGstSalesRegisterPdf(invoices = [], fromDate = new Date(), toDate = new Date()) {
  const pdfDoc = await PDFDocument.create();
  const page = pdfDoc.addPage([841.89, 595.28]); // A4 Landscape
  const { width, height } = page.getSize();
  const font = await pdfDoc.embedFont(StandardFonts.Helvetica);
  const fontBold = await pdfDoc.embedFont(StandardFonts.HelveticaBold);

  // Exact Wooden & Parchment palette matching Temporary Bill theme
  const darkWood = rgb(46 / 255, 26 / 255, 12 / 255);       // #2E1A0C
  const mediumWood = rgb(90 / 255, 50 / 255, 26 / 255);     // #5A321A
  const lightGold = rgb(240 / 255, 212 / 255, 136 / 255);   // #F0D488
  const antiqueGold = rgb(217 / 255, 178 / 255, 95 / 255);  // #D9B25F
  const creamText = rgb(248 / 255, 239 / 255, 220 / 255);   // #F8EFDC
  const parchmentBg = rgb(251 / 255, 248 / 255, 241 / 255); // #FBF8F1
  const zebraBg = rgb(243 / 255, 234 / 255, 220 / 255);     // #F3EADC
  const gridBorder = rgb(191 / 255, 166 / 255, 136 / 255);  // #BFA688
  const darkText = rgb(42 / 255, 23 / 255, 11 / 255);       // #2A170B

  const marginX = 26.0;
  const startY = 22.0;

  // 1. Warm Parchment Base Background
  page.drawRectangle({
    x: 0,
    y: 0,
    width: width,
    height: height,
    color: parchmentBg
  });

  // Perimeter Frame in wood tone
  page.drawRectangle({
    x: 10,
    y: 10,
    width: width - 20,
    height: height - 20,
    borderColor: gridBorder,
    borderWidth: 1.0
  });

  // 2. Header Box in Rich Dark Wood
  const headerH = 80.0;
  page.drawRectangle({
    x: marginX,
    y: height - (startY + headerH),
    width: width - (marginX * 2),
    height: headerH,
    color: darkWood,
    borderColor: antiqueGold,
    borderWidth: 1.5
  });

  page.drawRectangle({
    x: marginX,
    y: height - (startY + 4),
    width: width - (marginX * 2),
    height: 3,
    color: antiqueGold
  });

  page.drawText('SUPRIME SOLUTIONS', {
    x: marginX + 16,
    y: height - (startY + 24),
    size: 16,
    font: fontBold,
    color: lightGold
  });

  page.drawText('Industrial Gaskets, Hydraulics & Industrial Supplies', {
    x: marginX + 16,
    y: height - (startY + 39),
    size: 8.5,
    font: font,
    color: antiqueGold
  });

  page.drawText('Mahalaxmi Bole, Beside Yashoda Dairy, Tikrapara, Bilaspur (C.G.) 495001 | Ph: 9981365878', {
    x: marginX + 16,
    y: height - (startY + 52),
    size: 8.0,
    font: font,
    color: creamText
  });

  page.drawText('Company GSTIN: 22FWDPD2626D1Z7 | State: Chhattisgarh (Code 22)', {
    x: marginX + 16,
    y: height - (startY + 67),
    size: 8.5,
    font: fontBold,
    color: lightGold
  });

  // Right Side Header
  const titleText = 'GST SALES REGISTER (FOR CA / AUDIT)';
  const titleW = fontBold.widthOfTextAtSize(titleText, 12.5);
  page.drawText(titleText, {
    x: width - marginX - titleW - 16,
    y: height - (startY + 24),
    size: 12.5,
    font: fontBold,
    color: lightGold
  });

  const fromStr = fromDate ? new Date(fromDate).toLocaleDateString('en-GB') : '';
  const toStr = toDate ? new Date(toDate).toLocaleDateString('en-GB') : '';
  const periodText = `Period: ${fromStr} To ${toStr}`;
  const periodW = fontBold.widthOfTextAtSize(periodText, 9.5);
  page.drawText(periodText, {
    x: width - marginX - periodW - 16,
    y: height - (startY + 42),
    size: 9.5,
    font: fontBold,
    color: antiqueGold
  });

  const countText = `Official Tax Invoices: ${invoices.length} (Temporary Bills Excluded)`;
  const countW = font.widthOfTextAtSize(countText, 8.5);
  page.drawText(countText, {
    x: width - marginX - countW - 16,
    y: height - (startY + 56),
    size: 8.5,
    font: font,
    color: creamText
  });

  const genText = `Generated: ${new Date().toLocaleDateString('en-GB')}`;
  const genW = font.widthOfTextAtSize(genText, 7.5);
  page.drawText(genText, {
    x: width - marginX - genW - 16,
    y: height - (startY + 69),
    size: 7.5,
    font: font,
    color: antiqueGold
  });

  // Table Columns
  const cols = [
    { name: 'S.NO.', w: 32, align: 'center' },
    { name: 'INVOICE NO.', w: 68, align: 'center' },
    { name: 'DATE', w: 64, align: 'center' },
    { name: 'PARTY NAME', w: 184, align: 'left' },
    { name: 'PARTY GSTIN', w: 105, align: 'center' },
    { name: 'TAXABLE (Rs.)', w: 78, align: 'right' },
    { name: 'CGST (Rs.)', w: 62, align: 'right' },
    { name: 'SGST (Rs.)', w: 62, align: 'right' },
    { name: 'IGST (Rs.)', w: 50, align: 'right' },
    { name: 'TOTAL (Rs.)', w: 84.89, align: 'right' }
  ];

  const tblY = startY + 92.0;
  const hdrH = 24.0;

  // Draw Table Header (Medium Wood with Gold accent border)
  page.drawRectangle({
    x: marginX,
    y: height - (tblY + hdrH),
    width: width - (marginX * 2),
    height: hdrH,
    color: mediumWood,
    borderColor: antiqueGold,
    borderWidth: 1.0
  });

  let currX = marginX;
  for (const c of cols) {
    const textW = fontBold.widthOfTextAtSize(c.name, 8.0);
    let xPos = currX + 6;
    if (c.align === 'center') xPos = currX + (c.w - textW) / 2;
    if (c.align === 'right') xPos = currX + c.w - textW - 6;

    page.drawText(c.name, {
      x: xPos,
      y: height - (tblY + 16),
      size: 8.0,
      font: fontBold,
      color: lightGold
    });
    currX += c.w;
  }

  // Draw Table Rows
  let rowY = tblY + hdrH;
  const rowH = 22.0;

  let sumTaxable = 0, sumCgst = 0, sumSgst = 0, sumIgst = 0, sumTotal = 0;

  invoices.forEach((inv, idx) => {
    const isOdd = idx % 2 === 1;
    const rowColor = isOdd ? zebraBg : rgb(1, 1, 1);

    page.drawRectangle({
      x: marginX,
      y: height - (rowY + rowH),
      width: width - (marginX * 2),
      height: rowH,
      color: rowColor,
      borderColor: gridBorder,
      borderWidth: 0.5
    });

    const taxable = inv.netAmount || 0;
    const cgst = inv.cgstTotal || 0;
    const sgst = inv.sgstTotal || 0;
    const igst = inv.igstTotal || 0;
    const total = inv.grandTotal || 0;

    sumTaxable += taxable;
    sumCgst += cgst;
    sumSgst += sgst;
    sumIgst += igst;
    sumTotal += total;

    const rowData = [
      String(idx + 1),
      String(inv.invoiceNumber || ''),
      inv.invoiceDate ? new Date(inv.invoiceDate).toLocaleDateString('en-GB') : '',
      String(inv.customer ? (inv.customer.name || '') : ''),
      String(inv.customer && inv.customer.gstin ? inv.customer.gstin : 'Unregistered'),
      taxable.toLocaleString('en-IN', { minimumFractionDigits: 2 }),
      cgst.toLocaleString('en-IN', { minimumFractionDigits: 2 }),
      sgst.toLocaleString('en-IN', { minimumFractionDigits: 2 }),
      igst.toLocaleString('en-IN', { minimumFractionDigits: 2 }),
      total.toLocaleString('en-IN', { minimumFractionDigits: 2 })
    ];

    let cellX = marginX;
    cols.forEach((c, colIdx) => {
      let val = rowData[colIdx];
      if (colIdx === 3 && val.length > 27) val = val.substring(0, 25) + '..';

      const isBold = colIdx === 0 || colIdx === 1 || colIdx === 9;
      const f = isBold ? fontBold : font;
      const textW = f.widthOfTextAtSize(val, 8.0);
      let xPos = cellX + 6;
      if (c.align === 'center') xPos = cellX + (c.w - textW) / 2;
      if (c.align === 'right') xPos = cellX + c.w - textW - 6;

      let textColor = darkText;
      if (colIdx === 0) textColor = mediumWood;
      if (colIdx === 1) textColor = darkWood;
      if (colIdx === 9) textColor = darkWood;

      page.drawText(val, {
        x: xPos,
        y: height - (rowY + 15),
        size: 8.0,
        font: f,
        color: textColor
      });
      cellX += c.w;
    });

    rowY += rowH;
  });

  // Grand Total Summary Row (Deep Walnut with Gold Numbers)
  const totH = 26.0;
  page.drawRectangle({
    x: marginX,
    y: height - (rowY + totH),
    width: width - (marginX * 2),
    height: totH,
    color: darkWood,
    borderColor: antiqueGold,
    borderWidth: 1.2
  });

  page.drawText(`GRAND TOTAL (${invoices.length} TAX INVOICES)`, {
    x: marginX + 14,
    y: height - (rowY + 17),
    size: 9.0,
    font: fontBold,
    color: lightGold
  });

  const totCols = cols.slice(5);
  const totVals = [
    sumTaxable.toLocaleString('en-IN', { minimumFractionDigits: 2 }),
    sumCgst.toLocaleString('en-IN', { minimumFractionDigits: 2 }),
    sumSgst.toLocaleString('en-IN', { minimumFractionDigits: 2 }),
    sumIgst.toLocaleString('en-IN', { minimumFractionDigits: 2 }),
    sumTotal.toLocaleString('en-IN', { minimumFractionDigits: 2 })
  ];

  let totX = marginX + cols.slice(0, 5).reduce((acc, c) => acc + c.w, 0);
  totCols.forEach((c, idx) => {
    const val = totVals[idx];
    const textW = fontBold.widthOfTextAtSize(val, 9.0);
    const xPos = totX + c.w - textW - 6;

    page.drawText(val, {
      x: xPos,
      y: height - (rowY + 17),
      size: 9.0,
      font: fontBold,
      color: lightGold
    });
    totX += c.w;
  });

  const pdfBytes = await pdfDoc.save();
  return Buffer.from(pdfBytes);
}

async function generateInvoicePdf(invoice) {
  if (invoice && invoice.invoiceType === 'temporary') {
    return generateTemporaryBillPdf(invoice);
  }
  return generateGstInvoicePdf(invoice);
}

module.exports = {
  generateInvoicePdf,
  generateGstInvoicePdf,
  generateTemporaryBillPdf,
  generateGstSalesRegisterPdf
};
