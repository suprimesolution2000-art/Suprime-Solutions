const Invoice = require('../models/Invoice');
const Customer = require('../models/Customer');
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

    const skip = (Number(page) - 1) * Number(limit);
    const [invoices, total] = await Promise.all([
      Invoice.find(query).sort(sort).skip(skip).limit(Number(limit)),
      Invoice.countDocuments(query)
    ]);

    res.json({
      success: true,
      data: invoices,
      pagination: {
        page: Number(page),
        limit: Number(limit),
        total,
        pages: Math.ceil(total / Number(limit))
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

// @desc    Delete invoice permanently
// @route   DELETE /api/invoices/:id
// @access  Private (Owner)
exports.deleteInvoice = async (req, res, next) => {
  try {
    const invoice = await Invoice.findOne(findByIdOrUuid(req.params.id));

    if (!invoice) {
      return res.status(404).json({ success: false, message: 'Invoice not found.' });
    }

    // Adjust customer ledger balance if unpaid / partially paid
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

    await Invoice.deleteOne({ _id: invoice._id });

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
