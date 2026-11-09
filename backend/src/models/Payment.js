const mongoose = require('mongoose');

const paymentSchema = new mongoose.Schema({
  uuid: {
    type: String,
    required: true,
    unique: true
  },
  invoiceId: {
    type: String,
    required: true,
    index: true // Invoice UUID
  },
  invoiceNumber: {
    type: String,
    required: true,
    index: true
  },
  customerId: {
    type: String,
    required: true,
    index: true
  },
  customerName: {
    type: String,
    required: true
  },
  amount: {
    type: Number,
    required: true,
    min: 0.01
  },
  paymentMethod: {
    type: String,
    enum: ['cash', 'upi', 'bank_transfer', 'cheque', 'other'],
    required: true,
    default: 'upi'
  },
  referenceNumber: {
    type: String,
    trim: true,
    default: ''
  },
  paymentDate: {
    type: Date,
    required: true,
    default: Date.now,
    index: true
  },
  notes: {
    type: String,
    trim: true
  },
  receivedBy: {
    type: String,
    required: true
  },
  deviceId: {
    type: String
  }
}, {
  timestamps: true
});

module.exports = mongoose.model('Payment', paymentSchema);
