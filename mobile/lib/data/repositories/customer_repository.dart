import 'dart:async';
import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import '../database/app_database.dart';
import '../models/customer_model.dart';
import '../../services/sync/sync_service.dart';

class CustomerRepository {
  final AppDatabase _db = AppDatabase.instance;

  // Auto-heal customers from local invoices
  Future<int> recoverCustomersFromInvoices() async {
    final db = await _db.database;
    final allSettings = await db.query('app_settings');
    final activeTombstones = allSettings
        .where((r) => (r['key'] as String).startsWith('deleted_customer_'))
        .map((r) => (r['key'] as String).replaceFirst('deleted_customer_', ''))
        .toSet();

    final invoices = await db.query('invoices');
    int recovered = 0;
    for (final invRow in invoices) {
      try {
        final custJson = invRow['customer_json'] as String?;
        if (custJson != null && custJson.isNotEmpty) {
          final custMap = jsonDecode(custJson);
          final cust = CustomerModel.fromMap(Map<String, dynamic>.from(custMap));
          if (cust.name.trim().isNotEmpty) {
            // Do NOT resurrect if tombstoned as deleted
            if (activeTombstones.contains(cust.uuid)) continue;
            // Check if customer exists in DB and was soft-deleted (active == 0)
            final existing = await db.query('customers', where: 'uuid = ?', whereArgs: [cust.uuid], limit: 1);
            if (existing.isNotEmpty && (existing.first['active'] == 0 || existing.first['active'] == 'false')) {
              continue;
            }
            await saveCustomer(cust);
            recovered++;
          }
        }
      } catch (_) {}
    }
    if (recovered > 0) {
      await recalculateCustomerBalances();
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

  Future<CustomerModel?> getCustomerByName(String name) async {
    if (name.trim().isEmpty) return null;
    final db = await _db.database;
    final results = await db.query(
      'customers',
      where: 'LOWER(name) = ?',
      whereArgs: [name.trim().toLowerCase()],
      limit: 1,
    );
    if (results.isEmpty) return null;
    return CustomerModel.fromMap(results.first);
  }

  Future<void> saveCustomer(CustomerModel customer, {bool preserveInactive = true, bool preserveBalancesIfZero = false}) async {
    final db = await _db.database;
    if (customer.uuid.isNotEmpty) {
      final existingByUuid = await db.query(
        'customers',
        where: 'uuid = ?',
        whereArgs: [customer.uuid],
        limit: 1,
      );
      if (existingByUuid.isNotEmpty) {
        final existingActive = existingByUuid.first['active'];
        final map = customer.toMap();
        if (preserveInactive && (existingActive == 0 || existingActive == 'false')) {
          map['active'] = 0;
        }
        // Preserve existing due balance only if explicitly asked
        final existingDue = (existingByUuid.first['outstanding_balance'] as num?)?.toDouble() ?? 0.0;
        final existingBilled = (existingByUuid.first['total_billed'] as num?)?.toDouble() ?? 0.0;
        final existingPaid = (existingByUuid.first['total_paid'] as num?)?.toDouble() ?? 0.0;
        if (preserveBalancesIfZero && customer.outstandingBalance == 0.0 && existingDue > 0.0) {
          map['outstanding_balance'] = existingDue;
          map['total_billed'] = existingBilled;
          map['total_paid'] = existingPaid;
        }
        await db.update(
          'customers',
          map,
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
        final existingActive = existingByName.first['active'];
        final updatedMap = customer.toMap();
        updatedMap['uuid'] = existingUuid; // Preserve existing customer UUID for relational integrity
        if (preserveInactive && (existingActive == 0 || existingActive == 'false')) {
          updatedMap['active'] = 0;
        }
        // Preserve existing due balance only if explicitly asked
        final existingDue = (existingByName.first['outstanding_balance'] as num?)?.toDouble() ?? 0.0;
        final existingBilled = (existingByName.first['total_billed'] as num?)?.toDouble() ?? 0.0;
        final existingPaid = (existingByName.first['total_paid'] as num?)?.toDouble() ?? 0.0;
        if (preserveBalancesIfZero && customer.outstandingBalance == 0.0 && existingDue > 0.0) {
          updatedMap['outstanding_balance'] = existingDue;
          updatedMap['total_billed'] = existingBilled;
          updatedMap['total_paid'] = existingPaid;
        }
        await db.update(
          'customers',
          updatedMap,
          where: 'uuid = ?',
          whereArgs: [existingUuid],
        );
        return;
      }
    }

    // Check if there's a deleted tombstone before inserting
    final tombstones = await db.query('app_settings', where: 'key = ?', whereArgs: ['deleted_customer_${customer.uuid}']);
    final map = customer.toMap();
    if (preserveInactive && tombstones.isNotEmpty) {
      map['active'] = 0;
    }

    await db.insert(
      'customers',
      map,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Dynamically computes and updates the true financial totals (totalBilled, totalPaid, outstandingBalance)
  /// directly from local active invoices and payments.
  Future<void> recalculateCustomerBalances({String? targetCustomerUuid}) async {
    final db = await _db.database;

    // Fetch all active invoices (all active bills where goods/services were delivered)
    final invoices = await db.query(
      'invoices',
      columns: ['customer_json', 'grand_total', 'total_paid', 'balance_due', 'status'],
      where: "status != 'cancelled'",
    );

    final Map<String, double> billedByUuid = {};
    final Map<String, double> paidByUuid = {};
    final Map<String, double> dueByUuid = {};

    final Map<String, double> billedByPhone = {};
    final Map<String, double> paidByPhone = {};
    final Map<String, double> dueByPhone = {};

    final Map<String, double> billedByName = {};
    final Map<String, double> paidByName = {};
    final Map<String, double> dueByName = {};

    for (final inv in invoices) {
      final rawCust = inv['customer_json'] as String?;
      if (rawCust == null || rawCust.isEmpty) continue;
      try {
        final custMap = jsonDecode(rawCust);
        final uuid = (custMap['uuid'] ?? '').toString().trim();
        final phone = (custMap['phone'] ?? '').toString().trim();
        final name = (custMap['name'] ?? '').toString().trim().toLowerCase();

        final grandTotal = (inv['grand_total'] as num?)?.toDouble() ?? 0.0;
        final totalPaid = (inv['total_paid'] as num?)?.toDouble() ?? 0.0;
        final balanceDue = (inv['balance_due'] as num?)?.toDouble() ?? 0.0;

        if (uuid.isNotEmpty) {
          billedByUuid[uuid] = (billedByUuid[uuid] ?? 0.0) + grandTotal;
          paidByUuid[uuid] = (paidByUuid[uuid] ?? 0.0) + totalPaid;
          dueByUuid[uuid] = (dueByUuid[uuid] ?? 0.0) + balanceDue;
        }
        if (phone.isNotEmpty) {
          billedByPhone[phone] = (billedByPhone[phone] ?? 0.0) + grandTotal;
          paidByPhone[phone] = (paidByPhone[phone] ?? 0.0) + totalPaid;
          dueByPhone[phone] = (dueByPhone[phone] ?? 0.0) + balanceDue;
        }
        if (name.isNotEmpty) {
          billedByName[name] = (billedByName[name] ?? 0.0) + grandTotal;
          paidByName[name] = (paidByName[name] ?? 0.0) + totalPaid;
          dueByName[name] = (dueByName[name] ?? 0.0) + balanceDue;
        }
      } catch (_) {}
    }

    final totalLocalInvoices = Sqflite.firstIntValue(
      await db.rawQuery("SELECT COUNT(*) FROM invoices WHERE status != 'cancelled'"),
    ) ?? 0;

    final customerRows = targetCustomerUuid != null
        ? await db.query('customers', where: 'uuid = ?', whereArgs: [targetCustomerUuid])
        : await db.query('customers');

    final batch = db.batch();
    for (final c in customerRows) {
      final uuid = (c['uuid'] ?? '').toString().trim();
      final phone = (c['phone'] ?? '').toString().trim();
      final name = (c['name'] ?? '').toString().trim().toLowerCase();

      double? liveBilled;
      double? livePaid;
      double? liveDue;

      if (uuid.isNotEmpty && billedByUuid.containsKey(uuid)) {
        liveBilled = billedByUuid[uuid];
        livePaid = paidByUuid[uuid];
        liveDue = dueByUuid[uuid];
      } else if (phone.isNotEmpty && billedByPhone.containsKey(phone)) {
        liveBilled = billedByPhone[phone];
        livePaid = paidByPhone[phone];
        liveDue = dueByPhone[phone];
      } else if (name.isNotEmpty && billedByName.containsKey(name)) {
        liveBilled = billedByName[name];
        livePaid = paidByName[name];
        liveDue = dueByName[name];
      }

      if (liveDue != null) {
        final cleanDue = (liveDue <= 0.005 ? 0.0 : liveDue).clamp(0.0, double.infinity);
        batch.update(
          'customers',
          {
            'total_billed': (liveBilled ?? 0.0).clamp(0.0, double.infinity),
            'total_paid': (livePaid ?? 0.0).clamp(0.0, double.infinity),
            'outstanding_balance': cleanDue,
          },
          where: 'uuid = ?',
          whereArgs: [uuid],
        );
      } else if (totalLocalInvoices > 0) {
        // Customer has no active bills remaining on device
        batch.update(
          'customers',
          {
            'total_billed': 0.0,
            'total_paid': 0.0,
            'outstanding_balance': 0.0,
          },
          where: 'uuid = ?',
          whereArgs: [uuid],
        );
      }
    }
    await batch.commit(noResult: true);
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

    try {
      unawaited(SyncService.instance.synchronize(forceFullSync: false));
    } catch (_) {}
  }
}
