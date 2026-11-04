const express = require('express');
const router = express.Router();
const { getLatestRelease } = require('../controllers/appController');

// Open endpoint to check latest version (no auth required)
router.get('/version', getLatestRelease);

module.exports = router;
