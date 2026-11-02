import 'package:sqflite/sqflite.dart';
import '../database/app_database.dart';
import '../models/product_model.dart';

class ProductRepository {
  final AppDatabase _db = AppDatabase.instance;

  Future<List<ProductModel>> getAllProducts({String? searchQuery}) async {
    final db = await _db.database;
    List<Map<String, dynamic>> results;

    if (searchQuery != null && searchQuery.trim().isNotEmpty) {
      final query = '%${searchQuery.trim()}%';
      results = await db.rawQuery('''
        SELECT * FROM products 
        WHERE (active = 1 OR active IS NULL OR active = 'true') AND (
          description LIKE ? OR 
          hsn_code LIKE ?
        )
        ORDER BY description ASC
      ''', [query, query]);
    } else {
      results = await db.query(
        'products',
        where: "active = 1 OR active IS NULL OR active = 'true'",
        orderBy: 'description ASC',
      );
    }

    return results.map((m) => ProductModel.fromMap(m)).toList();
  }

  Future<void> saveProduct(ProductModel product, {bool preserveInactive = true}) async {
    final db = await _db.database;
    final map = product.toMap();
    if (preserveInactive) {
      final existing = await db.query('products', where: 'uuid = ?', whereArgs: [product.uuid], limit: 1);
      if (existing.isNotEmpty && (existing.first['active'] == 0 || existing.first['active'] == 'false')) {
        map['active'] = 0;
      }
    }
    await db.insert(
      'products',
      map,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Automatically saves or updates product description, HSN code & details
  Future<void> saveOrUpdateProduct({
    String? uuid,
    required String description,
    required String hsnCode,
    String unit = 'PCS',
    double defaultRate = 0.0,
    double gstRate = 18.0,
    bool active = true,
    bool preserveInactive = true,
  }) async {
    final cleanDesc = description.trim();
    if (cleanDesc.isEmpty) return;

    final db = await _db.database;

    // Check by uuid first if provided
    if (uuid != null && uuid.isNotEmpty) {
      final existingByUuid = await db.query(
        'products',
        where: 'uuid = ?',
        whereArgs: [uuid],
        limit: 1,
      );
      if (existingByUuid.isNotEmpty) {
        final existingActive = existingByUuid.first['active'];
        final finalActive = (preserveInactive && (existingActive == 0 || existingActive == 'false')) ? 0 : (active ? 1 : 0);
        await db.update(
          'products',
          {
            'description': cleanDesc,
            if (hsnCode.trim().isNotEmpty) 'hsn_code': hsnCode.trim(),
            'unit': unit,
            'default_rate': defaultRate,
            'gst_rate': gstRate,
            'active': finalActive,
          },
          where: 'uuid = ?',
          whereArgs: [uuid],
        );
        return;
      }
    }

    final existing = await db.query(
      'products',
      where: 'LOWER(description) = LOWER(?)',
      whereArgs: [cleanDesc],
      limit: 1,
    );

    if (existing.isNotEmpty) {
      final existingUuid = existing.first['uuid'] as String;
      final existingActive = existing.first['active'];
      final finalActive = (preserveInactive && (existingActive == 0 || existingActive == 'false')) ? 0 : (active ? 1 : 0);
      await db.update(
        'products',
        {
          'description': cleanDesc,
          if (hsnCode.trim().isNotEmpty) 'hsn_code': hsnCode.trim(),
          'unit': unit,
          'default_rate': defaultRate,
          'gst_rate': gstRate,
          'active': finalActive,
        },
        where: 'uuid = ?',
        whereArgs: [existingUuid],
      );
    } else {
      final newUuid = uuid ?? 'prod-${DateTime.now().millisecondsSinceEpoch}';
      final tombstones = await db.query('app_settings', where: 'key = ?', whereArgs: ['deleted_product_$newUuid']);
      final finalActive = (preserveInactive && tombstones.isNotEmpty) ? 0 : (active ? 1 : 0);
      await db.insert(
        'products',
        {
          'uuid': newUuid,
          'description': cleanDesc,
          'hsn_code': hsnCode.trim(),
          'unit': unit,
          'default_rate': defaultRate,
          'gst_rate': gstRate,
          'active': finalActive,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
  }

  Future<void> deleteProduct(String productUuid) async {
    final db = await _db.database;
    try {
      await db.insert(
        'app_settings',
        {'key': 'deleted_product_$productUuid', 'value': DateTime.now().toIso8601String()},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    } catch (_) {}

    await db.update(
      'products',
      {'active': 0},
      where: 'uuid = ?',
      whereArgs: [productUuid],
    );
  }
}
