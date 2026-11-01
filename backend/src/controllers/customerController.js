const Customer = require('../models/Customer');
const Invoice = require('../models/Invoice');
const Payment = require('../models/Payment');
const { v4: uuidv4 } = require('uuid');

// Universal customer search & list
exports.getCustomers = async (req, res, next) => {
  try {
    const { search, page = 1, limit = 50 } = req.query;
    const query = { active: true };

    if (search && search.trim()) {
      const regex = new RegExp(search.trim(), 'i');
      query.$or = [
        { name: regex },
        { businessName: regex },
        { phone: regex },
        { gstin: regex }
      ];
    }

    const skip = (Number(page) - 1) * Number(limit);
    const [customers, total] = await Promise.all([
      Customer.find(query).sort({ name: 1 }).skip(skip).limit(Number(limit)),
      Customer.countDocuments(query)
    ]);

    res.json({
      success: true,
      data: customers,
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

exports.getCustomerById = async (req, res, next) => {
  try {
    const customer = await Customer.findOne({
      $or: [{ _id: req.params.id }, { uuid: req.params.id }]
    });

    if (!customer) {
      return res.status(404).json({ success: false, message: 'Customer not found.' });
    }

    res.json({ success: true, data: customer });
  } catch (error) {
    next(error);
  }
};

// Customer Ledger (invoices, payments, balance)
exports.getCustomerLedger = async (req, res, next) => {
  try {
    const customerId = req.params.id;
    const customer = await Customer.findOne({
      $or: [{ _id: customerId }, { uuid: customerId }]
    });

    if (!customer) {
      return res.status(404).json({ success: false, message: 'Customer not found.' });
    }

    const customerMatch = [{ 'customer.uuid': customer.uuid }];
    if (customer.phone && customer.phone.trim()) {
      customerMatch.push({ 'customer.phone': customer.phone.trim() });
    }

    const [invoices, payments] = await Promise.all([
      Invoice.find({
        $or: customerMatch,
        status: { $ne: 'cancelled' }
      }).sort({ invoiceDate: -1 }),
      Payment.find({
        $or: [{ customerId: customer.uuid }, { customerId: customer._id }]
      }).sort({ paymentDate: -1 })
    ]);

    const totalBilled = invoices.reduce((acc, inv) => acc + (inv.grandTotal || 0), 0);
    const totalPaid = payments.reduce((acc, p) => acc + (p.amount || 0), 0);
    const outstandingBalance = Math.round((totalBilled - totalPaid) * 100) / 100;

    res.json({
      success: true,
      data: {
        customer,
        summary: {
          totalBilled,
          totalPaid,
          outstandingBalance
        },
        invoices,
        payments
      }
    });
  } catch (error) {
    next(error);
  }
};

exports.createCustomer = async (req, res, next) => {
  try {
    const { name, businessName, phone, email, gstin, address, city, state, stateCode, pincode } = req.body;

    if (!name || !name.trim()) {
      return res.status(400).json({ success: false, message: 'Customer Name is required.' });
    }

    const uuid = req.body.uuid || uuidv4();

    const customer = await Customer.create({
      uuid,
      name: name.trim(),
      businessName: businessName ? businessName.trim() : '',
      phone: phone ? phone.trim() : '',
      email: email ? email.trim() : '',
      gstin: gstin ? gstin.trim().toUpperCase() : '',
      address: address ? address.trim() : '',
      city: city || 'Bilaspur',
      state: state || 'Chhattisgarh',
      stateCode: stateCode || '22',
      pincode: pincode || ''
    });

    res.status(201).json({ success: true, message: 'Customer created successfully', data: customer });
  } catch (error) {
    next(error);
  }
};

exports.updateCustomer = async (req, res, next) => {
  try {
    const customer = await Customer.findOneAndUpdate(
      { $or: [{ _id: req.params.id }, { uuid: req.params.id }] },
      { $set: req.body },
      { new: true }
    );

    if (!customer) {
      return res.status(404).json({ success: false, message: 'Customer not found.' });
    }

    res.json({ success: true, message: 'Customer updated successfully', data: customer });
  } catch (error) {
    next(error);
  }
};
