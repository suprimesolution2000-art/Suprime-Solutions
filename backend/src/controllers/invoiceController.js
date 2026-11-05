const Invoice = require('../models/Invoice');
const Customer = require('../models/Customer');
const Payment = require('../models/Payment');
const Product = require('../models/Product');
const AuditLog = require('../models/AuditLog');
const { calculateInvoiceFinancials } = require('../services/gstCalculationService');
const { allocateInvoiceNumber, getFinancialYear } = require('../services/invoiceService');
const { generateInvoicePdf } = require('../services/pdfService');
const env = require('../config/env');
const { v4: uuidv4 } = require('uuid');
const { findByIdOrUuid } = require('../utils/idHelper');
const { escapeRegex } = require('../utils/regexHelper');

// Universal search and filtering
exports.getInvoices = async (req, res, next) => {
  try {
    const {
      search,
      status,
      paymentStatus,
      startDate,
      endDate,
      minAmount,
      maxAmount,
      customerId,
      isInterState,
      sortBy = 'invoiceDate',
      sortOrder = 'desc',
      page = 1,
      limit = 25
    } = req.query;

    const query = {};

    // 1. Universal Search (Case-insensitive across invoice #, party, phone, GSTIN, items, PO, Challan)
    if (search && search.trim()) {
      const regex = new RegExp(escapeRegex(search.trim()), 'i');
      query.$or = [
        { invoiceNumber: regex },
        { 'customer.name': regex },
        { 'customer.businessName': regex },
        { 'customer.phone': regex },
        { 'customer.gstin': regex },
        { poNumber: regex },
        { challanNumber: regex },
        { 'items.description': regex },
        { 'items.hsnCode': regex }
      ];
    }

    // 2. Status Filters
    if (status) query.status = status;
    if (paymentStatus) query.paymentStatus = paymentStatus;

    // 3. Date Filters
    if (startDate || endDate) {
      query.invoiceDate = {};
      if (startDate) query.invoiceDate.$gte = new Date(startDate);
      if (endDate) {
        const end = new Date(endDate);
        end.setHours(23, 59, 59, 999);
        query.invoiceDate.$lte = end;
      }
    }

    // 4. Amount Filters
    if (minAmount !== undefined || maxAmount !== undefined) {
      query.grandTotal = {};
      if (minAmount !== undefined) query.grandTotal.$gte = Number(minAmount);
      if (maxAmount !== undefined) query.grandTotal.$lte = Number(maxAmount);
    }

    // 5. Customer Filter
    if (customerId) {
      query['customer.uuid'] = customerId;
    }

    if (isInterState !== undefined) {
      query.isInterState = isInterState === 'true';
    }

    // Sorting
    const sort = {};
    sort[sortBy] = sortOrder === 'asc' ? 1 : -1;

    const safePage = Math.max(1, parseInt(page, 10) || 1);
    const safeLimit = Math.min(Math.max(1, parseInt(limit, 10) || 25), 200);
    const skip = (safePage - 1) * safeLimit;
    const [invoices, total] = await Promise.all([
      Invoice.find(query).sort(sort).skip(skip).limit(safeLimit),
      Invoice.countDocuments(query)
    ]);

    res.json({
      success: true,
      data: invoices,
      pagination: {
        page: safePage,
        limit: safeLimit,
        total,
        pages: Math.ceil(total / safeLimit)
      }
    });
  } catch (error) {
    next(error);
  }
};

exports.getInvoiceById = async (req, res, next) => {
  try {
    const invoice = await Invoice.findOne(findByIdOrUuid(req.params.id));

    if (!invoice) {
      return res.status(404).json({ success: false, message: 'Invoice not found.' });
    }

    res.json({ success: true, data: invoice });
  } catch (error) {
    next(error);
  }
};

