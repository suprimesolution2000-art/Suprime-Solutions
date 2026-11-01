const express = require('express');
const router = express.Router();
const paymentController = require('../controllers/paymentController');
const authMiddleware = require('../middleware/auth');

router.use(authMiddleware);

router.get('/', paymentController.getPayments);
router.post('/', paymentController.recordPayment);

module.exports = router;
