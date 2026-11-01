const Invoice = require('../models/Invoice');
const Payment = require('../models/Payment');
const Customer = require('../models/Customer');

exports.getDashboardSummary = async (req, res, next) => {
  try {
    const today = new Date();
    today.setHours(0, 0, 0, 0);

    const firstDayOfMonth = new Date(today.getFullYear(), today.getMonth(), 1);

    // 1. Today's sales
    const todayInvoices = await Invoice.find({
      invoiceDate: { $gte: today },
      status: { $ne: 'cancelled' }
    });
    const todaySales = todayInvoices.reduce((acc, inv) => acc + (inv.grandTotal || 0), 0);
    const todayInvoiceCount = todayInvoices.length;

    // 2. Month's sales
    const monthInvoices = await Invoice.find({
      invoiceDate: { $gte: firstDayOfMonth },
      status: { $ne: 'cancelled' }
    });
    const monthlySales = monthInvoices.reduce((acc, inv) => acc + (inv.grandTotal || 0), 0);
    const monthlyInvoiceCount = monthInvoices.length;

    // 3. Pending payments (all outstanding balance across non-cancelled invoices)
    const unpaidInvoices = await Invoice.find({
      status: { $ne: 'cancelled' },
      paymentStatus: { $in: ['unpaid', 'partially_paid', 'overdue'] }
    });
    const pendingPayments = unpaidInvoices.reduce((acc, inv) => acc + (inv.balanceDue || 0), 0);

    // 4. Total Customers
    const customerCount = await Customer.countDocuments({ active: true });

    res.json({
      success: true,
      data: {
        todaySales: Math.round(todaySales * 100) / 100,
        todayInvoiceCount,
        monthlySales: Math.round(monthlySales * 100) / 100,
        monthlyInvoiceCount,
        pendingPayments: Math.round(pendingPayments * 100) / 100,
        pendingInvoicesCount: unpaidInvoices.length,
        customerCount
      }
    });
  } catch (error) {
    next(error);
  }
};

exports.getSalesReport = async (req, res, next) => {
  try {
    const { startDate, endDate } = req.query;
    const query = { status: { $ne: 'cancelled' } };

    if (startDate || endDate) {
      query.invoiceDate = {};
      if (startDate) query.invoiceDate.$gte = new Date(startDate);
      if (endDate) {
        const end = new Date(endDate);
        end.setHours(23, 59, 59, 999);
        query.invoiceDate.$lte = end;
      }
    }

    const invoices = await Invoice.find(query).sort({ invoiceDate: -1 });

    const totalSales = invoices.reduce((acc, inv) => acc + (inv.grandTotal || 0), 0);
    const totalTaxable = invoices.reduce((acc, inv) => acc + (inv.netAmount || 0), 0);
    const totalCgst = invoices.reduce((acc, inv) => acc + (inv.cgstTotal || 0), 0);
    const totalSgst = invoices.reduce((acc, inv) => acc + (inv.sgstTotal || 0), 0);
    const totalIgst = invoices.reduce((acc, inv) => acc + (inv.igstTotal || 0), 0);

    res.json({
      success: true,
      summary: {
        count: invoices.length,
        totalSales: Math.round(totalSales * 100) / 100,
        totalTaxable: Math.round(totalTaxable * 100) / 100,
        totalCgst: Math.round(totalCgst * 100) / 100,
        totalSgst: Math.round(totalSgst * 100) / 100,
        totalIgst: Math.round(totalIgst * 100) / 100
      },
      data: invoices
    });
  } catch (error) {
    next(error);
  }
};

exports.getOutstandingReport = async (req, res, next) => {
  try {
    const customers = await Customer.find({
      outstandingBalance: { $gt: 0 },
      active: true
    }).sort({ outstandingBalance: -1 });

    const totalOutstanding = customers.reduce((acc, c) => acc + (c.outstandingBalance || 0), 0);

    res.json({
      success: true,
      summary: {
        totalOutstanding: Math.round(totalOutstanding * 100) / 100,
        partyCount: customers.length
      },
      data: customers
    });
  } catch (error) {
    next(error);
  }
};
