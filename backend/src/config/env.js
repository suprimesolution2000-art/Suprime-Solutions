require('dotenv').config();

module.exports = {
  NODE_ENV: process.env.NODE_ENV || 'development',
  PORT: process.env.PORT || 5000,
  MONGODB_URI: process.env.MONGODB_URI || 'mongodb://127.0.0.1:27017/ss_supreme_solutions',
  JWT_SECRET: process.env.JWT_SECRET || 'ss_supreme_solutions_super_secure_jwt_secret_2026',
  JWT_REFRESH_SECRET: process.env.JWT_REFRESH_SECRET || 'ss_supreme_solutions_refresh_jwt_secret_2026',
  JWT_EXPIRES_IN: '7d',
  JWT_REFRESH_EXPIRES_IN: '30d',
  COMPANY: {
    name: 'SS Suprime Solutions',
    gstin: '22FWDPD2626D1Z7',
    ePan: 'FWDPD2626D',
    phone: '9981365878',
    address: 'Mahalaxmi Bole, Beside Yashoda Dairy, Tikrapara, Bilaspur (C.G.) 495001',
    state: 'Chhattisgarh',
    stateCode: '22',
    bank: {
      name: 'Punjab National Bank',
      accountNumber: '1539050003087',
      ifsc: 'PUNB0324500'
    },
    terms: [
      'Subject to Bilaspur (C.G.) Jurisdiction',
      'Goods once sold will not be back'
    ]
  }
};
