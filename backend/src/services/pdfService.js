const { PDFDocument, rgb, StandardFonts } = require('pdf-lib');
const fs = require('fs');
const path = require('path');

const TEMPLATE_PATH = path.join(__dirname, '../../../assets/invoice-template/master_invoice.pdf');
const COORDS_PATH = path.join(__dirname, '../../../assets/invoice-template/overlay_coordinates.json');

/**
 * Generate PDF buffer for an invoice overlaid on the original scanned template
 * @param {Object} invoice
 */
async function generateInvoicePdf(invoice) {
  const templateBytes = fs.readFileSync(TEMPLATE_PATH);
  const coords = JSON.parse(fs.readFileSync(COORDS_PATH, 'utf8'));

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

  // 1. Header Details
  drawText(invoice.invoiceNumber, coords.fields.invoiceNo.pxX, coords.fields.invoiceNo.pxY, 11, true);

  const formattedDate = invoice.invoiceDate ? new Date(invoice.invoiceDate).toLocaleDateString('en-GB') : '';
  drawText(formattedDate, coords.fields.invoiceDate.pxX, coords.fields.invoiceDate.pxY, 10);

  // 2. Customer Details
  const cust = invoice.customer || {};
  drawText(cust.name || cust.businessName || '', coords.fields.customerName.pxX, coords.fields.customerName.pxY, 10.5, true);
  drawText(cust.address || '', coords.fields.customerAddress.pxX, coords.fields.customerAddress.pxY, 9.5);
  drawText(cust.state || 'Chhattisgarh', coords.fields.state.pxX, coords.fields.state.pxY, 10);
  drawText(cust.stateCode || '22', coords.fields.stateCode.pxX, coords.fields.stateCode.pxY, 10);
  drawText(cust.gstin || '', coords.fields.gstin.pxX, coords.fields.gstin.pxY, 10.5, true);

  // PO & Challan
  if (invoice.poNumber) drawText(invoice.poNumber, coords.fields.poNo.pxX, coords.fields.poNo.pxY, 9.5);
  if (invoice.poDate) drawText(new Date(invoice.poDate).toLocaleDateString('en-GB'), coords.fields.poDate.pxX, coords.fields.poDate.pxY, 9.5);
  if (invoice.challanNumber) drawText(invoice.challanNumber, coords.fields.challanNo.pxX, coords.fields.challanNo.pxY, 9.5);
  if (invoice.challanDate) drawText(new Date(invoice.challanDate).toLocaleDateString('en-GB'), coords.fields.challanDate.pxX, coords.fields.challanDate.pxY, 9.5);

  // 3. Table Rows
  const items = invoice.items || [];
  const startY = coords.table.startY;
  const rowGap = coords.table.rowGap;

  items.slice(0, coords.table.maxRowsPerPage).forEach((item, idx) => {
    const y = startY + (idx * rowGap);
    const amountVal = item.taxableValue || item.totalAmount || 0;
    const rupees = Math.floor(amountVal);
    const paise = Math.round((amountVal - rupees) * 100);

    drawCenteredText(item.sno || idx + 1, coords.table.columns.sno.centerPx, y, 9.5);
    drawText(item.description || '', coords.table.columns.description.leftPx, y, 9.5);
    drawCenteredText(item.hsnCode || '', coords.table.columns.hsn.centerPx, y, 9.5);
    drawCenteredText(`${item.quantity} ${item.unit || 'PCS'}`, coords.table.columns.qty.centerPx, y, 9.5);
    drawRightText(Number(item.rate).toFixed(2), coords.table.columns.rate.rightPx, y, 9.5);
    drawRightText(String(rupees), coords.table.columns.amountRs.rightPx, y, 9.5);
    drawCenteredText(String(paise).padStart(2, '0'), coords.table.columns.amountP.centerPx, y, 9.5);
  });

  // 4. Summary & Tax Rows
  function splitRupeesPaise(val) {
    const v = Number(val) || 0;
    const r = Math.floor(v);
    const p = Math.round((v - r) * 100);
    return { rs: String(r), p: String(p).padStart(2, '0') };
  }

  // Net Amount
  const netParts = splitRupeesPaise(invoice.netAmount);
  drawRightText(netParts.rs, coords.summary.netAmount.rsRightPx, coords.summary.netAmount.y, 9.5);
  drawCenteredText(netParts.p, coords.summary.netAmount.pCenterPx, coords.summary.netAmount.y, 9.5);

  // SGST & CGST or IGST
  if (!invoice.isInterState) {
    const sgstRate = ((invoice.items && invoice.items[0] && invoice.items[0].gstRate) || 18) / 2;
    drawCenteredText(sgstRate.toFixed(1), coords.summary.sgst.rateCenterPx, coords.summary.sgst.y, 9);
    const sgstParts = splitRupeesPaise(invoice.sgstTotal);
    drawRightText(sgstParts.rs, coords.summary.sgst.rsRightPx, coords.summary.sgst.y, 9.5);
    drawCenteredText(sgstParts.p, coords.summary.sgst.pCenterPx, coords.summary.sgst.y, 9.5);

    drawCenteredText(sgstRate.toFixed(1), coords.summary.cgst.rateCenterPx, coords.summary.cgst.y, 9);
    const cgstParts = splitRupeesPaise(invoice.cgstTotal);
    drawRightText(cgstParts.rs, coords.summary.cgst.rsRightPx, coords.summary.cgst.y, 9.5);
    drawCenteredText(cgstParts.p, coords.summary.cgst.pCenterPx, coords.summary.cgst.y, 9.5);

    // IGST 0
    drawCenteredText('0.0', coords.summary.igst.rateCenterPx, coords.summary.igst.y, 9);
    drawRightText('0', coords.summary.igst.rsRightPx, coords.summary.igst.y, 9.5);
    drawCenteredText('00', coords.summary.igst.pCenterPx, coords.summary.igst.y, 9.5);
  } else {
    const igstRate = (invoice.items && invoice.items[0] && invoice.items[0].gstRate) || 18;
    drawCenteredText('0.0', coords.summary.sgst.rateCenterPx, coords.summary.sgst.y, 9);
    drawRightText('0', coords.summary.sgst.rsRightPx, coords.summary.sgst.y, 9.5);
    drawCenteredText('00', coords.summary.sgst.pCenterPx, coords.summary.sgst.y, 9.5);

    drawCenteredText('0.0', coords.summary.cgst.rateCenterPx, coords.summary.cgst.y, 9);
    drawRightText('0', coords.summary.cgst.rsRightPx, coords.summary.cgst.y, 9.5);
    drawCenteredText('00', coords.summary.cgst.pCenterPx, coords.summary.cgst.y, 9.5);

    drawCenteredText(igstRate.toFixed(1), coords.summary.igst.rateCenterPx, coords.summary.igst.y, 9);
    const igstParts = splitRupeesPaise(invoice.igstTotal);
    drawRightText(igstParts.rs, coords.summary.igst.rsRightPx, coords.summary.igst.y, 9.5);
    drawCenteredText(igstParts.p, coords.summary.igst.pCenterPx, coords.summary.igst.y, 9.5);
  }

  // Round off
  const roundParts = splitRupeesPaise(invoice.roundOff);
  drawRightText(roundParts.rs, coords.summary.roundOff.rsRightPx, coords.summary.roundOff.y, 9.5);
  drawCenteredText(roundParts.p, coords.summary.roundOff.pCenterPx, coords.summary.roundOff.y, 9.5);

  // Grand Total
  const totalParts = splitRupeesPaise(invoice.grandTotal);
  drawRightText(totalParts.rs, coords.summary.totalAmount.rsRightPx, coords.summary.totalAmount.y, 11, true);
  drawCenteredText(totalParts.p, coords.summary.totalAmount.pCenterPx, coords.summary.totalAmount.y, 11, true);

  // Amount in words
  drawText(invoice.amountInWords || '', coords.fields.amountInWords.pxX, coords.fields.amountInWords.pxY, 9.5);

  const pdfBytes = await pdfDoc.save();
  return Buffer.from(pdfBytes);
}

module.exports = {
  generateInvoicePdf
};