// Create / Issue Invoice
exports.createInvoice = async (req, res, next) => {
  try {
    const {
      customer,
      items,
      invoiceDate = new Date(),
      dueDate,
      poNumber,
      poDate,
      challanNumber,
      challanDate,
      status = 'finalized',
      deviceId,
      clientInvoiceNumber,
      clientSequenceNumber
    } = req.body;

    if (!customer || !customer.name || !customer.name.trim()) {
      return res.status(400).json({ success: false, message: 'Customer name is required.' });
    }

    if (!items || !items.length) {
      return res.status(400).json({ success: false, message: 'At least one line item is required.' });
    }

    const customerStateCode = customer.stateCode || '22';
    const businessStateCode = env.COMPANY.stateCode || '22';

    // 1. Calculate & Validate all financials server-side
    const financials = calculateInvoiceFinancials(items, customerStateCode, businessStateCode);

    // 2. Sequential Invoice Numbering
    let invoiceNumber = clientInvoiceNumber || req.body.invoiceNumber;
    let sequenceNumber = clientSequenceNumber || req.body.sequenceNumber;
    const fy = getFinancialYear(invoiceDate);

    if (!invoiceNumber) {
      const allocated = await allocateInvoiceNumber(invoiceDate);
      invoiceNumber = allocated.invoiceNumber;
      sequenceNumber = allocated.sequenceNumber;
    } else if (!sequenceNumber) {
      const parsedSeq = parseInt((invoiceNumber.match(/\d+/) || [])[0], 10);
      sequenceNumber = isNaN(parsedSeq) ? 1 : parsedSeq;
    }

    const uuid = req.body.uuid || uuidv4();

    // 3. Snapshot customer details & ensure customer record exists/updates
    let customerUuid = customer.uuid;
    const customerPhone = customer.phone ? customer.phone.trim() : '';

    if (!customerUuid) {
      let existingCustomer = null;
      if (customerPhone) {
        existingCustomer = await Customer.findOne({ phone: customerPhone });
      }
      if (!existingCustomer && customer.name && customer.name.trim()) {
        existingCustomer = await Customer.findOne({ name: customer.name.trim() });
      }

      if (existingCustomer) {
        customerUuid = existingCustomer.uuid;
        existingCustomer.totalBilled = (existingCustomer.totalBilled || 0) + financials.grandTotal;
        existingCustomer.outstandingBalance = (existingCustomer.outstandingBalance || 0) + financials.grandTotal;
        await existingCustomer.save();
      } else {
        customerUuid = uuidv4();
        await Customer.create({
          uuid: customerUuid,
          name: customer.name.trim(),
          businessName: customer.businessName || '',
          phone: customerPhone,
          gstin: customer.gstin ? customer.gstin.trim().toUpperCase() : '',
          address: customer.address || '',
          city: customer.city || 'Bilaspur',
          state: customer.state || 'Chhattisgarh',
          stateCode: customer.stateCode || '22',
          totalBilled: financials.grandTotal,
          outstandingBalance: financials.grandTotal
        });
      }
    } else {
      await Customer.updateOne(
        { uuid: customerUuid },
        {
          $inc: {
            totalBilled: financials.grandTotal,
            outstandingBalance: financials.grandTotal
          }
        }
      );
    }

    const customerSnapshot = {
      uuid: customerUuid,
      name: customer.name.trim(),
      businessName: customer.businessName || '',
      phone: customerPhone,
      email: customer.email || '',
      gstin: customer.gstin ? customer.gstin.trim().toUpperCase() : '',
      address: customer.address || '',
      city: customer.city || 'Bilaspur',
      state: customer.state || 'Chhattisgarh',
      stateCode: customer.stateCode || '22'
    };

    // 4. Save Invoice
    const invoice = await Invoice.create({
      uuid,
      invoiceNumber,
      sequenceNumber: sequenceNumber || 1,
      financialYear: fy,
      invoiceDate: new Date(invoiceDate),
      dueDate: dueDate ? new Date(dueDate) : null,
      poNumber: poNumber || '',
      poDate: poDate ? new Date(poDate) : null,
      challanNumber: challanNumber || '',
      challanDate: challanDate ? new Date(challanDate) : null,
      customer: customerSnapshot,
      isInterState: financials.isInterState,
      items: financials.items,
      netAmount: financials.netAmount,
      cgstTotal: financials.cgstTotal,
      sgstTotal: financials.sgstTotal,
      igstTotal: financials.igstTotal,
      roundOff: financials.roundOff,
      grandTotal: financials.grandTotal,
      amountInWords: financials.amountInWords,
      status: status,
      paymentStatus: 'unpaid',
      totalPaid: 0,
      balanceDue: financials.grandTotal,
      deviceId: deviceId || 'web-or-mobile',
      createdBy: req.user ? req.user.name : 'System',
      syncStatus: 'synced'
    });

    // Audit log
    await AuditLog.create({
      action: 'CREATE_INVOICE',
      entity: 'Invoice',
      entityId: invoice.uuid,
      performedBy: req.user ? req.user.name : 'Owner',
      role: req.user ? req.user.role : 'owner',
      deviceId,
      details: { invoiceNumber, grandTotal: financials.grandTotal }
    });

    res.status(201).json({
      success: true,
      message: 'Invoice created successfully',
      data: invoice
    });
  } catch (error) {
    next(error);
  }
};

