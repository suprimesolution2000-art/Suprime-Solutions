const Device = require('../models/Device');
const Invoice = require('../models/Invoice');
const Payment = require('../models/Payment');
const Customer = require('../models/Customer');
const Product = require('../models/Product');
const { v4: uuidv4 } = require('uuid');
const { reserveNumberBlockForDevice, allocateInvoiceNumber, allocateTemporaryInvoiceNumber, adjustSequenceNumber } = require('../services/invoiceService');
const { calculateInvoiceFinancials } = require('../services/gstCalculationService');
const env = require('../config/env');

// Register device and reserve initial block of invoice numbers (e.g. 50 numbers)
exports.registerDevice = async (req, res, next) => {
  try {
    const { deviceId, deviceName } = req.body;

    if (!deviceId) {
      return res.status(400).json({ success: false, message: 'DeviceId is required.' });
    }

    const currentFy = require('../services/invoiceService').getFinancialYear(new Date());
    let device = await Device.findOne({ deviceId });
    if (!device) {
      const block = await reserveNumberBlockForDevice(deviceId, deviceName || 'Android Device', 50);
      device = await Device.create({
        deviceId,
        deviceName: deviceName || 'Android Device',
        registeredUser: req.user ? req.user.name : 'Owner',
        financialYear: currentFy,
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
          financialYear: currentFy,
          fromNumber: block.fromNumber,
          toNumber: block.toNumber,
          nextUsableNumber: block.fromNumber
        }
      });
    }

    // If client reported its current counter, advance device.nextUsableNumber
    const clientReportedNext = Number(req.body.nextUsableNumber);
    if (!isNaN(clientReportedNext) && clientReportedNext > device.nextUsableNumber) {
      device.nextUsableNumber = clientReportedNext;
    }

    // BUG-09: Partition block allocations by FY so devices restart at 1 every April 1st
    const isNewFy = !device.financialYear || device.financialYear !== currentFy;
    if (isNewFy || device.nextUsableNumber >= device.currentRangeTo) {
      const block = await reserveNumberBlockForDevice(deviceId, device.deviceName, 50);
      device.financialYear = currentFy;
      device.currentRangeFrom = block.fromNumber;
      device.currentRangeTo = block.toNumber;
      device.nextUsableNumber = block.fromNumber;
      await device.save();
    } else if (!isNaN(clientReportedNext)) {
      await device.save();
    }

    res.json({
      success: true,
      data: {
        deviceId: device.deviceId,
        financialYear: device.financialYear || currentFy,
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
    const { deviceId, customers = [], invoices = [], payments = [], products = [] } = req.body;

    const results = {
      customersSynced: 0,
      invoicesSynced: 0,
      paymentsSynced: 0,
      productsSynced: 0,
      syncedInvoiceUuids: [],
      syncedPaymentUuids: [],
      errors: []
    };

    // 1. Sync Customers
    for (const cust of customers) {
      try {
        const { totalBilled, outstandingBalance, totalPaid, ...profileData } = cust;
        const existingCust = await Customer.findOne({ uuid: cust.uuid });
        if (!existingCust) {
          await Customer.create({
            ...cust,
            updatedAt: new Date()
          });
        } else {
          // A stale device must not reactivate a customer that was deleted elsewhere.
          // Re-activation remains available through the explicit customer update API.
          const updateData = { ...profileData, updatedAt: new Date() };
          if (existingCust.active === false && cust.active !== false) {
            updateData.active = false;
          }
          // Only initialize balances if the cloud record has never been billed (B7)
          if ((existingCust.totalBilled || 0) === 0 && (existingCust.totalPaid || 0) === 0) {
            if (cust.outstandingBalance !== undefined) {
              updateData.outstandingBalance = Number(cust.outstandingBalance) || 0;
            }
            if (cust.totalBilled !== undefined) {
              updateData.totalBilled = Number(cust.totalBilled) || 0;
            }
            if (cust.totalPaid !== undefined) {
              updateData.totalPaid = Number(cust.totalPaid) || 0;
            }
          }
          await Customer.updateOne(
            { uuid: cust.uuid },
            { $set: updateData }
          );
        }
        results.customersSynced++;
      } catch (err) {
        results.errors.push({ type: 'Customer', id: cust.uuid, error: err.message });
      }
    }

    // 2. Sync Invoices
    for (const inv of invoices) {
      try {
        const isTemporary = (inv.invoiceType || inv.invoice_type) === 'temporary';

        // BUG-01: Match strictly by invoice UUID to prevent blind overwriting of existing invoices
        const existing = await Invoice.findOne({ uuid: inv.uuid });

        // Prevent older stale clients from re-cancelling restored server temporary bills
        if (isTemporary && existing && existing.status === 'finalized' && existing.active === true && (inv.status === 'cancelled' || inv.active === false)) {
          continue;
        }

        // If invoice is marked cancelled or inactive from mobile
        if (inv.status === 'cancelled' || inv.active === false) {
          if (existing && existing.status !== 'cancelled') {
            const custQuery = existing.customer && existing.customer.uuid
              ? { $or: [{ uuid: existing.customer.uuid }, { name: existing.customer.name }] }
              : (existing.customer?.name ? { name: existing.customer.name } : null);

            if (custQuery && existing.invoiceType !== 'temporary') {
              await Customer.updateOne(
                custQuery,
                {
                  $inc: {
                    totalBilled: -existing.grandTotal,
                    outstandingBalance: -existing.balanceDue,
                    totalPaid: -(existing.totalPaid || 0)
                  }
                }
              );
              const updatedCust = await Customer.findOne(custQuery);
              if (updatedCust && Math.abs(updatedCust.outstandingBalance) < 0.01) {
                updatedCust.outstandingBalance = 0;
                await updatedCust.save();
              }
            }
            await Payment.deleteMany({ invoiceId: existing.uuid });
            existing.status = 'cancelled';
            existing.active = false;
            existing.syncStatus = 'synced';
            existing.updatedAt = new Date();
            await existing.save();
            results.invoicesSynced++;
          }
          continue;
        }

        // Ignore stale copies of an invoice that has already been cancelled/deleted.
        if (existing && (existing.status === 'cancelled' || existing.active === false)) {
          continue;
        }

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

        // Validate calculations (BUG-07: Safe fallback for state code)
        const rawStateCode = inv.customer ? (inv.customer.stateCode || inv.customer.state_code) : '22';
        const customerStateCode = (rawStateCode && String(rawStateCode).trim() && String(rawStateCode).trim() !== 'null')
          ? String(rawStateCode).trim()
          : '22';
        const financials = calculateInvoiceFinancials(
          normalizedItems,
          customerStateCode,
          env.COMPANY.stateCode || '22',
          isTemporary
        );

        const safeCustomer = {
          uuid: inv.customer?.uuid || require('uuid').v4(),
          name: (inv.customer?.name && String(inv.customer.name).trim()) ? String(inv.customer.name).trim() : 'Walk-in Customer',
          businessName: inv.customer?.businessName || '',
          phone: inv.customer?.phone || '',
          email: inv.customer?.email || '',
          gstin: inv.customer?.gstin || '',
          address: inv.customer?.address || '',
          city: inv.customer?.city || '',
          state: (inv.customer?.state && String(inv.customer.state).trim()) ? String(inv.customer.state).trim() : (env.COMPANY.state || 'Chhattisgarh'),
          stateCode: customerStateCode
        };

        const safeSeq = inv.sequenceNumber !== undefined ? Number(inv.sequenceNumber) : (isTemporary ? 0 : 1);
        const safeFy = inv.financialYear || require('../services/invoiceService').getFinancialYear(inv.invoiceDate || new Date());
        const safeInvNumber = inv.invoiceNumber || (isTemporary ? `TEMP-${Date.now()}` : `INV-${Date.now()}`);

        if (!existing) {
          try {
            const { _id, __v, createdAt, ...cleanInv } = inv;
            await Invoice.create({
              ...cleanInv,
              customer: safeCustomer,
              invoiceNumber: safeInvNumber,
              sequenceNumber: safeSeq,
              financialYear: safeFy,
              invoiceType: isTemporary ? 'temporary' : 'gst',
              items: financials.items,
              createdBy: inv.createdBy || (req.user ? req.user.name : 'Administrator'),
              netAmount: financials.netAmount,
              cgstTotal: financials.cgstTotal,
              sgstTotal: financials.sgstTotal,
              igstTotal: financials.igstTotal,
              roundOff: financials.roundOff,
              grandTotal: financials.grandTotal,
              amountInWords: financials.amountInWords,
              balanceDue: inv.balanceDue !== undefined ? Number(inv.balanceDue) : financials.grandTotal,
              totalPaid: Number(inv.totalPaid) || 0,
              isInterState: inv.isInterState !== undefined ? Boolean(inv.isInterState) : false,
              paymentStatus: inv.paymentStatus || 'unpaid',
              status: inv.status || 'finalized',
              syncStatus: 'synced'
            });
            await adjustSequenceNumber(safeFy, safeSeq, isTemporary);
            results.invoicesSynced++;
            results.syncedInvoiceUuids.push(inv.uuid);
          } catch (createErr) {
            const collision = await Invoice.findOne({
              $or: [
                { uuid: inv.uuid },
                {
                  invoiceNumber: safeInvNumber,
                  invoiceType: isTemporary ? 'temporary' : { $ne: 'temporary' }
                }
              ]
            });
            if (collision && collision.uuid === inv.uuid) {
              // Same invoice being updated — preserve UUID and foreign keys
              collision.customer = safeCustomer;
              collision.items = financials.items;
              collision.netAmount = financials.netAmount;
              collision.cgstTotal = financials.cgstTotal;
              collision.sgstTotal = financials.sgstTotal;
              collision.igstTotal = financials.igstTotal;
              collision.roundOff = financials.roundOff;
              collision.grandTotal = financials.grandTotal;
              collision.amountInWords = financials.amountInWords;
              collision.balanceDue = inv.balanceDue !== undefined ? Number(inv.balanceDue) : financials.grandTotal;
              collision.paymentStatus = inv.paymentStatus || 'unpaid';
              collision.status = inv.status || 'finalized';
              collision.syncStatus = 'synced';
              collision.updatedAt = new Date();
              await collision.save();
              results.invoicesSynced++;
              results.syncedInvoiceUuids.push(inv.uuid);
            } else if (collision && collision.uuid !== inv.uuid) {
              // Sequence number collision with a DIFFERENT server invoice:
              // Allocate next available sequence number to protect existing server invoice & payments (B11)
              const allocated = isTemporary
                ? await allocateTemporaryInvoiceNumber(inv.invoiceDate || new Date())
                : await allocateInvoiceNumber(inv.invoiceDate || new Date());

              await Invoice.create({
                uuid: inv.uuid,
                invoiceNumber: allocated.invoiceNumber,
                sequenceNumber: allocated.sequenceNumber,
                financialYear: safeFy,
                invoiceDate: new Date(inv.invoiceDate || Date.now()),
                dueDate: inv.dueDate ? new Date(inv.dueDate) : null,
                poNumber: inv.poNumber ? String(inv.poNumber).trim() : '',
                poDate: inv.poDate ? new Date(inv.poDate) : null,
                challanNumber: inv.challanNumber ? String(inv.challanNumber).trim() : '',
                challanDate: inv.challanDate ? new Date(inv.challanDate) : null,
                customer: safeCustomer,
                isInterState: financials.isInterState,
                items: financials.items,
                netAmount: financials.netAmount,
                cgstTotal: financials.cgstTotal,
                sgstTotal: financials.sgstTotal,
                igstTotal: financials.igstTotal,
                roundOff: financials.roundOff,
                grandTotal: financials.grandTotal,
                amountInWords: financials.amountInWords,
                status: inv.status || 'finalized',
                paymentStatus: inv.paymentStatus || 'unpaid',
                balanceDue: inv.balanceDue !== undefined ? Number(inv.balanceDue) : financials.grandTotal,
                invoiceType: isTemporary ? 'temporary' : 'gst',
                deviceId: inv.deviceId || 'mobile-sync',
                syncStatus: 'synced'
              });
              results.invoicesSynced++;
              results.syncedInvoiceUuids.push(inv.uuid);
            } else {
              console.error(`[PushSync] Failed to create invoice ${inv.uuid}:`, createErr.message);
              throw createErr;
            }
          }

          // Auto-save/update customer in cloud database (preserve deactivated state if existing, and credit ledger for each new invoice - B9)
          if (inv.customer && inv.customer.name) {
            const custName = inv.customer.name.trim();
            const custUuid = inv.customer.uuid || inv.customerId || ('cust-' + inv.uuid);
            try {
              // BUG-02: Prevent double-credit if upfront payment is present in payments batch
              const hasMatchingPayment = Array.isArray(payments) && payments.some(p => p.invoiceId === inv.uuid);
              const invPaid = hasMatchingPayment ? 0 : (Number(inv.totalPaid) || 0);
              const invDue = Math.max(0, financials.grandTotal - invPaid);
              const existingCustRecord = await Customer.findOne({ $or: [{ uuid: custUuid }, { name: custName }] });

              if (existingCustRecord) {
                if (!isTemporary) {
                  existingCustRecord.totalBilled = Math.round(((existingCustRecord.totalBilled || 0) + financials.grandTotal) * 100) / 100;
                  existingCustRecord.totalPaid = Math.round(((existingCustRecord.totalPaid || 0) + invPaid) * 100) / 100;
                  existingCustRecord.outstandingBalance = Math.max(0, Math.round(((existingCustRecord.outstandingBalance || 0) + invDue) * 100) / 100);
                }
                existingCustRecord.businessName = inv.customer.businessName || existingCustRecord.businessName;
                existingCustRecord.phone = inv.customer.phone || existingCustRecord.phone;
                existingCustRecord.gstin = inv.customer.gstin || existingCustRecord.gstin;
                existingCustRecord.updatedAt = new Date();
                await existingCustRecord.save();
              } else {
                await Customer.create({
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
                  totalBilled: isTemporary ? 0 : financials.grandTotal,
                  totalPaid: isTemporary ? 0 : invPaid,
                  outstandingBalance: isTemporary ? 0 : invDue,
                  updatedAt: new Date()
                });
              }
            } catch (custErr) {
              console.error('Customer upsert error during sync:', custErr.message);
            }
          }
        } else {
          // Existing invoice was edited offline and pushed to cloud
          const deltaGrandTotal = Math.round((financials.grandTotal - existing.grandTotal) * 100) / 100;
          const newBalanceDue = Math.max(0, Math.round((financials.grandTotal - (existing.totalPaid || 0)) * 100) / 100);
          const deltaBalanceDue = Math.round((newBalanceDue - existing.balanceDue) * 100) / 100;

          if (!isTemporary && existing.invoiceType !== 'temporary' && existing.customer && existing.customer.uuid) {
            await Customer.updateOne(
              { uuid: existing.customer.uuid },
              {
                $inc: {
                  totalBilled: deltaGrandTotal,
                  outstandingBalance: deltaBalanceDue
                }
              }
            );
          }

          existing.items = financials.items;
          existing.netAmount = financials.netAmount;
          existing.cgstTotal = financials.cgstTotal;
          existing.sgstTotal = financials.sgstTotal;
          existing.igstTotal = financials.igstTotal;
          existing.roundOff = financials.roundOff;
          existing.grandTotal = financials.grandTotal;
          existing.amountInWords = financials.amountInWords;
          existing.balanceDue = newBalanceDue;
          existing.paymentStatus = newBalanceDue === 0 ? 'paid' : ((existing.totalPaid || 0) > 0 ? 'partially_paid' : 'unpaid');
          if (inv.poNumber !== undefined) existing.poNumber = inv.poNumber;
          if (inv.poDate !== undefined) existing.poDate = inv.poDate ? new Date(inv.poDate) : null;
          if (inv.challanNumber !== undefined) existing.challanNumber = inv.challanNumber;
          if (inv.challanDate !== undefined) existing.challanDate = inv.challanDate ? new Date(inv.challanDate) : null;
          if (inv.dueDate !== undefined) existing.dueDate = inv.dueDate ? new Date(inv.dueDate) : null;
          if (inv.customer) {
            existing.customer = {
              ...existing.customer,
              ...inv.customer
            };
          }
          existing.syncStatus = 'synced';
          existing.updatedAt = new Date();
          await existing.save();
          results.invoicesSynced++;
          results.syncedInvoiceUuids.push(inv.uuid);
        }

        // Auto-catalogue any products in invoice items without resurrecting deactivated ones (B10, B25 bulkWrite)
        if (Array.isArray(inv.items) && inv.items.length > 0) {
          const validItems = inv.items.filter(itm => itm.description && itm.description.trim());
          if (validItems.length > 0) {
            const bulkOps = validItems.map(itm => {
              const prodSet = {
                description: itm.description.trim(),
                unit: itm.unit || 'PCS',
                defaultRate: itm.rate || 0,
                gstRate: itm.gstRate || 18,
                updatedAt: new Date()
              };
              if (itm.hsnCode && itm.hsnCode.trim()) {
                prodSet.hsnCode = itm.hsnCode.trim();
              }
              return {
                updateOne: {
                  filter: { description: itm.description.trim() },
                  update: {
                    $set: prodSet,
                    $setOnInsert: {
                      uuid: itm.uuid || uuidv4(),
                      active: true
                    }
                  },
                  upsert: true
                }
              };
            });
            await Product.bulkWrite(bulkOps);
          }
        }
      } catch (err) {
        results.errors.push({ type: 'Invoice', id: inv.uuid, error: err.message });
      }
    }

    // 3. Sync Payments (S2: Calculate authoritative totalPaid from recorded payments)
    for (const p of payments) {
      try {
        const existing = await Payment.findOne({ uuid: p.uuid });
        if (!existing) {
          await Payment.create(p);

          // Update invoice balance from actual payments sum to prevent double-counting
          const targetInvoice = await Invoice.findOne({ uuid: p.invoiceId });
          if (targetInvoice && targetInvoice.status !== 'cancelled') {
            const allPayments = await Payment.find({ invoiceId: targetInvoice.uuid });
            const totalPaidSum = allPayments.reduce((acc, pay) => acc + (pay.amount || 0), 0);
            targetInvoice.totalPaid = Math.round(totalPaidSum * 100) / 100;
            targetInvoice.balanceDue = Math.max(0, Math.round((targetInvoice.grandTotal - targetInvoice.totalPaid) * 100) / 100);
            targetInvoice.paymentStatus = targetInvoice.balanceDue <= 0.01 ? 'paid' : (targetInvoice.totalPaid > 0 ? 'partially_paid' : 'unpaid');
            await targetInvoice.save();

            // Update Customer ledger balance in cloud MongoDB (B12)
            if (targetInvoice.invoiceType !== 'temporary' && targetInvoice.customer && targetInvoice.customer.uuid) {
              await Customer.updateOne(
                { uuid: targetInvoice.customer.uuid },
                {
                  $inc: {
                    totalPaid: Number(p.amount) || 0,
                    outstandingBalance: -(Number(p.amount) || 0)
                  }
                }
              );
            }
          }

          results.paymentsSynced++;
          results.syncedPaymentUuids.push(p.uuid);
        } else {
          results.paymentsSynced++;
          results.syncedPaymentUuids.push(p.uuid);
        }
      } catch (err) {
        results.errors.push({ type: 'Payment', id: p.uuid, error: err.message });
      }
    }

    // 4. Sync Products
    for (const prod of products) {
      try {
        if (!prod.description || !prod.description.trim()) continue;
        const prodUuid = prod.uuid || require('uuid').v4();
        const productFilter = { $or: [{ uuid: prodUuid }, { description: prod.description.trim() }] };
        const existingProduct = await Product.findOne(productFilter);
        const finalUuid = existingProduct ? existingProduct.uuid : prodUuid; // Preserve existing UUID (B11)
        const requestedActive = prod.active !== undefined
          ? (prod.active === true || prod.active === 1 || prod.active === 'true' || prod.active === '1')
          : true;
        const prodUpdateSet = {
          uuid: finalUuid,
          description: prod.description.trim(),
          unit: prod.unit || 'PCS',
          defaultRate: Number(prod.defaultRate !== undefined ? prod.defaultRate : prod.default_rate) || 0,
          gstRate: Number(prod.gstRate !== undefined ? prod.gstRate : prod.gst_rate) || 18,
          // Keep a deletion made on another device when this device sends a stale active copy.
          active: existingProduct?.active === false ? false : requestedActive,
          updatedAt: new Date()
        };
        const rawHsn = prod.hsnCode || prod.hsn_code;
        if (rawHsn && String(rawHsn).trim()) {
          prodUpdateSet.hsnCode = String(rawHsn).trim();
        }
        await Product.findOneAndUpdate(
          productFilter,
          { $set: prodUpdateSet },
          { upsert: true, new: true }
        );
        results.productsSynced++;
      } catch (err) {
        results.errors.push({ type: 'Product', id: prod.uuid, error: err.message });
      }
    }

    if (deviceId) {
      await Device.updateOne({ deviceId }, { $set: { lastSyncAt: new Date() } });
    }

    res.json({
      success: true,
      hasErrors: results.errors.length > 0,
      message: results.errors.length === 0 ? 'Sync completed' : 'Sync completed with non-critical warnings',
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
    let sinceDate = null;

    if (since && since !== 'null' && since !== 'undefined') {
      const parsed = new Date(since);
      if (!isNaN(parsed.getTime())) {
        sinceDate = parsed;
      }
    }

    const isFullSync = !sinceDate;

    // Full sync includes inactive records so clients can apply deletion tombstones.
    const custQuery = isFullSync
      ? {}
      : {
          $or: [
            { updatedAt: { $gt: sinceDate } },
            { createdAt: { $gt: sinceDate }, updatedAt: { $exists: false } }
          ]
        };

    // For incremental sync, pull only invoices modified since the last sync timestamp
    const invQuery = isFullSync
      ? {}
      : {
          $or: [
            { updatedAt: { $gt: sinceDate } },
            { createdAt: { $gt: sinceDate }, updatedAt: { $exists: false } }
          ]
        };
    const payQuery = isFullSync
      ? {}
      : {
          $or: [
            { updatedAt: { $gt: sinceDate } },
            { createdAt: { $gt: sinceDate }, updatedAt: { $exists: false } }
          ]
        };

    // Full sync includes inactive products so clients can apply deletion tombstones.
    const prodQuery = isFullSync
      ? {}
      : {
          $or: [
            { updatedAt: { $gt: sinceDate } },
            { createdAt: { $gt: sinceDate }, updatedAt: { $exists: false } }
          ]
        };

    const maxSyncLimit = isFullSync ? 5000 : 1000;
    const [customers, invoices, payments, products] = await Promise.all([
      Customer.find(custQuery).limit(maxSyncLimit).lean(),
      Invoice.find(invQuery).limit(maxSyncLimit).lean(),
      Payment.find(payQuery).limit(maxSyncLimit).lean(),
      Product.find(prodQuery).limit(maxSyncLimit).lean()
    ]);

    // Calculate live dynamic balances for pulled customers
    const customerUuids = customers.map(c => c.uuid).filter(Boolean);
    const aggregates = await Invoice.aggregate([
      { 
        $match: { 
          'customer.uuid': { $in: customerUuids },
          status: { $ne: 'cancelled' },
          invoiceType: { $ne: 'temporary' }
        } 
      },
      {
        $group: {
          _id: '$customer.uuid',
          totalBilled: { $sum: '$grandTotal' },
          totalPaid: { $sum: '$totalPaid' },
          outstandingBalance: { $sum: '$balanceDue' }
        }
      }
    ]);

    const aggMap = new Map();
    for (const agg of aggregates) {
      if (agg._id) {
        aggMap.set(agg._id, {
          totalBilled: Math.round((agg.totalBilled || 0) * 100) / 100,
          totalPaid: Math.round((agg.totalPaid || 0) * 100) / 100,
          outstandingBalance: Math.max(0, Math.round((agg.outstandingBalance || 0) * 100) / 100)
        });
      }
    }

    const enrichedCustomers = customers.map(c => {
      const agg = aggMap.get(c.uuid);
      if (agg) {
        return {
          ...c,
          totalBilled: agg.totalBilled,
          totalPaid: agg.totalPaid,
          outstandingBalance: agg.outstandingBalance
        };
      }
      return c;
    });

    res.json({
      success: true,
      timestamp: new Date().toISOString(),
      data: {
        customers: enrichedCustomers,
        invoices,
        payments,
        products
      }
    });
  } catch (error) {
    next(error);
  }
};
