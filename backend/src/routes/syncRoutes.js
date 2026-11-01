const express = require('express');
const router = express.Router();
const syncController = require('../controllers/syncController');
const authMiddleware = require('../middleware/auth');

router.use(authMiddleware);

router.post('/device/register', syncController.registerDevice);
router.post('/push', syncController.pushSync);
router.get('/pull', syncController.pullSync);

module.exports = router;
