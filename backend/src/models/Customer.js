const mongoose = require('mongoose');

const customerSchema = new mongoose.Schema({
  uuid: {
    type: String,
    required: true,
    unique: true,
    index: true
  },
  name: {
    type: String,
    required: true,
    trim: true,
    index: true
  },
  businessName: {
    type: String,
    trim: true,
    index: true
  },
  phone: {
    type: String,
    required: false,
    default: '',
    trim: true,
    index: true
  },
  email: {
    type: String,
    trim: true,
    lowercase: true
  },
  gstin: {
    type: String,
    trim: true,
    uppercase: true,
    index: true
  },
  address: {
    type: String,
    trim: true
  },
  city: {
    type: String,
    trim: true,
    default: 'Bilaspur'
  },
  state: {
    type: String,
    trim: true,
    default: 'Chhattisgarh'
  },
  stateCode: {
    type: String,
    trim: true,
    default: '22'
  },
  pincode: {
    type: String,
    trim: true
  },
  outstandingBalance: {
    type: Number,
    default: 0
  },
  totalBilled: {
    type: Number,
    default: 0
  },
  totalPaid: {
    type: Number,
    default: 0
  },
  active: {
    type: Boolean,
    default: true
  }
}, {
  timestamps: true
});

// Text index for universal customer search
customerSchema.index({
  name: 'text',
  businessName: 'text',
  phone: 'text',
  gstin: 'text'
});

module.exports = mongoose.model('Customer', customerSchema);
