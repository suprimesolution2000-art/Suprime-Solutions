const mongoose = require('mongoose');

const deviceSchema = new mongoose.Schema({
  deviceId: {
    type: String,
    required: true,
    unique: true
  },
  deviceName: {
    type: String,
    required: true
  },
  registeredUser: {
    type: String,
    required: true
  },
  active: {
    type: Boolean,
    default: true
  },
  lastSyncAt: {
    type: Date,
    default: Date.now
  },
  currentRangeFrom: {
    type: Number,
    default: 0
  },
  currentRangeTo: {
    type: Number,
    default: 0
  },
  nextUsableNumber: {
    type: Number,
    default: 0
  }
}, {
  timestamps: true
});

module.exports = mongoose.model('Device', deviceSchema);
