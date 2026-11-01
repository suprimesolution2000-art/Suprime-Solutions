const mongoose = require('mongoose');

const productSchema = new mongoose.Schema({
  uuid: {
    type: String,
    required: true,
    unique: true,
    index: true
  },
  description: {
    type: String,
    required: true,
    trim: true,
    index: true
  },
  hsnCode: {
    type: String,
    trim: true,
    index: true
  },
  unit: {
    type: String,
    required: true,
    default: 'PCS'
  },
  defaultRate: {
    type: Number,
    required: true,
    default: 0
  },
  gstRate: {
    type: Number,
    required: true,
    default: 18.0
  },
  active: {
    type: Boolean,
    default: true
  }
}, {
  timestamps: true
});

productSchema.index({ description: 'text', hsnCode: 'text' });

module.exports = mongoose.model('Product', productSchema);
