/**
 * GST Calculation & Indian Currency Words Service
 * Handles accurate decimal & paise calculations, intra-state vs inter-state rules,
 * round-off calculations, and amount in words.
 */

// Number to Indian Words converter
function numberToIndianWords(amount) {
  if (amount === 0) return 'Rupees Zero Only';
  if (amount < 0) return 'Minus ' + numberToIndianWords(Math.abs(amount));

  const units = ['', 'One', 'Two', 'Three', 'Four', 'Five', 'Six', 'Seven', 'Eight', 'Nine',
    'Ten', 'Eleven', 'Twelve', 'Thirteen', 'Fourteen', 'Fifteen', 'Sixteen', 'Seventeen', 'Eighteen', 'Nineteen'];
  const tens = ['', '', 'Twenty', 'Thirty', 'Forty', 'Fifty', 'Sixty', 'Seventy', 'Eighty', 'Ninety'];

  function convertTwoDigits(n) {
    if (n < 20) return units[n];
    const unit = n % 10;
    return tens[Math.floor(n / 10)] + (unit ? ' ' + units[unit] : '');
  }

  function convertThreeDigits(n) {
    let str = '';
    const hundred = Math.floor(n / 100);
    const rest = n % 100;
    if (hundred) str += units[hundred] + ' Hundred';
    if (rest) str += (str ? ' ' : '') + convertTwoDigits(rest);
    return str;
  }

  const rounded = Math.round(amount * 100) / 100;
  const rupees = Math.floor(rounded);
  const paise = Math.round((rounded - rupees) * 100);

  let words = '';

  // Crores (>= 1,00,00,000)
  const crores = Math.floor(rupees / 10000000);
  let remainder = rupees % 10000000;

  // Lakhs (>= 1,00,000)
  const lakhs = Math.floor(remainder / 100000);
  remainder %= 100000;

  // Thousands (>= 1,000)
  const thousands = Math.floor(remainder / 1000);
  remainder %= 1000;

  if (crores > 0) words += convertThreeDigits(crores) + ' Crore ';
  if (lakhs > 0) words += convertThreeDigits(lakhs) + ' Lakh ';
  if (thousands > 0) words += convertThreeDigits(thousands) + ' Thousand ';
  if (remainder > 0) words += convertThreeDigits(remainder) + ' ';

  words = words.trim();
  let result = words ? 'Rupees ' + words : 'Rupees Zero';

  if (paise > 0) {
    result += ' and ' + convertTwoDigits(paise) + ' Paise';
  }

  return result + ' Only';
}

/**
 * Calculate complete invoice financials
 * @param {Array} items - [{ sno, description, hsnCode, quantity, rate, discount, gstRate, unit }]
 * @param {string} customerStateCode - e.g. "22" for Chhattisgarh
 * @param {string} businessStateCode - defaults to "22"
 */
function calculateInvoiceFinancials(items, customerStateCode = '22', businessStateCode = '22', isTemporary = false) {
  const isInterState = String(customerStateCode).trim() !== String(businessStateCode).trim();

  let netAmount = 0;
  let cgstTotal = 0;
  let sgstTotal = 0;
  let igstTotal = 0;

  const calculatedItems = items.map((item, idx) => {
    const qty = Number(item.quantity) || 0;
    const rate = Number(item.rate) || 0;
    const discount = Number(item.discount) || 0;
    const gstRate = isTemporary ? 0 : Number(item.gstRate !== undefined ? item.gstRate : (item.gst_rate !== undefined ? item.gst_rate : 18.0));

    const grossValue = Math.round(qty * rate * 100) / 100;
    const taxableValue = Math.max(0, Math.round((grossValue - discount) * 100) / 100);

    let cgstRate = 0, cgstAmount = 0;
    let sgstRate = 0, sgstAmount = 0;
    let igstRate = 0, igstAmount = 0;

    if (!isTemporary) {
      if (isInterState) {
        igstRate = gstRate;
        igstAmount = Math.round((taxableValue * (igstRate / 100)) * 100) / 100;
      } else {
        cgstRate = Math.round((gstRate / 2) * 100) / 100;
        sgstRate = Math.round((gstRate / 2) * 100) / 100;
        cgstAmount = Math.round((taxableValue * (cgstRate / 100)) * 100) / 100;
        sgstAmount = Math.round((taxableValue * (sgstRate / 100)) * 100) / 100;
      }
    }

    const itemTotal = isTemporary ? taxableValue : Math.round((taxableValue + cgstAmount + sgstAmount + igstAmount) * 100) / 100;

    netAmount += taxableValue;
    cgstTotal += cgstAmount;
    sgstTotal += sgstAmount;
    igstTotal += igstAmount;

    return {
      sno: item.sno || idx + 1,
      description: item.description,
      hsnCode: isTemporary ? '' : (item.hsnCode || item.hsn_code || ''),
      quantity: qty,
      unit: item.unit || 'PCS',
      rate: rate,
      discount: discount,
      taxableValue: Math.round(taxableValue * 100) / 100,
      gstRate: gstRate,
      cgstRate: cgstRate,
      cgstAmount: Math.round(cgstAmount * 100) / 100,
      sgstRate: sgstRate,
      sgstAmount: Math.round(sgstAmount * 100) / 100,
      igstRate: igstRate,
      igstAmount: Math.round(igstAmount * 100) / 100,
      totalAmount: Math.round(itemTotal * 100) / 100
    };
  });

  netAmount = Math.round(netAmount * 100) / 100;
  cgstTotal = Math.round(cgstTotal * 100) / 100;
  sgstTotal = Math.round(sgstTotal * 100) / 100;
  igstTotal = Math.round(igstTotal * 100) / 100;

  const unroundedGrandTotal = isTemporary ? netAmount : Math.round((netAmount + cgstTotal + sgstTotal + igstTotal) * 100) / 100;
  const roundedGrandTotal = Math.round(unroundedGrandTotal);
  const roundOff = isTemporary ? 0 : Math.round((roundedGrandTotal - unroundedGrandTotal) * 100) / 100;

  const amountInWords = numberToIndianWords(roundedGrandTotal);

  return {
    isInterState,
    items: calculatedItems,
    netAmount,
    cgstTotal,
    sgstTotal,
    igstTotal,
    roundOff,
    grandTotal: roundedGrandTotal,
    amountInWords
  };
}

module.exports = {
  numberToIndianWords,
  calculateInvoiceFinancials
};
