const User = require('../models/User');

// GET /api/admin/users - List all users (Admin only)
exports.getAllUsers = async (req, res, next) => {
  try {
    const users = await User.find({})
      .select('-passwordHash')
      .sort({ createdAt: -1 });

    res.json({
      success: true,
      count: users.length,
      data: users
    });
  } catch (error) {
    next(error);
  }
};

// POST /api/admin/users - Create new user account (Admin only)
exports.createUser = async (req, res, next) => {
  try {
    const { name, username, password, phone, role } = req.body;

    if (!name || !username || !password) {
      return res.status(400).json({
        success: false,
        message: 'Name, username, and password are required.'
      });
    }

    if (password.length < 6) {
      return res.status(400).json({
        success: false,
        message: 'Password must be at least 6 characters long.'
      });
    }

    const cleanUsername = username.trim().toLowerCase();
    const existing = await User.findOne({ username: cleanUsername });
    if (existing) {
      return res.status(400).json({
        success: false,
        message: `Username '${cleanUsername}' already exists. Please choose a different username.`
      });
    }

    const passwordHash = await User.hashPassword(password);
    const userRole = role === 'owner' ? 'owner' : 'employee';

    const user = await User.create({
      name: name.trim(),
      username: cleanUsername,
      passwordHash,
      plainPassword: password,
      phone: phone ? phone.trim() : null,
      role: userRole,
      active: true
    });

    res.status(201).json({
      success: true,
      message: `Account for ${user.name} created successfully.`,
      user: {
        id: user._id,
        name: user.name,
        username: user.username,
        role: user.role,
        phone: user.phone,
        plainPassword: user.plainPassword
      }
    });
  } catch (error) {
    next(error);
  }
};

// PUT /api/admin/users/:id/password - Reset any user password (Admin only)
exports.resetUserPassword = async (req, res, next) => {
  try {
    const { id } = req.params;
    const { newPassword } = req.body;

    if (!newPassword || newPassword.length < 6) {
      return res.status(400).json({
        success: false,
        message: 'New password must be at least 6 characters long.'
      });
    }

    const user = await User.findById(id);
    if (!user) {
      return res.status(404).json({
        success: false,
        message: 'User account not found.'
      });
    }

    user.passwordHash = await User.hashPassword(newPassword);
    user.plainPassword = newPassword;
    await user.save();

    res.json({
      success: true,
      message: `Password for ${user.name} (@${user.username}) updated successfully.`,
      user: {
        id: user._id,
        name: user.name,
        username: user.username,
        role: user.role,
        plainPassword: user.plainPassword
      }
    });
  } catch (error) {
    next(error);
  }
};

// DELETE /api/admin/users/:id - Delete user account (Admin only)
exports.deleteUser = async (req, res, next) => {
  try {
    const { id } = req.params;

    if (req.user && String(req.user.id || req.user._id) === String(id)) {
      return res.status(400).json({
        success: false,
        message: 'Cannot delete your own active administrator account.'
      });
    }

    const user = await User.findByIdAndDelete(id);
    if (!user) {
      return res.status(404).json({
        success: false,
        message: 'User account not found.'
      });
    }

    res.json({
      success: true,
      message: `User account @${user.username} deleted successfully.`
    });
  } catch (error) {
    next(error);
  }
};
