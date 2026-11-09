const mongoose = require('mongoose');

const invoiceItemSchema = new mongoose.Schema({
  sno: { type: Number, required: true },
  description: { type: String, required: true, trim: true },
  hsnCode: { type: String, trim: true, default: '' },
  quantity: { type: Number, required: true, min: 0 },
  unit: { type: String, required: true, default: 'PCS' },
  rate: { type: Number, required: true, min: 0 },
  discount: { type: Number, default: 0 },
  taxableValue: { type: Number, required: true },
  gstRate: { type: Number, required: true, default: 18.0 },
  cgstRate: { type: Number, default: 0 },
  cgstAmount: { type: Number, default: 0 },
  sgstRate: { type: Number, default: 0 },
  sgstAmount: { type: Number, default: 0 },
  igstRate: { type: Number, default: 0 },
  igstAmount: { type: Number, default: 0 },
  totalAmount: { type: Number, required: true }
}, { _id: false });

const invoiceSchema = new mongoose.Schema({
  uuid: {
    type: String,
    required: true,
    unique: true
  },
  invoiceNumber: {
    type: String,
    required: true,
    index: true // e.g. "SS/26-27/001" or "1"
  },
  sequenceNumber: {
    type: Number,
    required: true
  },
  financialYear: {
    type: String,
    required: true,
    index: true // e.g. "26-27"
  },
  invoiceDate: {
    type: Date,
    required: true,
    index: true
  },
  dueDate: {
    type: Date
  },
  poNumber: {
    type: String,
    trim: true,
    default: ''
  },
  poDate: {
    type: Date
  },
  challanNumber: {
    type: String,
    trim: true,
    default: ''
  },
  challanDate: {
    type: Date
  },
  // Snapshot of customer at time of billing
  customer: {
    uuid: { type: String, index: true },
    name: { type: String, required: true },
    businessName: { type: String, default: '' },
    phone: { type: String, default: '' },
    email: { type: String },
    gstin: { type: String },
    address: { type: String },
    city: { type: String },
    state: { type: String, required: true, default: 'Chhattisgarh' },
    stateCode: { type: String, required: true, default: '22' }
  },
  isInterState: {
    type: Boolean,
    required: true,
    default: false
  },
  items: [invoiceItemSchema],
  netAmount: {
    type: Number,
    required: true
  },
  cgstTotal: {
    type: Number,
    default: 0
  },
  sgstTotal: {
    type: Number,
    default: 0
  },
  igstTotal: {
    type: Number,
    default: 0
  },
  roundOff: {
    type: Number,
    default: 0
  },
  grandTotal: {
    type: Number,
    required: true,
    index: true
  },
  amountInWords: {
    type: String,
    required: true
  },
  status: {
    type: String,
    enum: ['draft', 'finalized', 'cancelled'],
    default: 'finalized',
    index: true
  },
  paymentStatus: {
    type: String,
    enum: ['unpaid', 'partially_paid', 'paid', 'overdue'],
    default: 'unpaid',
    index: true
  },
  totalPaid: {
    type: Number,
    default: 0
  },
  balanceDue: {
    type: Number,
    required: true
  },
  deviceId: {
    type: String,
    index: true
  },
  createdBy: {
    type: String,
    required: true
  },
  syncStatus: {
    type: String,
    enum: ['synced', 'local_only', 'conflict'],
    default: 'synced'
  },
  invoiceType: {
    type: String,
    enum: ['gst', 'temporary'],
    default: 'gst',
    index: true
  },
  active: {
    type: Boolean,
    default: true,
    index: true
  }
}, {
  timestamps: true
});

// Unique scoped per invoice type and financial year
invoiceSchema.index({ invoiceNumber: 1, invoiceType: 1, financialYear: 1 }, { unique: true });

// Full-text search index across invoice number, customer name, phone, gstin, PO, challan, and item descriptions
invoiceSchema.index({
  invoiceNumber: 'text',
  'customer.name': 'text',
  'customer.phone': 'text',
  'customer.gstin': 'text',
  'customer.businessName': 'text',
  poNumber: 'text',
  challanNumber: 'text',
  'items.description': 'text',
  'items.hsnCode': 'text'
});

module.exports = mongoose.model('Invoice', invoiceSchema);
