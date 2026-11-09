const mongoose = require('mongoose');

const invoiceSequenceSchema = new mongoose.Schema({
  financialYear: {
    type: String,
    required: true,
    unique: true // e.g., '26-27'
  },
  currentNumber: {
    type: Number,
    required: true,
    default: 0
  },
  currentTemporaryNumber: {
    type: Number,
    required: true,
    default: 0
  },
  reservedBlocks: [{
    deviceId: { type: String, required: true },
    deviceName: { type: String },
    fromNumber: { type: Number, required: true },
    toNumber: { type: Number, required: true },
    reservedAt: { type: Date, default: Date.now },
    isExhausted: { type: Boolean, default: false }
  }]
}, {
  timestamps: true
});

module.exports = mongoose.model('InvoiceSequence', invoiceSequenceSchema);
