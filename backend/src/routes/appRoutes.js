const express = require('express');
const router = express.Router();
const { getLatestRelease, downloadLatestApk } = require('../controllers/appController');

// Open endpoint to check latest version (no auth required)
router.get('/version', getLatestRelease);

// Direct high-speed download endpoint (no auth required)
router.get('/download', downloadLatestApk);

module.exports = router;
