const requireRole = (...allowedRoles) => {
  return (req, res, next) => {
    if (!req.user || !req.user.role) {
      return res.status(403).json({ success: false, message: 'Access denied. Role not specified.' });
    }

    if (!allowedRoles.includes(req.user.role)) {
      return res.status(403).json({
        success: false,
        message: `Forbidden: This action requires [${allowedRoles.join(', ')}] role. Current role is ${req.user.role}.`
      });
    }

    next();
  };
};

module.exports = {
  requireRole,
  isOwner: requireRole('owner')
};
