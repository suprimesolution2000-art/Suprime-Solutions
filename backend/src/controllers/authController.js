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
        const passwordHash = await User.hashPassword(password);
        user = await User.create({
          name: 'Father (Owner)',
          username: cleanUsername,
          passwordHash,
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

    const passwordHash = await User.hashPassword(password);
    const user = await User.create({
      name: name.trim(),
      username: cleanUsername,
      passwordHash,
      role: role || 'owner',
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
// @access  Public
exports.recoverAccount = async (req, res, next) => {
  try {
    const { phone, username, newPassword } = req.body;

    if (!phone && !username) {
      return res.status(400).json({
        success: false,
        message: 'Please provide either your registered mobile number or username.'
      });
    }

    const query = {};
    if (username) {
      query.username = String(username).toLowerCase().trim();
    } else if (phone) {
      query.phone = String(phone).trim();
    }

    const user = await User.findOne(query);
    if (!user) {
      return res.status(404).json({
        success: false,
        message: 'No account found matching this mobile number or username.'
      });
    }

    if (newPassword) {
      if (newPassword.length < 6) {
        return res.status(400).json({
          success: false,
          message: 'New password must be at least 6 characters.'
        });
      }
      user.passwordHash = await User.hashPassword(newPassword);
      await user.save();
    }

    res.json({
      success: true,
      message: newPassword ? 'Password reset successfully! You can now log in.' : 'Account found.',
      data: {
        username: user.username,
        name: user.name,
        role: user.role
      }
    });
  } catch (error) {
    next(error);
  }
};
