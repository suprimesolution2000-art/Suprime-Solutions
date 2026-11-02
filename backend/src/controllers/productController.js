const Product = require('../models/Product');
const { v4: uuidv4 } = require('uuid');
const { findByIdOrUuid } = require('../utils/idHelper');
const { escapeRegex } = require('../utils/regexHelper');

exports.getProducts = async (req, res, next) => {
  try {
    const { search, limit = 100 } = req.query;
    const safeLimit = Math.min(Math.max(1, parseInt(limit, 10) || 100), 500);
    const query = { active: true };

    if (search && search.trim()) {
      const regex = new RegExp(escapeRegex(search.trim()), 'i');
      query.$or = [
        { description: regex },
        { hsnCode: regex }
      ];
    }

    const products = await Product.find(query).sort({ description: 1 }).limit(safeLimit);
    res.json({ success: true, data: products });
  } catch (error) {
    next(error);
  }
};

exports.createProduct = async (req, res, next) => {
  try {
    const { description, hsnCode, unit, defaultRate, gstRate } = req.body;

    if (!description) {
      return res.status(400).json({ success: false, message: 'Description is required.' });
    }

    const uuid = req.body.uuid || uuidv4();
    const product = await Product.create({
      uuid,
      description: description.trim(),
      hsnCode: hsnCode ? hsnCode.trim() : '',
      unit: unit || 'PCS',
      defaultRate: Number(defaultRate) || 0,
      gstRate: Number(gstRate !== undefined ? gstRate : 18.0)
    });

    res.status(201).json({ success: true, data: product });
  } catch (error) {
    next(error);
  }
};

exports.updateProduct = async (req, res, next) => {
  try {
    const { description, hsnCode, unit, defaultRate, gstRate, active } = req.body;
    const updateFields = { updatedAt: new Date() };

    if (description !== undefined) updateFields.description = description.trim();
    if (hsnCode !== undefined) updateFields.hsnCode = hsnCode.trim();
    if (unit !== undefined) updateFields.unit = unit;
    if (defaultRate !== undefined) updateFields.defaultRate = Number(defaultRate) || 0;
    if (gstRate !== undefined) updateFields.gstRate = Number(gstRate) || 0;
    if (active !== undefined) updateFields.active = Boolean(active);

    const product = await Product.findOneAndUpdate(
      findByIdOrUuid(req.params.id),
      { $set: updateFields },
      { new: true }
    );

    if (!product) {
      return res.status(404).json({ success: false, message: 'Product not found.' });
    }

    res.json({ success: true, data: product });
  } catch (error) {
    next(error);
  }
};

exports.deleteProduct = async (req, res, next) => {
  try {
    const product = await Product.findOneAndUpdate(
      findByIdOrUuid(req.params.id),
      { $set: { active: false, updatedAt: new Date() } },
      { new: true }
    );

    if (!product) {
      return res.status(404).json({ success: false, message: 'Product not found.' });
    }

    res.json({ success: true, message: 'Product deleted successfully' });
  } catch (error) {
    next(error);
  }
};
