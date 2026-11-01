const InvoiceSequence = require('../models/InvoiceSequence');
const Invoice = require('../models/Invoice');

/**
 * Get financial year string for a given date
 * In India, FY starts on April 1st and ends on March 31st.
 * Example: 1 Nov 2026 -> "26-27"
 * Example: 15 Jan 2027 -> "26-27"
 * Example: 15 May 2025 -> "25-26"
 */
function getFinancialYear(date = new Date()) {
  const d = new Date(date);
  const month = d.getMonth() + 1; // 1-12
  const fullYear = d.getFullYear(); // e.g. 2026

  let startYear, endYear;
  if (month >= 4) {
    startYear = fullYear;
    endYear = fullYear + 1;
  } else {
    startYear = fullYear - 1;
    endYear = fullYear;
  }

  const startYY = String(startYear).slice(-2);
  const endYY = String(endYear).slice(-2);
  return `${startYY}-${endYY}`;
}

/**
 * Allocate next sequential invoice number atomically
 */
async function allocateInvoiceNumber(date = new Date(), prefix = '') {
  const fy = getFinancialYear(date);

  const sequence = await InvoiceSequence.findOneAndUpdate(
    { financialYear: fy },
    { $inc: { currentNumber: 1 } },
    { new: true, upsert: true }
  );

  const seqNo = sequence.currentNumber;
  // Simple sequential invoice number: e.g. "1", "2", "3" or "SS-1"
  const invoiceNumber = prefix ? `${prefix}${seqNo}` : `${seqNo}`;

  return {
    financialYear: fy,
    sequenceNumber: seqNo,
    invoiceNumber
  };
}

/**
 * Reserve a block of sequential invoice numbers for an offline device
 * Example: device requests a block of 50 numbers.
 */
async function reserveNumberBlockForDevice(deviceId, deviceName = 'Android Mobile', blockSize = 50) {
  const fy = getFinancialYear(new Date());

  const sequence = await InvoiceSequence.findOneAndUpdate(
    { financialYear: fy },
    { $inc: { currentNumber: blockSize } },
    { new: true, upsert: true }
  );

  const to = sequence.currentNumber;
  const from = to - blockSize + 1;

  sequence.reservedBlocks.push({
    deviceId,
    deviceName,
    fromNumber: from,
    toNumber: to,
    reservedAt: new Date(),
    isExhausted: false
  });

  await sequence.save();

  return {
    financialYear: fy,
    fromNumber: from,
    toNumber: to,
    blockSize
  };
}

module.exports = {
  getFinancialYear,
  allocateInvoiceNumber,
  reserveNumberBlockForDevice
};
