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
  const custAddr = (cust.address || '').trim();

  // Billed To
  if (custAddr) {
    page.drawText(custName, {
      x: 58.0,
      y: toPdfY(221.0),
      size: 11.5,
      font: fontBold,
      color: espressoColor,
    });
    page.drawText(custAddr, {
      x: 58.0,
      y: toPdfY(236.0),
      size: 9.5,
      font: font,
      color: espressoColor,
    });
  } else {
    page.drawText(custName, {
      x: 58.0,
      y: toPdfY(228.0),
      size: 12.0,
      font: fontBold,
      color: espressoColor,
    });
  }

  // Bill Date & Bill No
  const formattedDate = invoice.invoiceDate ? new Date(invoice.invoiceDate).toLocaleDateString('en-GB') : '';
  page.drawText(`Bill No: ${invoice.invoiceNumber || ''}`, {
    x: 385.5,
    y: toPdfY(221.0),
    size: 11.0,
    font: fontBold,
    color: espressoColor,
  });
  page.drawText(`Date: ${formattedDate}`, {
    x: 385.5,
    y: toPdfY(236.0),
    size: 10.5,
    font: fontBold,
    color: espressoColor,
  });

  // Table items (Up to 16 rows)
  const items = Array.isArray(invoice.items) ? invoice.items.slice(0, 16) : [];
  items.forEach((itm, idx) => {
    const yTop = 337.5 + (idx * 24.62);

    let displayDesc = itm.description || '';
    if (itm.quantity && itm.rate) {
      displayDesc += ` (${itm.quantity} ${itm.unit || 'PCS'} @ ${Number(itm.rate).toFixed(2)})`;
    }

    if (displayDesc.length > 55) {
      displayDesc = displayDesc.substring(0, 52) + '...';
    }

    page.drawText(displayDesc, {
      x: 86.0,
      y: toPdfY(yTop),
      size: 10.0,
      font: font,
      color: espressoColor,
    });

    const amt = Number(itm.totalAmount || (itm.quantity * itm.rate) || 0).toFixed(2);
    const amtWidth = fontBold.widthOfTextAtSize(amt, 10.5);
    page.drawText(amt, {
      x: 538.0 - amtWidth,
      y: toPdfY(yTop),
      size: 10.5,
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

async function generateInvoicePdf(invoice) {
  if (invoice && invoice.invoiceType === 'temporary') {
    return generateTemporaryBillPdf(invoice);
  }
  return generateGstInvoicePdf(invoice);
}

module.exports = {
  generateInvoicePdf,
  generateGstInvoicePdf,
  generateTemporaryBillPdf
};
