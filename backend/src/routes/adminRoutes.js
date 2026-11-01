const express = require('express');
const router = express.Router();
const adminController = require('../controllers/adminController');
const authMiddleware = require('../middleware/auth');
const { isOwner } = require('../middleware/role');

// All admin routes require authentication AND owner/admin role
router.use(authMiddleware);
router.use(isOwner);

router.get('/users', adminController.getAllUsers);
router.post('/users', adminController.createUser);
router.put('/users/:id/password', adminController.resetUserPassword);
router.delete('/users/:id', adminController.deleteUser);

module.exports = router;
