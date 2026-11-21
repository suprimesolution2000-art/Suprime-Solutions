const errorHandler = (err, req, res, next) => {
  console.error('[Error]', err);

  const statusCode = err.statusCode || 500;
  const isProd = process.env.NODE_ENV === 'production';
  const message = (isProd && statusCode === 500)
    ? 'An unexpected server error occurred. Please try again later.'
    : (err.message || 'Internal server error');

  res.status(statusCode).json({
    success: false,
    message,
    stack: process.env.NODE_ENV === 'development' ? err.stack : undefined
  });
};

module.exports = errorHandler;
