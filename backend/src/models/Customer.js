const mongoose = require('mongoose');

const customerSchema = new mongoose.Schema({
  uuid: {
    type: String,
    required: true,
    unique: true
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
    lowercase: true,
    validate: {
      validator: (v) => !v || /^[\w-.]+@([\w-]+\.)+[\w-]{2,4}$/.test(v),
      message: 'Please provide a valid email address'
    }
  },
  gstin: {
    type: String,
    trim: true,
    uppercase: true,
    index: true,
    validate: {
      validator: (v) => !v || /^[0-9]{2}[A-Z]{5}[0-9]{4}[A-Z]{1}[1-9A-Z]{1}Z[0-9A-Z]{1}$/.test(v),
      message: 'Please provide a valid 15-character GSTIN format'
    }
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
