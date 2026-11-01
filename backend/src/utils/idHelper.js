const mongoose = require('mongoose');

/**
 * Returns a safe query condition that works for both MongoDB ObjectId (24 hex chars) and UUID strings
 * without throwing Mongoose CastError.
 */
function findByIdOrUuid(id) {
  if (!id) return { _id: null };
  const strId = String(id).trim();
  const isMongoId = mongoose.Types.ObjectId.isValid(strId) && strId.length === 24;
  return isMongoId ? { $or: [{ _id: strId }, { uuid: strId }] } : { uuid: strId };
}

module.exports = { findByIdOrUuid };
