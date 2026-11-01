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

    // If MongoDB is reachable, verify active user; otherwise use token payload
    try {
      const user = await User.findById(decoded.id).select('-passwordHash');
      if (user && !user.active) {
        return res.status(403).json({ success: false, message: 'User account is inactive.' });
      }
      req.user = user || decoded;
    } catch {
      req.user = decoded;
    }

    next();
  } catch (error) {
    return res.status(401).json({ success: false, message: 'Invalid or expired token.', error: error.message });
  }
};

module.exports = authMiddleware;
