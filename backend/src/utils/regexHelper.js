/**
 * Escape special regex characters to prevent ReDoS (Regular Expression Denial of Service)
 * @param {string} text
 * @returns {string}
 */
function escapeRegex(text) {
  if (!text || typeof text !== 'string') return '';
  return text.replace(/[-[\]{}()*+?.,\\^$|#\s]/g, '\\$&');
}

module.exports = { escapeRegex };
