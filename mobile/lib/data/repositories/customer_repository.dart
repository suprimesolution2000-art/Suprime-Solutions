import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import '../database/app_database.dart';
import '../models/customer_model.dart';

class CustomerRepository {
  final AppDatabase _db = AppDatabase.instance;

  // Auto-heal customers from local invoices
  Future<int> recoverCustomersFromInvoices() async {
    final db = await _db.database;
    final invoices = await db.query('invoices');
    int recovered = 0;
    for (final invRow in invoices) {
      try {
        final custJson = invRow['customer_json'] as String?;
        if (custJson != null && custJson.isNotEmpty) {
          final custMap = jsonDecode(custJson);
          final cust = CustomerModel.fromMap(Map<String, dynamic>.from(custMap));
          if (cust.name.trim().isNotEmpty) {
            await saveCustomer(cust);
            recovered++;
          }
        }
      } catch (_) {}
    }
    return recovered;
  }

  Future<List<CustomerModel>> getAllCustomers({String? searchQuery}) async {
    final db = await _db.database;
    List<Map<String, dynamic>> results;

    // Auto-heal if customers table is empty but local invoices exist
    final count = Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM customers')) ?? 0;
    if (count == 0) {
      await recoverCustomersFromInvoices();
    }

    if (searchQuery != null && searchQuery.trim().isNotEmpty) {
      final query = '%${searchQuery.trim()}%';
      results = await db.rawQuery('''
        SELECT * FROM customers 
        WHERE (active = 1 OR active IS NULL OR active = 'true') AND (
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
        where: "active = 1 OR active IS NULL OR active = 'true'",
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
    if (customer.uuid.isNotEmpty) {
      final existingByUuid = await db.query(
        'customers',
        where: 'uuid = ?',
        whereArgs: [customer.uuid],
        limit: 1,
      );
      if (existingByUuid.isNotEmpty) {
        await db.update(
          'customers',
          customer.toMap(),
          where: 'uuid = ?',
          whereArgs: [customer.uuid],
        );
        return;
      }
    }

    if (customer.name.trim().isNotEmpty) {
      final existingByName = await db.query(
        'customers',
        where: 'LOWER(name) = ?',
        whereArgs: [customer.name.trim().toLowerCase()],
        limit: 1,
      );
      if (existingByName.isNotEmpty) {
        final existingUuid = existingByName.first['uuid'] as String;
        final updatedMap = customer.toMap();
        updatedMap['uuid'] = existingUuid; // Preserve existing customer UUID for relational integrity
        await db.update(
          'customers',
          updatedMap,
          where: 'uuid = ?',
          whereArgs: [existingUuid],
        );
        return;
      }
    }

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

  Future<void> deleteCustomer(String customerUuid) async {
    final db = await _db.database;
    try {
      await db.insert(
        'app_settings',
        {'key': 'deleted_customer_$customerUuid', 'value': DateTime.now().toIso8601String()},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    } catch (_) {}

    await db.update(
      'customers',
      {'active': 0},
      where: 'uuid = ?',
      whereArgs: [customerUuid],
    );
  }
}
