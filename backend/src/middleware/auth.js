const jwt = require('jsonwebtoken');
const env = require('../config/env');
const User = require('../models/User');

const authMiddleware = async (req, res, next) => {
  try {
    const authHeader = req.headers.authorization;
    if (!authHeader || !authHeader.startsWith('Bearer ')) {
      return res.status(401).json({ success: false, message: 'Authentication required. No token provided.' });
    }

    const token = authHeader.split(' ')[1];
    const decoded = jwt.verify(token, env.JWT_SECRET);

    // Verify user exists and is active in database
    const user = await User.findById(decoded.id).select('-passwordHash -plainPassword');
    if (!user) {
      return res.status(401).json({ success: false, message: 'User account not found.' });
    }
    if (!user.active) {
      return res.status(403).json({ success: false, message: 'User account is inactive.' });
    }
    req.user = user;

    next();
  } catch (error) {
    if (error.name === 'TokenExpiredError' || error.name === 'JsonWebTokenError') {
      return res.status(401).json({ success: false, message: 'Invalid or expired token.' });
    }
    return res.status(503).json({ success: false, message: 'Service temporarily unavailable. Database connection error.' });
  }
};

module.exports = authMiddleware;
