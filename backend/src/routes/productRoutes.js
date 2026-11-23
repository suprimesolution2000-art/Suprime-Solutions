const express = require('express');
const router = express.Router();
const productController = require('../controllers/productController');
const authMiddleware = require('../middleware/auth');
const { isOwner } = require('../middleware/role');

router.use(authMiddleware);

router.get('/', productController.getProducts);
router.post('/', productController.createProduct);
router.put('/:id', productController.updateProduct);
router.delete('/:id', isOwner, productController.deleteProduct);

module.exports = router;
