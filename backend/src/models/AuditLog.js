const mongoose = require('mongoose');

const auditLogSchema = new mongoose.Schema({
  action: {
    type: String,
    required: true,
    index: true // e.g. "CREATE_INVOICE", "CANCEL_INVOICE", "RECORD_PAYMENT"
  },
  entity: {
    type: String,
    required: true,
    index: true // e.g. "Invoice", "Payment", "Customer"
  },
  entityId: {
    type: String,
    required: true,
    index: true
  },
  performedBy: {
    type: String,
    required: true
  },
  role: {
    type: String,
    required: true
  },
  deviceId: {
    type: String
  },
  ipAddress: {
    type: String
  },
  details: {
    type: mongoose.Schema.Types.Mixed
  }
}, {
  timestamps: true
});

// Auto-clean audit logs older than 1 year (TTL index)
auditLogSchema.index({ createdAt: 1 }, { expireAfterSeconds: 365 * 24 * 60 * 60 });

module.exports = mongoose.model('AuditLog', auditLogSchema);
