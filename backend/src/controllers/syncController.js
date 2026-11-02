const Device = require('../models/Device');
const Invoice = require('../models/Invoice');
const Payment = require('../models/Payment');
const Customer = require('../models/Customer');
const Product = require('../models/Product');
const { reserveNumberBlockForDevice } = require('../services/invoiceService');
const { calculateInvoiceFinancials } = require('../services/gstCalculationService');
const env = require('../config/env');

// Register device and reserve initial block of invoice numbers (e.g. 50 numbers)
exports.registerDevice = async (req, res, next) => {
  try {
    const { deviceId, deviceName } = req.body;

    if (!deviceId) {
      return res.status(400).json({ success: false, message: 'DeviceId is required.' });
    }

    let device = await Device.findOne({ deviceId });
    if (!device) {
      const block = await reserveNumberBlockForDevice(deviceId, deviceName || 'Android Device', 50);
      device = await Device.create({
        deviceId,
        deviceName: deviceName || 'Android Device',
        registeredUser: req.user ? req.user.name : 'Owner',
        currentRangeFrom: block.fromNumber,
        currentRangeTo: block.toNumber,
        nextUsableNumber: block.fromNumber,
        lastSyncAt: new Date()
      });

      return res.status(201).json({
        success: true,
        message: 'Device registered successfully with initial reserved sequence block',
        data: {
          deviceId: device.deviceId,
          financialYear: block.financialYear,
          fromNumber: block.fromNumber,
          toNumber: block.toNumber,
          nextUsableNumber: block.fromNumber
        }
      });
    }

    // If device exists and range exhausted, reserve new block
    if (device.nextUsableNumber > device.currentRangeTo) {
      const block = await reserveNumberBlockForDevice(deviceId, device.deviceName, 50);
      device.currentRangeFrom = block.fromNumber;
      device.currentRangeTo = block.toNumber;
      device.nextUsableNumber = block.fromNumber;
      await device.save();
    }

    res.json({
      success: true,
      data: {
        deviceId: device.deviceId,
        fromNumber: device.currentRangeFrom,
        toNumber: device.currentRangeTo,
        nextUsableNumber: device.nextUsableNumber
      }
    });
  } catch (error) {
    next(error);
  }
};

