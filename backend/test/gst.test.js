const { describe, it } = require('node:test');
const assert = require('node:assert');
const { numberToIndianWords, calculateInvoiceFinancials } = require('../src/services/gstCalculationService');

describe('GST Calculation Service Tests', () => {
  it('should correctly convert numbers to Indian currency words', () => {
    assert.strictEqual(
      numberToIndianWords(31329),
      'Rupees Thirty One Thousand Three Hundred Twenty Nine Only'
    );
    assert.strictEqual(
      numberToIndianWords(100500),
      'Rupees One Lakh Five Hundred Only'
    );
    assert.strictEqual(
      numberToIndianWords(2500050.75),
      'Rupees Twenty Five Lakh Fifty and Seventy Five Paise Only'
    );
  });

  it('should correctly calculate intra-state GST (CGST + SGST) for Chhattisgarh', () => {
    const items = [
      { sno: 1, description: 'Gasket', quantity: 10, rate: 100, gstRate: 18 },
      { sno: 2, description: 'Hydraulic Seal', quantity: 2, rate: 500, gstRate: 18 }
    ];
    // Taxable: 10*100 = 1000 + 2*500 = 1000 => 2000
    // CGST 9% = 180, SGST 9% = 180, Total = 2360
    const result = calculateInvoiceFinancials(items, '22', '22');
    assert.strictEqual(result.isInterState, false);
    assert.strictEqual(result.netAmount, 2000);
    assert.strictEqual(result.cgstTotal, 180);
    assert.strictEqual(result.sgstTotal, 180);
    assert.strictEqual(result.igstTotal, 0);
    assert.strictEqual(result.grandTotal, 2360);
    assert.strictEqual(result.roundOff, 0);
  });

  it('should correctly calculate inter-state GST (IGST) for outside Chhattisgarh', () => {
    const items = [
      { sno: 1, description: 'Industrial Hose', quantity: 5, rate: 1000, gstRate: 18 }
    ];
    // Taxable: 5000, IGST 18% = 900, Total = 5900
    const result = calculateInvoiceFinancials(items, '23', '22'); // 23 is MP, 22 is CG
    assert.strictEqual(result.isInterState, true);
    assert.strictEqual(result.netAmount, 5000);
    assert.strictEqual(result.cgstTotal, 0);
    assert.strictEqual(result.sgstTotal, 0);
    assert.strictEqual(result.igstTotal, 900);
    assert.strictEqual(result.grandTotal, 5900);
  });

  it('should handle round-off calculation correctly', () => {
    const items = [
      { sno: 1, description: 'Item A', quantity: 1, rate: 33.33, gstRate: 18 }
    ];
    // 33.33 * 0.18 = 5.9994 => CGST = 3.00, SGST = 3.00, Total = 39.33 => Rounded = 39, roundOff = -0.33
    const result = calculateInvoiceFinancials(items, '22', '22');
    assert.strictEqual(result.grandTotal, 39);
    assert.strictEqual(result.roundOff, -0.33);
  });
});
