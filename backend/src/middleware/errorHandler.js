const errorHandler = (err, req, res, next) => {
  console.error('[Error]', err);

  if (res.headersSent) {
    return next(err);
  }

  let statusCode = err.statusCode || 500;
  let message = err.message || 'Internal server error';

  if (err.name === 'ValidationError') {
    statusCode = 400;
    message = Object.values(err.errors || {}).map(e => e.message).join(', ') || 'Validation error.';
  } else if (err.name === 'CastError') {
    statusCode = 400;
    message = `Invalid format for field '${err.path}'.`;
  } else if (err.code === 11000) {
    statusCode = 409;
    const field = Object.keys(err.keyPattern || {})[0] || 'field';
    message = `Duplicate value entered for unique field '${field}'.`;
  }

  const isProd = process.env.NODE_ENV === 'production';
  const finalMessage = (isProd && statusCode === 500)
    ? 'An unexpected server error occurred. Please try again later.'
    : message;

  res.status(statusCode).json({
    success: false,
    message: finalMessage,
    stack: process.env.NODE_ENV === 'development' ? err.stack : undefined
  });
};

module.exports = errorHandler;
