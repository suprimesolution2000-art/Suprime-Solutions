const { describe, it } = require('node:test');
const assert = require('node:assert');
const { generateInvoicePdf } = require('../src/services/pdfService');

describe('Backend Services & PDF Overlay Tests', () => {
  it('should generate an invoice PDF buffer from sample data using the master template', async () => {
    const mockInvoice = {
      invoiceNumber: 'SS/26-27/001',
      invoiceDate: new Date('2026-11-01'),
      customer: {
        name: 'JINDAL STEEL & POWER LIMITED',
        address: 'Raigarh Plant, Industrial Area, Raigarh',
        state: 'Chhattisgarh',
        stateCode: '22',
        gstin: '22AAACJ1234F1Z5'
      },
      poNumber: 'PO/JSPL/2026/894',
      poDate: new Date('2026-10-28'),
      challanNumber: 'CH-5401',
      challanDate: new Date('2026-11-01'),
      items: [
        {
          sno: 1,
          description: 'Spiral Wound Gasket 3" 150# CS/SS304/Graphite',
          hsnCode: '8484',
          quantity: 25,
          unit: 'NOS',
          rate: 420.00,
          taxableValue: 10500.00,
          gstRate: 18.0
        }
      ],
      netAmount: 10500.00,
      cgstTotal: 945.00,
      sgstTotal: 945.00,
      igstTotal: 0.00,
      roundOff: 0.00,
      grandTotal: 12390.00,
      amountInWords: 'Rupees Twelve Thousand Three Hundred Ninety Only',
      isInterState: false
    };

    const pdfBuffer = await generateInvoicePdf(mockInvoice);
    assert.ok(pdfBuffer instanceof Buffer);
    assert.ok(pdfBuffer.length > 50000, 'PDF buffer should be substantial because of the scanned background template');

    // Verify it starts with PDF magic header '%PDF-'
    const header = pdfBuffer.slice(0, 5).toString('utf8');
    assert.strictEqual(header, '%PDF-');
  });

  it('should generate a Temporary Bill PDF buffer when invoiceType is temporary', async () => {
    const mockTempInvoice = {
      invoiceNumber: 'TB/26-27/001',
      invoiceType: 'temporary',
      invoiceDate: new Date('2026-11-08'),
      customer: {
        name: 'SHARMA HARDWARE',
        address: 'Main Market, Bilaspur',
      },
      items: [
        {
          sno: 1,
          description: 'Industrial Hose Pipe 20m',
          quantity: 2,
          unit: 'ROLL',
          rate: 1500.00,
          totalAmount: 3000.00
        }
      ],
      grandTotal: 3000.00
    };

    const pdfBuffer = await generateInvoicePdf(mockTempInvoice);
    assert.ok(pdfBuffer instanceof Buffer);
    assert.ok(pdfBuffer.length > 50000, 'Temporary bill PDF buffer should be substantial');

    const header = pdfBuffer.slice(0, 5).toString('utf8');
    assert.strictEqual(header, '%PDF-');
  });
});
