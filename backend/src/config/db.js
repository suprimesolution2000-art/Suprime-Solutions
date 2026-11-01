const mongoose = require('mongoose');
const env = require('./env');

const connectDB = async () => {
  try {
    const conn = await mongoose.connect(env.MONGODB_URI, {
      serverSelectionTimeoutMS: 10000,
      socketTimeoutMS: 45000,
      autoIndex: env.NODE_ENV !== 'production' ? true : false, // Don't build indexes in high-traffic prod on every boot
    });

    console.log(`[MongoDB Atlas] Successfully connected to: ${conn.connection.host}`);
    console.log(`[MongoDB Atlas] Database Name: ${conn.connection.name}`);

    mongoose.connection.on('error', (err) => {
      console.error(`[MongoDB Atlas] Runtime error: ${err.message}`);
    });

    mongoose.connection.on('disconnected', () => {
      console.warn(`[MongoDB Atlas] Connection disconnected. Mongoose will attempt to reconnect...`);
    });

    mongoose.connection.on('reconnected', () => {
      console.log(`[MongoDB Atlas] Reconnected successfully.`);
    });

    return conn;
  } catch (error) {
    console.error(`[MongoDB Atlas] Initial connection error: ${error.message}`);
    if (env.NODE_ENV === 'production') {
      console.error(`[CRITICAL] Could not connect to MongoDB Atlas in production. Please verify MONGODB_URI and Network IP Access (0.0.0.0/0).`);
    } else {
      console.log(`[MongoDB] Running in standalone development mode.`);
    }
    return null;
  }
};

module.exports = connectDB;
