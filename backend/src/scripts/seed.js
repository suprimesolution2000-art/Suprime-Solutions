const mongoose = require('mongoose');
const bcrypt = require('bcryptjs');
const env = require('../config/env');
const connectDB = require('../config/db');
const User = require('../models/User');
const Product = require('../models/Product');
const InvoiceSequence = require('../models/InvoiceSequence');
const { getFinancialYear } = require('../services/invoiceService');

const seedData = async () => {
  console.log('--- Initializing SS Supreme Solutions Cloud Database Seed ---');
  await connectDB();

  try {
    // 1. Seed Owner / Admin User
    const existingOwner = await User.findOne({ username: 'father' });
    if (!existingOwner) {
      const salt = await bcrypt.genSalt(10);
      const hashedPassword = await bcrypt.hash('supreme@2026', salt);

      await User.create({
        name: 'Father (SS Supreme Solutions)',
        username: 'father',
        passwordHash: hashedPassword,
        role: 'owner',
        phone: env.COMPANY.phone,
        active: true
      });
      console.log('✔ Created Owner Account: Username = "father" (Password: supreme@2026)');
    } else {
      console.log('ℹ Owner account "father" already exists in MongoDB Atlas.');
    }

    // 2. Seed Standard Industrial Gasket & Hydraulic Hardware Items
    const standardProducts = [
      {
        uuid: 'prod-001',
        description: 'Spiral Wound Gasket 3" 150# CS/SS304/Graphite',
        hsnCode: '8484',
        unit: 'NOS',
        defaultRate: 420.00,
        gstRate: 18.0
      },
      {
        uuid: 'prod-002',
        description: 'Hydraulic Cylinder Seal Kit (D/A 80x50)',
        hsnCode: '8487',
        unit: 'SET',
        defaultRate: 1850.00,
        gstRate: 18.0
      },
      {
        uuid: 'prod-003',
        description: 'PTFE Virgin Teflon Gasket Sheet 3mm (1m x 1m)',
        hsnCode: '3920',
        unit: 'PCS',
        defaultRate: 3400.00,
        gstRate: 18.0
      },
      {
        uuid: 'prod-004',
        description: 'Non-Asbestos CAF Gasket 2" 300# Flange',
        hsnCode: '6812',
        unit: 'NOS',
        defaultRate: 195.00,
        gstRate: 18.0
      },
      {
        uuid: 'prod-005',
        description: 'Pure Flexible Expanded Graphite Packing Ring 25x35',
        hsnCode: '6815',
        unit: 'PCS',
        defaultRate: 140.00,
        gstRate: 18.0
      },
      {
        uuid: 'prod-006',
        description: 'High Pressure Hydraulic Hose Pipe R2 1/2" with End Fittings',
        hsnCode: '4009',
        unit: 'MTR',
        defaultRate: 750.00,
        gstRate: 18.0
      },
      {
        uuid: 'prod-007',
        description: 'Viton FKM O-Ring Industrial Seal Kit',
        hsnCode: '4016',
        unit: 'SET',
        defaultRate: 1200.00,
        gstRate: 18.0
      },
      {
        uuid: 'prod-008',
        description: 'Metal Jacketed Gasket 4" Class 150 Flange',
        hsnCode: '8484',
        unit: 'NOS',
        defaultRate: 650.00,
        gstRate: 18.0
      },
      {
        uuid: 'prod-009',
        description: 'Neoprene Rubber Gasket Sheet 5mm Oil Resistant',
        hsnCode: '4008',
        unit: 'MTR',
        defaultRate: 850.00,
        gstRate: 18.0
      }
    ];

    for (const prod of standardProducts) {
      await Product.findOneAndUpdate(
        { uuid: prod.uuid },
        { ...prod, active: true },
        { upsert: true, new: true }
      );
    }
    console.log(`✔ Seeded ${standardProducts.length} Standard Industrial Gaskets & Hydraulic Hardware Products`);

    // 3. Initialize Invoice Sequence for current FY
    const fy = getFinancialYear(new Date());
    await InvoiceSequence.findOneAndUpdate(
      { financialYear: fy },
      { $setOnInsert: { currentNumber: 0, reservedBlocks: [] } },
      { upsert: true }
    );
    console.log(`✔ Initialized Invoice Sequence for FY ${fy}`);

    console.log('--- Database Seeding Complete ---');
  } catch (error) {
    console.error('Seeding error:', error);
  } finally {
    await mongoose.disconnect();
    process.exit(0);
  }
};

seedData();
