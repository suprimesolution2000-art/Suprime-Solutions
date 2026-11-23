const express = require('express');
const router = express.Router();
const reportController = require('../controllers/reportController');
const authMiddleware = require('../middleware/auth');

router.use(authMiddleware);

router.get('/dashboard', reportController.getDashboardSummary);
router.get('/sales', reportController.getSalesReport);
router.get('/sales/gstr1-pdf', reportController.getGstSalesRegisterPdf);
router.get('/sales/temporary-register-pdf', reportController.getTemporaryBillsRegisterPdf);
router.get('/outstanding', reportController.getOutstandingReport);

module.exports = router;
