const Payment = require('../models/Payment');
const Invoice = require('../models/Invoice');
const Customer = require('../models/Customer');
const AuditLog = require('../models/AuditLog');
const { v4: uuidv4 } = require('uuid');
const { findByIdOrUuid } = require('../utils/idHelper');

exports.getPayments = async (req, res, next) => {
  try {
    const { invoiceId, customerId, page = 1, limit = 50 } = req.query;
    const safePage = Math.max(1, parseInt(page, 10) || 1);
    const safeLimit = Math.min(Math.max(1, parseInt(limit, 10) || 50), 200);
    const query = {};

    if (invoiceId) query.invoiceId = invoiceId;
    if (customerId) query.customerId = customerId;

    const skip = (safePage - 1) * safeLimit;
    const [payments, total] = await Promise.all([
      Payment.find(query).sort({ paymentDate: -1 }).skip(skip).limit(safeLimit),
      Payment.countDocuments(query)
    ]);

    res.json({
      success: true,
      data: payments,
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

exports.recordPayment = async (req, res, next) => {
  try {
    const {
      invoiceId,
      amount,
      paymentMethod = 'upi',
      referenceNumber,
      paymentDate = new Date(),
      notes,
      deviceId
    } = req.body;

    const paymentAmount = Number(amount);
    if (!paymentAmount || paymentAmount <= 0) {
      return res.status(400).json({ success: false, message: 'Payment amount must be greater than zero.' });
    }

    const invoice = await Invoice.findOne(findByIdOrUuid(invoiceId));

    if (!invoice) {
      return res.status(404).json({ success: false, message: 'Invoice not found.' });
    }

    if (invoice.status === 'cancelled') {
      return res.status(400).json({ success: false, message: 'Cannot record payment for a cancelled invoice.' });
    }

    if (paymentAmount > invoice.balanceDue) {
      return res.status(400).json({
        success: false,
        message: `Payment amount (₹${paymentAmount}) cannot exceed the balance due (₹${invoice.balanceDue}).`
      });
    }

    const uuid = req.body.uuid || uuidv4();

    // 1. Create Payment record
    const payment = await Payment.create({
      uuid,
      invoiceId: invoice.uuid,
      invoiceNumber: invoice.invoiceNumber,
      customerId: invoice.customer.uuid,
      customerName: invoice.customer.name,
      amount: paymentAmount,
      paymentMethod,
      referenceNumber: referenceNumber || '',
      paymentDate: new Date(paymentDate),
      notes: notes || '',
      receivedBy: req.user ? req.user.name : 'Owner',
      deviceId
    });

    // 2. Update Invoice totals & status
    invoice.totalPaid = Math.round(((invoice.totalPaid || 0) + paymentAmount) * 100) / 100;
    invoice.balanceDue = Math.max(0, Math.round((invoice.grandTotal - invoice.totalPaid) * 100) / 100);

    if (invoice.balanceDue === 0) {
      invoice.paymentStatus = 'paid';
    } else {
      invoice.paymentStatus = 'partially_paid';
    }

    await invoice.save();

    // 3. Update Customer ledger
    if (invoice.customer && invoice.customer.uuid) {
      await Customer.updateOne(
        { uuid: invoice.customer.uuid },
        {
          $inc: {
            totalPaid: paymentAmount,
            outstandingBalance: -paymentAmount
          }
        }
      );
    }

    // 4. Audit Log
    await AuditLog.create({
      action: 'RECORD_PAYMENT',
      entity: 'Payment',
      entityId: payment.uuid,
      performedBy: req.user ? req.user.name : 'Owner',
      role: req.user ? req.user.role : 'owner',
      deviceId,
      details: {
        invoiceNumber: invoice.invoiceNumber,
        amount: paymentAmount,
        paymentMethod
      }
    });

    res.status(201).json({
      success: true,
      message: 'Payment recorded successfully',
      data: {
        payment,
        invoiceSummary: {
          invoiceNumber: invoice.invoiceNumber,
          grandTotal: invoice.grandTotal,
          totalPaid: invoice.totalPaid,
          balanceDue: invoice.balanceDue,
          paymentStatus: invoice.paymentStatus
        }
      }
    });
  } catch (error) {
    next(error);
  }
};
