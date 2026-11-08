require('dotenv').config();

if (process.env.NODE_ENV === 'production' && (!process.env.JWT_SECRET || process.env.JWT_SECRET.includes('super_secure'))) {
  console.warn('[SECURITY WARNING] Production running with default or insecure JWT_SECRET. Please set a strong custom JWT_SECRET.');
}

module.exports = {
  NODE_ENV: process.env.NODE_ENV || 'development',
  PORT: process.env.PORT || 5000,
  MONGODB_URI: process.env.MONGODB_URI || 'mongodb+srv://suprimesolution2000_db_user:b0qXOlHnM9ZEJzq4@cluster0.and9g1p.mongodb.net/ss_supreme_solutions?retryWrites=true&w=majority',
  JWT_SECRET: process.env.JWT_SECRET || 'ss_supreme_solutions_super_secure_jwt_secret_2026',
  JWT_REFRESH_SECRET: process.env.JWT_REFRESH_SECRET || 'ss_supreme_solutions_refresh_jwt_secret_2026',
  JWT_EXPIRES_IN: '7d',
  JWT_REFRESH_EXPIRES_IN: '30d',
  COMPANY: {
    name: process.env.COMPANY_NAME || 'Suprime Solutions',
    gstin: process.env.COMPANY_GSTIN || '22FWDPD2626D1Z7',
    ePan: process.env.COMPANY_EPAN || 'FWDPD2626D',
    phone: process.env.COMPANY_PHONE || '9981365878',
    address: process.env.COMPANY_ADDRESS || 'Mahalaxmi Bole, Beside Yashoda Dairy, Tikrapara, Bilaspur (C.G.) 495001',
    state: process.env.COMPANY_STATE || 'Chhattisgarh',
    stateCode: process.env.COMPANY_STATE_CODE || '22',
    bank: {
      name: process.env.BANK_NAME || 'Punjab National Bank',
      accountNumber: process.env.BANK_ACCOUNT || '1539050003087',
      ifsc: process.env.BANK_IFSC || 'PUNB0324500'
    },
    terms: [
      'Subject to Bilaspur (C.G.) Jurisdiction',
      'Goods once sold will not be back'
    ]
  }
};
