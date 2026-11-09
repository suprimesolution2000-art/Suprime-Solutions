const express = require('express');
const cors = require('cors');
const helmet = require('helmet');
const morgan = require('morgan');
const rateLimit = require('express-rate-limit');
const env = require('./config/env');
const connectDB = require('./config/db');
const errorHandler = require('./middleware/errorHandler');

// Route handlers
const authRoutes = require('./routes/authRoutes');
const customerRoutes = require('./routes/customerRoutes');
const productRoutes = require('./routes/productRoutes');
const invoiceRoutes = require('./routes/invoiceRoutes');
const paymentRoutes = require('./routes/paymentRoutes');
const reportRoutes = require('./routes/reportRoutes');
const syncRoutes = require('./routes/syncRoutes');
const adminRoutes = require('./routes/adminRoutes');
const appRoutes = require('./routes/appRoutes');

const app = express();

// Security and middleware
app.use(helmet({
  crossOriginResourcePolicy: false
}));
app.use(cors());
app.use(express.json({ limit: '10mb' }));
app.use(express.urlencoded({ extended: true, limit: '10mb' }));

if (env.NODE_ENV !== 'test') {
  app.use(morgan('dev'));
}

// Rate limiting for auth routes
const authLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  max: 100,
  message: { success: false, message: 'Too many requests, please try again later.' }
});
app.use('/api/auth', authLimiter);

// Health check endpoints
const sendHealth = (req, res) => {
  const isDbConnected = mongoose.connection.readyState === 1;
  res.status(isDbConnected ? 200 : 200).json({
    status: isDbConnected ? 'ok' : 'degraded',
    database: isDbConnected ? 'connected' : 'connecting',
    service: 'SS Supreme Solutions Mobile Billing API',
    company: env.COMPANY.name,
    timestamp: new Date().toISOString()
  });
};

app.get('/', sendHealth);
app.get('/health', sendHealth);
app.get('/api/health', sendHealth);

// Mount Routes
app.use('/api/auth', authRoutes);
app.use('/api/customers', customerRoutes);
app.use('/api/products', productRoutes);
app.use('/api/invoices', invoiceRoutes);
app.use('/api/payments', paymentRoutes);
app.use('/api/reports', reportRoutes);
app.use('/api/sync', syncRoutes);
app.use('/api/admin', adminRoutes);
app.use('/api/app', appRoutes);

// Centralized error handler
app.use(errorHandler);

// Connect DB and Start server
const startServer = async () => {
  const PORT = env.PORT;
  const server = app.listen(PORT, () => {
    console.log(`[Server] SS Supreme Solutions Backend running on port ${PORT}`);
  });

  // Connect to database in background so health check responds immediately on boot
  connectDB().catch((err) => {
    console.error(`[MongoDB Atlas] Initial connection error: ${err.message}`);
  });

  return server;
};

if (require.main === module) {
  startServer();
}

module.exports = { app, startServer };
