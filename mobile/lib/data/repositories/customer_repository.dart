import 'package:sqflite/sqflite.dart';
import '../database/app_database.dart';
import '../models/customer_model.dart';

class CustomerRepository {
  final AppDatabase _db = AppDatabase.instance;

  Future<List<CustomerModel>> getAllCustomers({String? searchQuery}) async {
    final db = await _db.database;
    List<Map<String, dynamic>> results;

    if (searchQuery != null && searchQuery.trim().isNotEmpty) {
      final query = '%${searchQuery.trim()}%';
      results = await db.rawQuery('''
        SELECT * FROM customers 
        WHERE active = 1 AND (
          name LIKE ? OR 
          business_name LIKE ? OR 
          phone LIKE ? OR 
          gstin LIKE ?
        )
        ORDER BY name ASC
      ''', [query, query, query, query]);
    } else {
      results = await db.query(
        'customers',
        where: 'active = 1',
        orderBy: 'name ASC',
      );
    }

    return results.map((m) => CustomerModel.fromMap(m)).toList();
  }

  Future<CustomerModel?> getCustomerByUuid(String uuid) async {
    final db = await _db.database;
    final results = await db.query(
      'customers',
      where: 'uuid = ?',
      whereArgs: [uuid],
      limit: 1,
    );
    if (results.isEmpty) return null;
    return CustomerModel.fromMap(results.first);
  }

  Future<CustomerModel?> findCustomerByPhone(String phone) async {
    if (phone.trim().isEmpty) return null;
    final db = await _db.database;
    final results = await db.query(
      'customers',
      where: 'phone = ? AND active = 1',
      whereArgs: [phone.trim()],
      limit: 1,
    );
    if (results.isEmpty) return null;
    return CustomerModel.fromMap(results.first);
  }

  Future<void> saveCustomer(CustomerModel customer) async {
    final db = await _db.database;
    await db.insert(
      'customers',
      customer.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> updateCustomerBalance(String customerUuid, double amountAdded, double paymentDeducted) async {
    final db = await _db.database;
    await db.rawUpdate('''
      UPDATE customers 
      SET 
        total_billed = total_billed + ?,
        total_paid = total_paid + ?,
        outstanding_balance = outstanding_balance + ? - ?
      WHERE uuid = ?
    ''', [amountAdded, paymentDeducted, amountAdded, paymentDeducted, customerUuid]);
  }
}