// Stream Generated PDF
exports.getInvoicePdf = async (req, res, next) => {
  try {
    const invoice = await Invoice.findOne(findByIdOrUuid(req.params.id));

    if (!invoice) {
      return res.status(404).json({ success: false, message: 'Invoice not found.' });
    }

    const pdfBuffer = await generateInvoicePdf(invoice);

    const filename = `${invoice.invoiceNumber.replace(/\//g, '_')}.pdf`;
    res.setHeader('Content-Type', 'application/pdf');
    res.setHeader('Content-Disposition', `inline; filename="${filename}"`);
    res.setHeader('Content-Length', pdfBuffer.length);
    res.send(pdfBuffer);
  } catch (error) {
    next(error);
  }
};

// Cancel Invoice (Owner only)
exports.cancelInvoice = async (req, res, next) => {
  try {
    const { reason } = req.body;
    const invoice = await Invoice.findOne(findByIdOrUuid(req.params.id));

    if (!invoice) {
      return res.status(404).json({ success: false, message: 'Invoice not found.' });
    }

    if (invoice.status === 'cancelled') {
      return res.status(400).json({ success: false, message: 'Invoice is already cancelled.' });
    }

    invoice.status = 'cancelled';
    await invoice.save();

    // Adjust customer ledger balance
    if (invoice.customer && invoice.customer.uuid) {
      await Customer.updateOne(
        { uuid: invoice.customer.uuid },
        {
          $inc: {
            totalBilled: -invoice.grandTotal,
            outstandingBalance: -invoice.balanceDue
          }
        }
      );
    }

    await AuditLog.create({
      action: 'CANCEL_INVOICE',
      entity: 'Invoice',
      entityId: invoice.uuid,
      performedBy: req.user.name,
      role: req.user.role,
      details: { invoiceNumber: invoice.invoiceNumber, reason }
    });

    res.json({ success: true, message: 'Invoice cancelled successfully', data: invoice });
  } catch (error) {
    next(error);
  }
};

