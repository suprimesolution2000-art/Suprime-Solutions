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
}
