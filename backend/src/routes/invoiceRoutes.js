const express = require('express');
const router = express.Router();
const invoiceController = require('../controllers/invoiceController');
const authMiddleware = require('../middleware/auth');
const { isOwner } = require('../middleware/role');

router.use(authMiddleware);

router.get('/', invoiceController.getInvoices);
router.post('/', invoiceController.createInvoice);
router.get('/:id', invoiceController.getInvoiceById);
router.put('/:id', invoiceController.updateInvoice);
router.get('/:id/pdf', invoiceController.getInvoicePdf);
router.post('/:id/cancel', isOwner, invoiceController.cancelInvoice);
router.delete('/:id', isOwner, invoiceController.deleteInvoice);

module.exports = router;
