const Invoice = require('../models/Invoice');
const Payment = require('../models/Payment');
const Customer = require('../models/Customer');
const pdfService = require('../services/pdfService');

exports.getDashboardSummary = async (req, res, next) => {
  try {
    const today = new Date();
    today.setHours(0, 0, 0, 0);

    const endOfToday = new Date(today);
    endOfToday.setHours(23, 59, 59, 999);

    const firstDayOfMonth = new Date(today.getFullYear(), today.getMonth(), 1);

    // Aggregate dashboard metrics in parallel on the database engine (B31)
    const [todayAgg, monthAgg, unpaidAgg, customerCount] = await Promise.all([
      Invoice.aggregate([
        {
          $match: {
            invoiceDate: { $gte: today, $lte: endOfToday },
            status: { $ne: 'cancelled' },
            invoiceType: { $ne: 'temporary' }
          }
        },
        {
          $group: {
            _id: null,
            totalSales: { $sum: '$grandTotal' },
            count: { $sum: 1 }
          }
        }
      ]),
      Invoice.aggregate([
        {
          $match: {
            invoiceDate: { $gte: firstDayOfMonth, $lte: endOfToday },
            status: { $ne: 'cancelled' },
            invoiceType: { $ne: 'temporary' }
          }
        },
        {
          $group: {
            _id: null,
            totalSales: { $sum: '$grandTotal' },
            count: { $sum: 1 }
          }
        }
      ]),
      Invoice.aggregate([
        {
          $match: {
            status: { $ne: 'cancelled' },
            paymentStatus: { $in: ['unpaid', 'partially_paid', 'overdue'] },
            invoiceType: { $ne: 'temporary' }
          }
        },
        {
          $group: {
            _id: null,
            totalPending: { $sum: '$balanceDue' },
            count: { $sum: 1 }
          }
        }
      ]),
      Customer.countDocuments({ active: true })
    ]);

    const todaySales = todayAgg[0]?.totalSales || 0;
    const todayInvoiceCount = todayAgg[0]?.count || 0;
    const monthlySales = monthAgg[0]?.totalSales || 0;
    const monthlyInvoiceCount = monthAgg[0]?.count || 0;
    const pendingPayments = unpaidAgg[0]?.totalPending || 0;
    const pendingInvoicesCount = unpaidAgg[0]?.count || 0;

    res.json({
      success: true,
      data: {
        todaySales: Math.round(todaySales * 100) / 100,
        todayInvoiceCount,
        monthlySales: Math.round(monthlySales * 100) / 100,
        monthlyInvoiceCount,
        pendingPayments: Math.round(pendingPayments * 100) / 100,
        pendingInvoicesCount,
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
    const query = { status: { $ne: 'cancelled' }, invoiceType: { $ne: 'temporary' } };

    if (startDate || endDate) {
      query.invoiceDate = {};
      if (startDate) query.invoiceDate.$gte = new Date(startDate);
      if (endDate) {
        const end = new Date(endDate);
        end.setHours(23, 59, 59, 999);
        query.invoiceDate.$lte = end;
      }
    }

    const invoices = await Invoice.find(query).sort({ invoiceDate: -1 }).lean();

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
    // Dynamically calculate live outstanding totals from active invoices (B15)
    const unpaidAggregates = await Invoice.aggregate([
      {
        $match: {
          status: { $ne: 'cancelled' },
          invoiceType: { $ne: 'temporary' },
          balanceDue: { $gt: 0.005 }
        }
      },
      {
        $group: {
          _id: '$customer.uuid',
          totalDue: { $sum: '$balanceDue' }
        }
      }
    ]);

    const dueMap = new Map();
    unpaidAggregates.forEach(agg => {
      if (agg._id) dueMap.set(agg._id, Math.round(agg.totalDue * 100) / 100);
    });

    // Include all customers so debts of deactivated parties are not hidden (BUG-10)
    const customers = await Customer.find({}).lean();
    const resultCustomers = [];
    let totalOutstanding = 0;

    for (const c of customers) {
      const liveDue = dueMap.get(c.uuid) || 0;
      if (liveDue > 0.005) {
        c.outstandingBalance = liveDue;
        resultCustomers.push(c);
        totalOutstanding += liveDue;
      }
    }

    resultCustomers.sort((a, b) => (b.outstandingBalance || 0) - (a.outstandingBalance || 0));

    res.json({
      success: true,
      summary: {
        totalOutstanding: Math.round(totalOutstanding * 100) / 100,
        partyCount: resultCustomers.length
      },
      data: resultCustomers
    });
  } catch (error) {
    next(error);
  }
};

exports.getGstSalesRegisterPdf = async (req, res, next) => {
  try {
    const { fromDate, toDate } = req.query;
    const start = fromDate ? new Date(fromDate) : new Date(new Date().getFullYear(), new Date().getMonth(), 1);
    const end = toDate ? new Date(toDate) : new Date();
    end.setHours(23, 59, 59, 999);

    const invoices = await Invoice.find({
      invoiceDate: { $gte: start, $lte: end },
      status: { $ne: 'cancelled' },
      invoiceType: { $ne: 'temporary' }
    }).sort({ invoiceDate: 1, sequenceNumber: 1 });

    const pdfBuffer = await pdfService.generateGstSalesRegisterPdf(invoices, start, end);
    res.setHeader('Content-Type', 'application/pdf');
    res.setHeader('Content-Disposition', 'inline; filename="GST_Sales_Register.pdf"');
    return res.send(pdfBuffer);
  } catch (error) {
    next(error);
  }
};

exports.getTemporaryBillsRegisterPdf = async (req, res, next) => {
  try {
    const { fromDate, toDate } = req.query;
    const start = fromDate ? new Date(fromDate) : new Date(new Date().getFullYear(), new Date().getMonth(), 1);
    const end = toDate ? new Date(toDate) : new Date();
    end.setHours(23, 59, 59, 999);

    const invoices = await Invoice.find({
      invoiceDate: { $gte: start, $lte: end },
      status: { $ne: 'cancelled' },
      invoiceType: 'temporary'
    }).sort({ invoiceDate: 1, sequenceNumber: 1 });

    const pdfBuffer = await pdfService.generateTemporaryBillsRegisterPdf(invoices, start, end);
    res.setHeader('Content-Type', 'application/pdf');
    res.setHeader('Content-Disposition', 'inline; filename="Temporary_Bills_Register.pdf"');
    return res.send(pdfBuffer);
  } catch (error) {
    next(error);
  }
};