// @desc    Update existing invoice
// @route   PUT /api/invoices/:id
// @access  Private
exports.updateInvoice = async (req, res, next) => {
  try {
    const invoice = await Invoice.findOne(findByIdOrUuid(req.params.id));

    if (!invoice) {
      return res.status(404).json({ success: false, message: 'Invoice not found.' });
    }

    if (invoice.status === 'cancelled') {
      return res.status(400).json({ success: false, message: 'Cannot edit a cancelled invoice.' });
    }

    const {
      customer,
      items,
      invoiceDate,
      dueDate,
      poNumber,
      poDate,
      challanNumber,
      challanDate,
      deviceId
    } = req.body;

    if (items && !items.length) {
      return res.status(400).json({ success: false, message: 'At least one line item is required.' });
    }

    const updatedCustomer = customer || invoice.customer;
    const customerStateCode = updatedCustomer.stateCode || '22';
    const businessStateCode = env.COMPANY.stateCode || '22';

    // Recalculate financials
    const itemsToCalculate = items || invoice.items;
    const financials = calculateInvoiceFinancials(itemsToCalculate, customerStateCode, businessStateCode);

    const deltaGrandTotal = Math.round((financials.grandTotal - invoice.grandTotal) * 100) / 100;
    const newBalanceDue = Math.max(0, Math.round((financials.grandTotal - (invoice.totalPaid || 0)) * 100) / 100);
    const deltaBalanceDue = Math.round((newBalanceDue - invoice.balanceDue) * 100) / 100;

    // Adjust customer ledger for financial differences
    if (invoice.customer && invoice.customer.uuid) {
      await Customer.updateOne(
        { uuid: invoice.customer.uuid },
        {
          $inc: {
            totalBilled: deltaGrandTotal,
            outstandingBalance: deltaBalanceDue
          }
        }
      );
    }

    // Update customer snapshot if provided
    if (customer) {
      invoice.customer = {
        uuid: customer.uuid || invoice.customer.uuid,
        name: (customer.name || invoice.customer.name).trim(),
        businessName: customer.businessName !== undefined ? customer.businessName : invoice.customer.businessName,
        phone: customer.phone !== undefined ? customer.phone : invoice.customer.phone,
        email: customer.email !== undefined ? customer.email : invoice.customer.email,
        gstin: customer.gstin !== undefined ? customer.gstin : invoice.customer.gstin,
        address: customer.address !== undefined ? customer.address : invoice.customer.address,
        city: customer.city !== undefined ? customer.city : invoice.customer.city,
        state: customer.state || invoice.customer.state,
        stateCode: customer.stateCode || invoice.customer.stateCode
      };
    }

    if (invoiceDate) invoice.invoiceDate = new Date(invoiceDate);
    if (dueDate !== undefined) invoice.dueDate = dueDate ? new Date(dueDate) : null;
    if (poNumber !== undefined) invoice.poNumber = poNumber.trim();
    if (poDate !== undefined) invoice.poDate = poDate ? new Date(poDate) : null;
    if (challanNumber !== undefined) invoice.challanNumber = challanNumber.trim();
    if (challanDate !== undefined) invoice.challanDate = challanDate ? new Date(challanDate) : null;

    invoice.isInterState = financials.isInterState;
    invoice.items = financials.items;
    invoice.netAmount = financials.netAmount;
    invoice.cgstTotal = financials.cgstTotal;
    invoice.sgstTotal = financials.sgstTotal;
    invoice.igstTotal = financials.igstTotal;
    invoice.roundOff = financials.roundOff;
    invoice.grandTotal = financials.grandTotal;
    invoice.amountInWords = financials.amountInWords;
    invoice.balanceDue = newBalanceDue;
    invoice.paymentStatus = newBalanceDue === 0 ? 'paid' : ((invoice.totalPaid || 0) > 0 ? 'partially_paid' : 'unpaid');
    invoice.updatedAt = new Date();
    await invoice.save();

    // Auto-catalog any products in updated invoice items
    if (Array.isArray(financials.items)) {
      for (const itm of financials.items) {
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
                updatedAt: new Date()
              },
              $setOnInsert: {
                active: true
              }
            },
            { upsert: true }
          );
        }
      }
    }

    await AuditLog.create({
      action: 'UPDATE_INVOICE',
      entity: 'Invoice',
      entityId: invoice.uuid,
      performedBy: req.user ? req.user.name : 'User',
      role: req.user ? req.user.role : 'owner',
      deviceId,
      details: {
        invoiceNumber: invoice.invoiceNumber,
        grandTotal: financials.grandTotal,
        deltaGrandTotal
      }
    });

    res.json({
      success: true,
      message: 'Invoice updated successfully',
      data: invoice
    });
  } catch (error) {
    next(error);
  }
};

// @desc    Delete invoice permanently (soft-delete for sync propagation)
// @route   DELETE /api/invoices/:id
// @access  Private (Owner)
exports.deleteInvoice = async (req, res, next) => {
  try {
    const invoice = await Invoice.findOne(findByIdOrUuid(req.params.id));

    if (!invoice) {
      return res.status(404).json({ success: false, message: 'Invoice not found.' });
    }

    // Adjust customer ledger balance only if invoice was not already cancelled
    if (invoice.status !== 'cancelled' && invoice.customer) {
      const custQuery = invoice.customer.uuid
        ? { $or: [{ uuid: invoice.customer.uuid }, { name: invoice.customer.name }] }
        : (invoice.customer.name ? { name: invoice.customer.name } : null);

      if (custQuery) {
        await Customer.updateOne(
          custQuery,
          {
            $inc: {
              totalBilled: -invoice.grandTotal,
              outstandingBalance: -invoice.balanceDue,
              totalPaid: -(invoice.totalPaid || 0)
            }
          }
        );
        const updatedCust = await Customer.findOne(custQuery);
        if (updatedCust && Math.abs(updatedCust.outstandingBalance) < 0.01) {
          updatedCust.outstandingBalance = 0;
          await updatedCust.save();
        }
      }
    }

    // Remove any associated payments
    await Payment.deleteMany({ invoiceId: invoice.uuid });

    // Mark as cancelled and deactivated so incremental sync propagates to other devices
    invoice.status = 'cancelled';
    invoice.active = false;
    invoice.syncStatus = 'synced';
    invoice.updatedAt = new Date();
    await invoice.save();

    await AuditLog.create({
      action: 'DELETE_INVOICE',
      entity: 'Invoice',
      entityId: invoice.uuid,
      performedBy: req.user?.name || 'Owner',
      role: req.user?.role || 'owner',
      details: { invoiceNumber: invoice.invoiceNumber }
    });

    res.json({ success: true, message: 'Invoice deleted successfully' });
  } catch (error) {
    next(error);
  }
};
