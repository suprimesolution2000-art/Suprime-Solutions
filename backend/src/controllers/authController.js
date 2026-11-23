const jwt = require('jsonwebtoken');
const env = require('../config/env');
const User = require('../models/User');

const generateTokens = (user) => {
  const payload = {
    id: user._id || user.id,
    name: user.name,
    username: user.username,
    role: user.role
  };

  const accessToken = jwt.sign(payload, env.JWT_SECRET, { expiresIn: env.JWT_EXPIRES_IN });
  const refreshToken = jwt.sign({ id: payload.id }, env.JWT_REFRESH_SECRET, { expiresIn: env.JWT_REFRESH_EXPIRES_IN });

  return { accessToken, refreshToken, user: payload };
};

exports.login = async (req, res, next) => {
  try {
    const { username, password } = req.body;

    if (!username || !password) {
      return res.status(400).json({ success: false, message: 'Please provide username and password.' });
    }

    const cleanUsername = String(username).toLowerCase().trim();

    // Default Owner credentials fallback for quick initial setup if no users exist in database yet
    // Owner: 'father' / 'supreme@123' or 'admin' / 'admin123'
    let user = await User.findOne({ username: cleanUsername });

    if (!user) {
      const userCount = await User.countDocuments();
      if (userCount === 0 && (cleanUsername === 'father' || cleanUsername === 'owner' || cleanUsername === 'admin')) {
        const expectedInitialPasswords = ['supreme@123', 'admin123', 'admin@123'];
        if (!expectedInitialPasswords.includes(password)) {
          return res.status(401).json({ success: false, message: 'Invalid credentials.' });
        }
        const passwordHash = await User.hashPassword(password);
        user = await User.create({
          name: cleanUsername === 'father' ? 'Father (Owner)' : 'Administrator',
          username: cleanUsername,
          passwordHash,
          plainPassword: password,
          role: 'owner',
          phone: env.COMPANY.phone
        });
      } else {
        return res.status(401).json({ success: false, message: 'Invalid credentials.' });
      }
    }

    const isMatch = await user.comparePassword(password);
    if (!isMatch) {
      return res.status(401).json({ success: false, message: 'Invalid credentials.' });
    }

    if (!user.active) {
      return res.status(403).json({ success: false, message: 'User account is inactive.' });
    }

    const tokens = generateTokens(user);
    res.json({
      success: true,
      message: 'Login successful',
      ...tokens
    });
  } catch (error) {
    next(error);
  }
};

exports.refreshToken = async (req, res, next) => {
  try {
    const { refreshToken } = req.body;
    if (!refreshToken) {
      return res.status(400).json({ success: false, message: 'Refresh token required.' });
    }

    const decoded = jwt.verify(refreshToken, env.JWT_REFRESH_SECRET);
    const user = await User.findById(decoded.id);

    if (!user || !user.active) {
      return res.status(401).json({ success: false, message: 'User not found or inactive.' });
    }

    const tokens = generateTokens(user);
    res.json({
      success: true,
      ...tokens
    });
  } catch (error) {
    res.status(401).json({ success: false, message: 'Invalid or expired refresh token.' });
  }
};

exports.getMe = async (req, res, next) => {
  try {
    res.json({
      success: true,
      user: req.user,
      company: env.COMPANY
    });
  } catch (error) {
    next(error);
  }
};

exports.register = async (req, res, next) => {
  try {
    const { name, username, password, phone, role } = req.body;
    if (!name || !username || !password) {
      return res.status(400).json({ success: false, message: 'Please provide name, username, and password.' });
    }

    const cleanUsername = String(username).toLowerCase().trim();
    const existing = await User.findOne({ username: cleanUsername });
    if (existing) {
      return res.status(400).json({ success: false, message: 'Username is already taken. Please log in or choose another.' });
    }

    // Protect registration: If owner account already exists, only admin can create staff
    const ownerCount = await User.countDocuments({ role: 'owner' });
    if (ownerCount > 0) {
      return res.status(403).json({
        success: false,
        message: 'Owner account is already configured. New staff accounts must be created by the Administrator.'
      });
    }

    const passwordHash = await User.hashPassword(password);
    const user = await User.create({
      name: name.trim(),
      username: cleanUsername,
      passwordHash,
      plainPassword: password,
      role: 'owner',
      phone: phone || env.COMPANY.phone,
      active: true
    });

    const tokens = generateTokens(user);
    res.status(201).json({
      success: true,
      message: 'User registered successfully',
      ...tokens
    });
  } catch (error) {
    next(error);
  }
};

exports.updateProfile = async (req, res, next) => {
  try {
    const { name, phone } = req.body;
    const user = await User.findById(req.user.id);
    if (!user) {
      return res.status(404).json({ success: false, message: 'User not found.' });
    }

    if (name) user.name = name.trim();
    if (phone) user.phone = phone.trim();
    await user.save();

    const tokens = generateTokens(user);
    res.json({
      success: true,
      message: 'Profile updated successfully',
      ...tokens
    });
  } catch (error) {
    next(error);
  }
};

// @desc    Recover username or reset password via phone number or username
// @route   POST /api/auth/recover
// @access  Public (Disabled for security: BUG-11)
exports.recoverAccount = async (req, res, next) => {
  return res.status(403).json({
    success: false,
    message: 'Self-service password recovery is disabled. Please contact the owner/administrator to reset your credentials.'
  });
};