// Push local offline records to cloud backend
exports.pushSync = async (req, res, next) => {
  try {
    const { deviceId, customers = [], invoices = [], payments = [] } = req.body;

    const results = {
      customersSynced: 0,
      invoicesSynced: 0,
      paymentsSynced: 0,
      errors: []
    };

    // 1. Sync Customers
    for (const cust of customers) {
      try {
        await Customer.findOneAndUpdate(
          { uuid: cust.uuid },
          { $set: { ...cust, updatedAt: new Date() } },
          { upsert: true, new: true }
        );
        results.customersSynced++;
      } catch (err) {
        results.errors.push({ type: 'Customer', id: cust.uuid, error: err.message });
      }
    }

    // 2. Sync Invoices
    for (const inv of invoices) {
      try {
        const existing = await Invoice.findOne({ uuid: inv.uuid });
        if (!existing) {
          // Normalize items (support both snake_case and camelCase from mobile)
          const normalizedItems = (inv.items || []).map((itm, idx) => ({
            sno: itm.sno || idx + 1,
            description: itm.description || '',
            hsnCode: itm.hsnCode || itm.hsn_code || '',
            quantity: Number(itm.quantity) || 0,
            unit: itm.unit || 'PCS',
            rate: Number(itm.rate) || 0,
            discount: Number(itm.discount) || 0,
            taxableValue: Number(itm.taxableValue !== undefined ? itm.taxableValue : itm.taxable_value) || 0,
            gstRate: Number(itm.gstRate !== undefined ? itm.gstRate : (itm.gst_rate !== undefined ? itm.gst_rate : 18.0)),
            cgstRate: Number(itm.cgstRate !== undefined ? itm.cgstRate : itm.cgst_rate) || 0,
            cgstAmount: Number(itm.cgstAmount !== undefined ? itm.cgstAmount : itm.cgst_amount) || 0,
            sgstRate: Number(itm.sgstRate !== undefined ? itm.sgstRate : itm.sgst_rate) || 0,
            sgstAmount: Number(itm.sgstAmount !== undefined ? itm.sgstAmount : itm.sgst_amount) || 0,
            igstRate: Number(itm.igstRate !== undefined ? itm.igstRate : itm.igst_rate) || 0,
            igstAmount: Number(itm.igstAmount !== undefined ? itm.igstAmount : itm.igst_amount) || 0,
            totalAmount: Number(itm.totalAmount !== undefined ? itm.totalAmount : itm.total_amount) || 0,
          }));

          // Validate calculations
          const financials = calculateInvoiceFinancials(
            normalizedItems,
            inv.customer ? inv.customer.stateCode : '22',
            env.COMPANY.stateCode || '22'
          );

          await Invoice.create({
            ...inv,
            items: financials.items,
            createdBy: inv.createdBy || (req.user ? req.user.name : 'Administrator'),
            netAmount: financials.netAmount,
            cgstTotal: financials.cgstTotal,
            sgstTotal: financials.sgstTotal,
            igstTotal: financials.igstTotal,
            roundOff: financials.roundOff,
            grandTotal: financials.grandTotal,
            amountInWords: financials.amountInWords,
            syncStatus: 'synced'
          });
          results.invoicesSynced++;

          // Auto-save/update customer in cloud database
          if (inv.customer && inv.customer.name) {
            const custName = inv.customer.name.trim();
            const custUuid = inv.customer.uuid || inv.customerId || ('cust-' + inv.uuid);
            try {
              await Customer.findOneAndUpdate(
                { $or: [{ uuid: custUuid }, { name: custName }] },
                {
                  $set: {
                    uuid: custUuid,
                    name: custName,
                    businessName: inv.customer.businessName || '',
                    phone: inv.customer.phone || '',
                    email: inv.customer.email || '',
                    gstin: inv.customer.gstin || '',
                    address: inv.customer.address || '',
                    city: inv.customer.city || '',
                    state: inv.customer.state || 'Chhattisgarh',
                    stateCode: inv.customer.stateCode || '22',
                    active: true,
                    updatedAt: new Date()
                  },
                  $inc: {
                    totalBilled: financials.grandTotal,
                    outstandingBalance: financials.grandTotal
                  }
                },
                { upsert: true, new: true }
              );
            } catch (custErr) {
              console.error('Customer upsert error during sync:', custErr.message);
            }
          }

          // Auto-catalogue any products in invoice items
          if (Array.isArray(inv.items)) {
            for (const itm of inv.items) {
              if (itm.description && itm.description.trim()) {
                await Product.findOneAndUpdate(
                  { description: itm.description.trim() },
                  {
                    $set: {
                      description: itm.description.trim(),
                      hsnCode: itm.hsnCode || '',
                      unit: itm.unit || 'PCS',
                      defaultRate: itm.rate || 0,
                      gstRate: itm.gstRate || 18,
                      active: true
                    }
                  },
                  { upsert: true }
                );
              }
            }
          }
        }
      } catch (err) {
        results.errors.push({ type: 'Invoice', id: inv.uuid, error: err.message });
      }
    }

    // 3. Sync Payments
    for (const p of payments) {
      try {
        const existing = await Payment.findOne({ uuid: p.uuid });
        if (!existing) {
          await Payment.create(p);

          // Update invoice balance
          const targetInvoice = await Invoice.findOne({ uuid: p.invoiceId });
          if (targetInvoice) {
            targetInvoice.totalPaid = Math.round(((targetInvoice.totalPaid || 0) + p.amount) * 100) / 100;
            targetInvoice.balanceDue = Math.max(0, Math.round((targetInvoice.grandTotal - targetInvoice.totalPaid) * 100) / 100);
            targetInvoice.paymentStatus = targetInvoice.balanceDue === 0 ? 'paid' : 'partially_paid';
            await targetInvoice.save();
          }

          results.paymentsSynced++;
        }
      } catch (err) {
        results.errors.push({ type: 'Payment', id: p.uuid, error: err.message });
      }
    }

    if (deviceId) {
      await Device.updateOne({ deviceId }, { $set: { lastSyncAt: new Date() } });
    }

    res.json({
      success: results.errors.length === 0,
      message: results.errors.length === 0 ? 'Sync completed' : 'Sync completed with errors',
      results
    });
  } catch (error) {
    next(error);
  }
};

// Pull latest changes since timestamp
exports.pullSync = async (req, res, next) => {
  try {
    const { since } = req.query;
    const sinceDate = since ? new Date(since) : new Date(0);

    const [customers, invoices, payments, products] = await Promise.all([
      Customer.find({ updatedAt: { $gt: sinceDate } }),
      Invoice.find({ updatedAt: { $gt: sinceDate } }),
      Payment.find({ updatedAt: { $gt: sinceDate } }),
      Product.find({ active: true })
    ]);

    res.json({
      success: true,
      timestamp: new Date().toISOString(),
      data: {
        customers,
        invoices,
        payments,
        products
      }
    });
  } catch (error) {
    next(error);
  }
};
