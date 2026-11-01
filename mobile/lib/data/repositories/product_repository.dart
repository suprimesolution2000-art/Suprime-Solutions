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
        WHERE active = 1 AND (
          description LIKE ? OR 
          hsn_code LIKE ?
        )
        ORDER BY description ASC
      ''', [query, query]);
    } else {
      results = await db.query(
        'products',
        where: 'active = 1',
        orderBy: 'description ASC',
      );
    }

    return results.map((m) => ProductModel.fromMap(m)).toList();
  }

  Future<void> saveProduct(ProductModel product) async {
    final db = await _db.database;
    await db.insert(
      'products',
      product.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Automatically saves or updates manual product description, HSN code & details for future bills
  Future<void> saveOrUpdateProduct({
    required String description,
    required String hsnCode,
    String unit = 'PCS',
    double defaultRate = 0.0,
    double gstRate = 18.0,
  }) async {
    final cleanDesc = description.trim();
    if (cleanDesc.isEmpty) return;

    final db = await _db.database;
    final existing = await db.query(
      'products',
      where: 'LOWER(description) = LOWER(?)',
      whereArgs: [cleanDesc],
      limit: 1,
    );

    if (existing.isNotEmpty) {
      final uuid = existing.first['uuid'] as String;
      await db.update(
        'products',
        {
          if (hsnCode.trim().isNotEmpty) 'hsn_code': hsnCode.trim(),
          'unit': unit,
          if (defaultRate > 0) 'default_rate': defaultRate,
          'gst_rate': gstRate,
          'active': 1,
        },
        where: 'uuid = ?',
        whereArgs: [uuid],
      );
    } else {
      final newUuid = 'prod-${DateTime.now().millisecondsSinceEpoch}';
      await db.insert(
        'products',
        {
          'uuid': newUuid,
          'description': cleanDesc,
          'hsn_code': hsnCode.trim(),
          'unit': unit,
          'default_rate': defaultRate,
          'gst_rate': gstRate,
          'active': 1,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
  }
}
