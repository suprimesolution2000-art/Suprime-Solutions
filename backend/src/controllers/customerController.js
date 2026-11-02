const Customer = require('../models/Customer');
const Invoice = require('../models/Invoice');
const Payment = require('../models/Payment');
const { v4: uuidv4 } = require('uuid');
const { findByIdOrUuid } = require('../utils/idHelper');
const { escapeRegex } = require('../utils/regexHelper');

// Universal customer search & list
exports.getCustomers = async (req, res, next) => {
  try {
    const { search, page = 1, limit = 50 } = req.query;
    const safePage = Math.max(1, parseInt(page, 10) || 1);
    const safeLimit = Math.min(Math.max(1, parseInt(limit, 10) || 50), 200);
    const query = { active: true };

    if (search && search.trim()) {
      const regex = new RegExp(escapeRegex(search.trim()), 'i');
      query.$or = [
        { name: regex },
        { businessName: regex },
        { phone: regex },
        { gstin: regex }
      ];
    }

    const skip = (safePage - 1) * safeLimit;
    const [customers, total] = await Promise.all([
      Customer.find(query).sort({ name: 1 }).skip(skip).limit(safeLimit),
      Customer.countDocuments(query)
    ]);

    res.json({
      success: true,
      data: customers,
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

exports.getCustomerById = async (req, res, next) => {
  try {
    const customer = await Customer.findOne(findByIdOrUuid(req.params.id));

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
    const customer = await Customer.findOne(findByIdOrUuid(req.params.id));

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
    const {
      name, businessName, phone, email, gstin, address, city, state, stateCode, pincode, active
    } = req.body;

    const updateFields = { updatedAt: new Date() };
    if (name !== undefined) updateFields.name = name.trim();
    if (businessName !== undefined) updateFields.businessName = businessName ? businessName.trim() : '';
    if (phone !== undefined) updateFields.phone = phone ? phone.trim() : '';
    if (email !== undefined) updateFields.email = email ? email.trim() : '';
    if (gstin !== undefined) updateFields.gstin = gstin ? gstin.trim().toUpperCase() : '';
    if (address !== undefined) updateFields.address = address ? address.trim() : '';
    if (city !== undefined) updateFields.city = city.trim();
    if (state !== undefined) updateFields.state = state.trim();
    if (stateCode !== undefined) updateFields.stateCode = stateCode.trim();
    if (pincode !== undefined) updateFields.pincode = pincode.trim();
    if (active !== undefined) updateFields.active = Boolean(active);

    const customer = await Customer.findOneAndUpdate(
      findByIdOrUuid(req.params.id),
      { $set: updateFields },
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

exports.deleteCustomer = async (req, res, next) => {
  try {
    const customer = await Customer.findOneAndUpdate(
      findByIdOrUuid(req.params.id),
      { $set: { active: false, updatedAt: new Date() } },
      { new: true }
    );

    if (!customer) {
      return res.status(404).json({ success: false, message: 'Customer not found.' });
    }

    res.json({ success: true, message: 'Customer deleted successfully' });
  } catch (error) {
    next(error);
  }
};
