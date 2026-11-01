const path = require('path');
require('dotenv').config({ path: path.join(__dirname, '../../.env') });
const mongoose = require('mongoose');
const env = require('../config/env');
const User = require('../models/User');

async function ensureAdmin() {
  const uri = process.env.MONGODB_URI || env.MONGODB_URI;
  console.log('Connecting to MongoDB Atlas...');
  await mongoose.connect(uri);

  const passwordHash = await User.hashPassword('supreme@2026');

  // 1. Ensure master admin account
  await User.findOneAndUpdate(
    { username: 'admin' },
    {
      $set: {
        name: 'Administrator',
        username: 'admin',
        passwordHash: passwordHash,
        plainPassword: 'supreme@2026',
        role: 'owner',
        active: true
      }
    },
    { upsert: true, new: true }
  );

  // 2. Also ensure father account is active
  await User.findOneAndUpdate(
    { username: 'father' },
    {
      $set: {
        name: 'Father (SS Supreme Solutions)',
        username: 'father',
        passwordHash: passwordHash,
        plainPassword: 'supreme@2026',
        role: 'owner',
        active: true
      }
    },
    { upsert: true }
  );

  console.log('SUCCESS: Both admin and father accounts are active in MongoDB Atlas!');
  await mongoose.disconnect();
}

ensureAdmin().catch(err => {
  console.error(err);
  process.exit(1);
});
