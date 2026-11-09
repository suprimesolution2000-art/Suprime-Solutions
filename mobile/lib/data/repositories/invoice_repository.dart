import 'dart:async';
import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import '../../core/utils/city_helper.dart';
import '../database/app_database.dart';
import '../models/invoice_model.dart';
import 'customer_repository.dart';
import '../../services/sync/sync_service.dart';

class InvoiceRepository {
  final AppDatabase _db = AppDatabase.instance;

  // Universal search and filtering in SQLite
  Future<List<InvoiceModel>> getInvoices({
    String? searchQuery,
    String? paymentFilter, // 'paid', 'unpaid', 'partially_paid', 'overdue'
    String? invoiceType, // 'gst' or 'temporary'
    String? cityFilter, // 'all' or specific city e.g. 'Raipur'
    DateTime? startDate,
    DateTime? endDate,
    double? minAmount,
    double? maxAmount,
    String? customerUuid,
    String sortBy = 'invoice_date',
    bool ascending = false,
    int limit = 50,
    int offset = 0,
  }) async {
    final db = await _db.database;
    final whereClauses = <String>[];
    final whereArgs = <dynamic>[];

    // 1. Universal Search (Case-insensitive across invoice #, customer name, phone, gstin, items)
    if (searchQuery != null && searchQuery.trim().isNotEmpty) {
      final term = '%${searchQuery.trim()}%';
      whereClauses.add('''
        (
          invoice_number LIKE ? OR
          customer_json LIKE ? OR
          items_json LIKE ? OR
          po_number LIKE ? OR
          challan_number LIKE ?
        )
      ''');
      whereArgs.addAll([term, term, term, term, term]);
    }

    // 2. Invoice Type filter (GST vs Temporary)
    if (invoiceType != null && invoiceType.isNotEmpty) {
      if (invoiceType == 'temporary') {
        whereClauses.add("invoice_type = 'temporary'");
      } else if (invoiceType == 'gst') {
        whereClauses.add("(invoice_type IS NULL OR invoice_type != 'temporary')");
      }
    }

    // 3. Payment status filter
    if (paymentFilter != null && paymentFilter.isNotEmpty && paymentFilter.toLowerCase() != 'all') {
      if (paymentFilter.toLowerCase() == 'partial') {
        whereClauses.add('payment_status = ?');
        whereArgs.add('partially_paid');
      } else {
        whereClauses.add('payment_status = ?');
        whereArgs.add(paymentFilter.toLowerCase());
      }
    }

    // 3. Date range
    if (startDate != null) {
      whereClauses.add('invoice_date >= ?');
      whereArgs.add(startDate.toIso8601String());
    }
    if (endDate != null) {
      final end = DateTime(endDate.year, endDate.month, endDate.day, 23, 59, 59);
      whereClauses.add('invoice_date <= ?');
      whereArgs.add(end.toIso8601String());
    }

    // 4. Amount filter
    if (minAmount != null) {
      whereClauses.add('grand_total >= ?');
      whereArgs.add(minAmount);
    }
    if (maxAmount != null) {
      whereClauses.add('grand_total <= ?');
      whereArgs.add(maxAmount);
    }

    // 5. Customer UUID
    if (customerUuid != null && customerUuid.isNotEmpty) {
      whereClauses.add('customer_json LIKE ?');
      whereArgs.add('%"uuid":"$customerUuid"%');
    }

    final whereString = whereClauses.isNotEmpty ? whereClauses.join(' AND ') : null;
    final orderDirection = ascending ? 'ASC' : 'DESC';
    const allowedSortColumns = {
      'sequence_number',
      'invoice_date',
      'grand_total',
      'invoice_number',
      'created_at',
      'status',
      'payment_status',
    };
    final safeSortBy = allowedSortColumns.contains(sortBy) ? sortBy : 'sequence_number';

    final results = await db.query(
      'invoices',
      where: whereString,
      whereArgs: whereArgs.isNotEmpty ? whereArgs : null,
      orderBy: '$safeSortBy $orderDirection',
      limit: limit,
      offset: offset,
    );

    var invoices = results.map((m) => InvoiceModel.fromMap(m)).toList();

    if (cityFilter != null && cityFilter.isNotEmpty && cityFilter != 'all') {
      invoices = invoices.where((inv) => inv.customer.city.trim().toLowerCase() == cityFilter.trim().toLowerCase()).toList();
    }

    int paymentPriority(String status, {bool unpaidFirst = true}) {
      final s = status.toLowerCase();
      if (unpaidFirst) {
        if (s == 'unpaid') return 0;
        if (s == 'partially_paid' || s == 'partial') return 1;
        if (s == 'paid') return 2;
        return 3;
      } else {
        if (s == 'paid') return 0;
        if (s == 'partially_paid' || s == 'partial') return 1;
        if (s == 'unpaid') return 2;
        return 3;
      }
    }

    // Layered sorting (e.g. City then Paid/Unpaid, or vice versa)
    if (sortBy == 'city_unpaid_first') {
      invoices.sort((a, b) {
        final cA = a.customer.city.trim().toLowerCase();
        final cB = b.customer.city.trim().toLowerCase();
        final cCmp = cA.compareTo(cB);
        if (cCmp != 0) return cCmp;
        final pCmp = paymentPriority(a.paymentStatus, unpaidFirst: true)
            .compareTo(paymentPriority(b.paymentStatus, unpaidFirst: true));
        if (pCmp != 0) return pCmp;
        return b.invoiceDate.compareTo(a.invoiceDate);
      });
    } else if (sortBy == 'city_paid_first') {
      invoices.sort((a, b) {
        final cA = a.customer.city.trim().toLowerCase();
        final cB = b.customer.city.trim().toLowerCase();
        final cCmp = cA.compareTo(cB);
        if (cCmp != 0) return cCmp;
        final pCmp = paymentPriority(a.paymentStatus, unpaidFirst: false)
            .compareTo(paymentPriority(b.paymentStatus, unpaidFirst: false));
        if (pCmp != 0) return pCmp;
        return b.invoiceDate.compareTo(a.invoiceDate);
      });
    } else if (sortBy == 'unpaid_city') {
      invoices.sort((a, b) {
        final pCmp = paymentPriority(a.paymentStatus, unpaidFirst: true)
            .compareTo(paymentPriority(b.paymentStatus, unpaidFirst: true));
        if (pCmp != 0) return pCmp;
        final cA = a.customer.city.trim().toLowerCase();
        final cB = b.customer.city.trim().toLowerCase();
        final cCmp = cA.compareTo(cB);
        if (cCmp != 0) return cCmp;
        return b.invoiceDate.compareTo(a.invoiceDate);
      });
    } else if (sortBy == 'paid_city') {
      invoices.sort((a, b) {
        final pCmp = paymentPriority(a.paymentStatus, unpaidFirst: false)
            .compareTo(paymentPriority(b.paymentStatus, unpaidFirst: false));
        if (pCmp != 0) return pCmp;
        final cA = a.customer.city.trim().toLowerCase();
        final cB = b.customer.city.trim().toLowerCase();
        final cCmp = cA.compareTo(cB);
        if (cCmp != 0) return cCmp;
        return b.invoiceDate.compareTo(a.invoiceDate);
      });
    }

    return invoices;
  }

  Future<InvoiceModel?> getInvoiceByUuid(String uuid) async {
    final db = await _db.database;
    final results = await db.query(
      'invoices',
      where: 'uuid = ?',
      whereArgs: [uuid],
      limit: 1,
    );
    if (results.isEmpty) return null;
    return InvoiceModel.fromMap(results.first);
  }

  /// Get all active GST Tax Invoices for a date range in chronological ascending order (Excludes temporary bills)
  Future<List<InvoiceModel>> getGstInvoicesForDateRange(DateTime from, DateTime to) async {
    final db = await _db.database;
    final start = DateTime(from.year, from.month, from.day).toIso8601String();
    final end = DateTime(to.year, to.month, to.day, 23, 59, 59).toIso8601String();

    final results = await db.query(
      'invoices',
      where: "status != 'cancelled' AND (invoice_type IS NULL OR invoice_type != 'temporary') AND invoice_date >= ? AND invoice_date <= ?",
      whereArgs: [start, end],
      orderBy: 'invoice_date ASC, sequence_number ASC',
    );

    return results.map((m) => InvoiceModel.fromMap(m)).toList();
  }

  Future<void> saveInvoice(InvoiceModel invoice) async {
    final db = await _db.database;
    await db.insert(
      'invoices',
      invoice.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    try {
      await CustomerRepository().recalculateCustomerBalances(targetCustomerUuid: invoice.customer.uuid);
      await SyncService.instance.checkPendingQueue();
      await SyncService.instance.synchronize(forceFullSync: true);
    } catch (_) {}
  }

  Future<void> updatePaymentStatus(String invoiceUuid, double newTotalPaid, double newBalanceDue, String paymentStatus) async {
    final db = await _db.database;
    await db.update(
      'invoices',
      {
        'total_paid': newTotalPaid,
        'balance_due': newBalanceDue,
        'payment_status': paymentStatus,
      },
      where: 'uuid = ?',
      whereArgs: [invoiceUuid],
    );
    try {
      await CustomerRepository().recalculateCustomerBalances();
      await SyncService.instance.checkPendingQueue();
      await SyncService.instance.synchronize(forceFullSync: true);
    } catch (_) {}
  }

  Future<void> cancelInvoice(String invoiceUuid) async {
    final db = await _db.database;
    await db.update(
      'invoices',
      {'status': 'cancelled'},
      where: 'uuid = ?',
      whereArgs: [invoiceUuid],
    );
    try {
      await CustomerRepository().recalculateCustomerBalances();
      await SyncService.instance.checkPendingQueue();
      await SyncService.instance.synchronize(forceFullSync: true);
    } catch (_) {}
  }

  Future<void> updateInvoice(
    InvoiceModel invoice, {
    double deltaGrandTotal = 0.0,
    double deltaBalanceDue = 0.0,
  }) async {
    final db = await _db.database;
    await db.update(
      'invoices',
      invoice.toMap(),
      where: 'uuid = ?',
      whereArgs: [invoice.uuid],
    );

    // Adjust customer ledger balance
    try {
      final custRows = await db.query('customers', where: 'uuid = ?', whereArgs: [invoice.customer.uuid], limit: 1);
      if (custRows.isNotEmpty) {
        final currentBilled = (custRows.first['total_billed'] as num?)?.toDouble() ?? 0.0;
        final currentDue = (custRows.first['outstanding_balance'] as num?)?.toDouble() ?? 0.0;
        await db.update(
          'customers',
          {
            'total_billed': (currentBilled + deltaGrandTotal).clamp(0.0, double.infinity),
            'outstanding_balance': (currentDue + deltaBalanceDue).clamp(0.0, double.infinity),
          },
          where: 'uuid = ?',
          whereArgs: [invoice.customer.uuid],
        );
      }
    } catch (_) {}

    try {
      await CustomerRepository().recalculateCustomerBalances(targetCustomerUuid: invoice.customer.uuid);
      await SyncService.instance.checkPendingQueue();
      unawaited(SyncService.instance.synchronize(forceFullSync: false));
    } catch (_) {}
  }

  Future<void> deleteInvoice(String invoiceUuid) async {
    final db = await _db.database;
    final inv = await getInvoiceByUuid(invoiceUuid);
    if (inv != null && inv.status != 'cancelled' && inv.invoiceType != 'temporary') {
      // Revert customer outstanding balance and payments
      try {
        List<Map<String, dynamic>> custRows = [];
        if (inv.customer.uuid.isNotEmpty) {
          custRows = await db.query('customers', where: 'uuid = ?', whereArgs: [inv.customer.uuid], limit: 1);
        }
        if (custRows.isEmpty && inv.customer.phone.isNotEmpty) {
          custRows = await db.query('customers', where: 'phone = ?', whereArgs: [inv.customer.phone], limit: 1);
        }
        if (custRows.isEmpty && inv.customer.name.trim().isNotEmpty) {
          custRows = await db.query('customers', where: 'LOWER(name) = ?', whereArgs: [inv.customer.name.trim().toLowerCase()], limit: 1);
        }
        if (custRows.isNotEmpty) {
          final matchedCustUuid = custRows.first['uuid'] as String;
          final currentBilled = (custRows.first['total_billed'] as num?)?.toDouble() ?? 0.0;
          final currentPaid = (custRows.first['total_paid'] as num?)?.toDouble() ?? 0.0;
          final currentDue = (custRows.first['outstanding_balance'] as num?)?.toDouble() ?? 0.0;
          await db.update(
            'customers',
            {
              'total_billed': (currentBilled - inv.grandTotal).clamp(0.0, double.infinity),
              'total_paid': (currentPaid - inv.totalPaid).clamp(0.0, double.infinity),
              'outstanding_balance': (currentDue - inv.balanceDue).clamp(0.0, double.infinity),
            },
            where: 'uuid = ?',
            whereArgs: [matchedCustUuid],
          );
        }
      } catch (_) {}
    }

    // Clean up any payments associated with this deleted invoice
    try {
      await db.delete(
        'payments',
        where: 'invoice_id = ?',
        whereArgs: [invoiceUuid],
      );
    } catch (_) {}

    // Record tombstone so cloud pullSync does not resurrect this deleted invoice
    try {
      await db.insert(
        'app_settings',
        {'key': 'deleted_invoice_$invoiceUuid', 'value': DateTime.now().toIso8601String()},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    } catch (_) {}

    await db.delete(
      'invoices',
      where: 'uuid = ?',
      whereArgs: [invoiceUuid],
    );

    try {
      await CustomerRepository().recalculateCustomerBalances();
      await SyncService.instance.checkPendingQueue();
      await SyncService.instance.synchronize(forceFullSync: true);
    } catch (_) {}
  }

  // Determine Financial Year for a date
  static String getFinancialYear(DateTime date) {
    final month = date.month;
    final year = date.year;
    int startYear, endYear;
    if (month >= 4) {
      startYear = year;
      endYear = year + 1;
    } else {
      startYear = year - 1;
      endYear = year;
    }
    final startYY = startYear.toString().substring(2);
    final endYY = endYear.toString().substring(2);
    return '$startYY-$endYY';
  }

  // Preview next simple invoice number without advancing the sequence (GST bills)
  Future<String> getNextInvoiceNumberPreview(DateTime date) async {
    final db = await _db.database;
    final fy = getFinancialYear(date);

    final nextNumRes = await db.query('app_settings', where: 'key = ?', whereArgs: ['next_usable_number']);

    int nextNum = 1;
    if (nextNumRes.isNotEmpty) {
      nextNum = int.tryParse(nextNumRes.first['value'] as String) ?? 1;
    } else {
      final maxRes = await db.rawQuery(
        "SELECT MAX(sequence_number) as max_seq FROM invoices WHERE (invoice_type IS NULL OR invoice_type != 'temporary') AND financial_year = ?",
        [fy],
      );
      if (maxRes.isNotEmpty && maxRes.first['max_seq'] != null) {
        nextNum = (maxRes.first['max_seq'] as int) + 1;
      }
    }

    final prefixRes = await db.query('app_settings', where: 'key = ?', whereArgs: ['invoice_prefix']);
    final prefix = prefixRes.isNotEmpty ? (prefixRes.first['value'] as String? ?? '') : '';

    return prefix.isNotEmpty ? '$prefix$nextNum' : '$nextNum';
  }

  // Preview next temporary bill number without advancing the sequence (Temporary bills)
  Future<String> getNextTemporaryInvoiceNumberPreview(DateTime date) async {
    final db = await _db.database;
    final fy = getFinancialYear(date);

    final nextNumRes = await db.query('app_settings', where: 'key = ?', whereArgs: ['next_temporary_number']);

    int nextNum = 1;
    if (nextNumRes.isNotEmpty) {
      nextNum = int.tryParse(nextNumRes.first['value'] as String) ?? 1;
    } else {
      final maxRes = await db.rawQuery(
        "SELECT MAX(sequence_number) as max_seq FROM invoices WHERE invoice_type = 'temporary' AND financial_year = ?",
        [fy],
      );
      if (maxRes.isNotEmpty && maxRes.first['max_seq'] != null) {
        nextNum = (maxRes.first['max_seq'] as int) + 1;
      }
    }

    final prefixRes = await db.query('app_settings', where: 'key = ?', whereArgs: ['temporary_invoice_prefix']);
    final prefix = prefixRes.isNotEmpty ? (prefixRes.first['value'] as String? ?? '') : '';

    return prefix.isNotEmpty ? '$prefix$nextNum' : '$nextNum';
  }

  // Allocate next sequential invoice number locally for GST Bills
  Future<Map<String, dynamic>> allocateNextLocalInvoiceNumber(
    DateTime date, {
    String? customInvoiceNumber,
  }) async {
    final db = await _db.database;
    final fy = getFinancialYear(date);

    return await db.transaction<Map<String, dynamic>>((txn) async {
      final nextNumRes = await txn.query('app_settings', where: 'key = ?', whereArgs: ['next_usable_number']);

      int nextNum = 1;
      if (nextNumRes.isNotEmpty) {
        nextNum = int.tryParse(nextNumRes.first['value'] as String) ?? 1;
      } else {
        // Find highest existing sequence for GST in this FY
        final maxRes = await txn.rawQuery(
          "SELECT MAX(sequence_number) as max_seq FROM invoices WHERE (invoice_type IS NULL OR invoice_type != 'temporary') AND financial_year = ?",
          [fy],
        );
        if (maxRes.isNotEmpty && maxRes.first['max_seq'] != null) {
          nextNum = (maxRes.first['max_seq'] as int) + 1;
        }
      }

      final prefixRes = await txn.query('app_settings', where: 'key = ?', whereArgs: ['invoice_prefix']);
      final prefix = prefixRes.isNotEmpty ? (prefixRes.first['value'] as String? ?? '') : '';

      String invoiceNumber;
      int seqNum;

      if (customInvoiceNumber != null && customInvoiceNumber.trim().isNotEmpty) {
        invoiceNumber = customInvoiceNumber.trim();
        final match = RegExp(r'(\d+)$').firstMatch(invoiceNumber) ?? RegExp(r'(\d+)').firstMatch(invoiceNumber);
        final parsed = match != null ? int.tryParse(match.group(1)!) : null;
        seqNum = parsed ?? nextNum;
        nextNum = (parsed != null && parsed >= nextNum) ? parsed + 1 : nextNum + 1;
      } else {
        // Simple format: e.g. "1", "2", "3" or "SS-1"
        invoiceNumber = prefix.isNotEmpty ? '$prefix$nextNum' : '$nextNum';
        seqNum = nextNum;
        nextNum = nextNum + 1;
      }

      // Increment and save next usable number
      await txn.insert(
        'app_settings',
        {'key': 'next_usable_number', 'value': nextNum.toString()},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      return {
        'invoiceNumber': invoiceNumber,
        'sequenceNumber': seqNum,
        'financialYear': fy,
      };
    });
  }

  /// Allocate a dedicated sequential number for Temporary Bill (completely separate from GST sequence)
  Future<Map<String, dynamic>> allocateTemporaryInvoiceNumber(
    DateTime date, {
    String? customInvoiceNumber,
  }) async {
    final db = await _db.database;
    final fy = getFinancialYear(date);

    return await db.transaction<Map<String, dynamic>>((txn) async {
      final nextNumRes = await txn.query('app_settings', where: 'key = ?', whereArgs: ['next_temporary_number']);

      int nextNum = 1;
      if (nextNumRes.isNotEmpty) {
        nextNum = int.tryParse(nextNumRes.first['value'] as String) ?? 1;
      } else {
        // Find highest existing sequence for temporary bills in this FY
        final maxRes = await txn.rawQuery(
          "SELECT MAX(sequence_number) as max_seq FROM invoices WHERE invoice_type = 'temporary' AND financial_year = ?",
          [fy],
        );
        if (maxRes.isNotEmpty && maxRes.first['max_seq'] != null) {
          nextNum = (maxRes.first['max_seq'] as int) + 1;
        }
      }

      final prefixRes = await txn.query('app_settings', where: 'key = ?', whereArgs: ['temporary_invoice_prefix']);
      final prefix = prefixRes.isNotEmpty ? (prefixRes.first['value'] as String? ?? '') : '';

      String invoiceNumber;
      int seqNum;

      if (customInvoiceNumber != null && customInvoiceNumber.trim().isNotEmpty) {
        invoiceNumber = customInvoiceNumber.trim();
        final match = RegExp(r'(\d+)$').firstMatch(invoiceNumber) ?? RegExp(r'(\d+)').firstMatch(invoiceNumber);
        final parsed = match != null ? int.tryParse(match.group(1)!) : null;
        seqNum = parsed ?? nextNum;
        nextNum = (parsed != null && parsed >= nextNum) ? parsed + 1 : nextNum + 1;
      } else {
        invoiceNumber = prefix.isNotEmpty ? '$prefix$nextNum' : '$nextNum';
        seqNum = nextNum;
        nextNum = nextNum + 1;
      }

      // Persist the incremented counter in app_settings
      await txn.insert(
        'app_settings',
        {'key': 'next_temporary_number', 'value': nextNum.toString()},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      return {
        'invoiceNumber': invoiceNumber,
        'sequenceNumber': seqNum,
        'financialYear': fy,
      };
    });
  }

  // Summary figures for Home Dashboard
  Future<Map<String, dynamic>> getDashboardSummary() async {
    final db = await _db.database;
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day).toIso8601String();
    final monthStart = DateTime(now.year, now.month, 1).toIso8601String();

    // Today's sales (Excludes cancelled & temporary bills)
    final todayRes = await db.rawQuery('''
      SELECT SUM(grand_total) as total, COUNT(*) as count 
      FROM invoices 
      WHERE invoice_date >= ? AND status != 'cancelled' AND (invoice_type IS NULL OR invoice_type != 'temporary')
    ''', [todayStart]);

    // Month's sales (Excludes cancelled & temporary bills)
    final monthRes = await db.rawQuery('''
      SELECT SUM(grand_total) as total, COUNT(*) as count 
      FROM invoices 
      WHERE invoice_date >= ? AND status != 'cancelled' AND (invoice_type IS NULL OR invoice_type != 'temporary')
    ''', [monthStart]);

    // Pending payments (Excludes cancelled & temporary bills)
    final pendingRes = await db.rawQuery('''
      SELECT SUM(balance_due) as total, COUNT(*) as count 
      FROM invoices 
      WHERE status != 'cancelled' AND (invoice_type IS NULL OR invoice_type != 'temporary') AND payment_status IN ('unpaid', 'partially_paid', 'overdue')
    ''');

    // Customer count
    final custRes = await db.rawQuery("SELECT COUNT(*) as count FROM customers WHERE (active = 1 OR active IS NULL OR active = 'true')");

    return {
      'todaySales': (todayRes.first['total'] as num?)?.toDouble() ?? 0.0,
      'todayCount': (todayRes.first['count'] as int?) ?? 0,
      'monthlySales': (monthRes.first['total'] as num?)?.toDouble() ?? 0.0,
      'monthlyCount': (monthRes.first['count'] as int?) ?? 0,
      'pendingPayments': (pendingRes.first['total'] as num?)?.toDouble() ?? 0.0,
      'pendingCount': (pendingRes.first['count'] as int?) ?? 0,
      'customerCount': (custRes.first['count'] as int?) ?? 0,
    };
  }
  /// Automatically extracts and repairs city data for legacy bills and customers
  Future<void> autoRepairLegacyCities() async {
    try {
      final db = await _db.database;
      final rows = await db.query('invoices', columns: ['uuid', 'customer_json']);
      final batch = db.batch();
      bool needsUpdate = false;

      for (final r in rows) {
        final uuid = r['uuid'] as String;
        final rawCust = r['customer_json'] as String?;
        if (rawCust == null || rawCust.isEmpty) continue;
        try {
          final custMap = jsonDecode(rawCust) as Map<String, dynamic>;
          final currentCity = (custMap['city'] ?? '').toString();
          final address = (custMap['address'] ?? '').toString();
          final extracted = CityHelper.extractCity(currentCity, address);
          if (extracted != currentCity && extracted.isNotEmpty) {
            custMap['city'] = extracted;
            batch.update(
              'invoices',
              {'customer_json': jsonEncode(custMap)},
              where: 'uuid = ?',
              whereArgs: [uuid],
            );
            needsUpdate = true;
          }
        } catch (_) {}
      }

      final custRows = await db.query('customers', columns: ['uuid', 'city', 'address']);
      for (final c in custRows) {
        final uuid = c['uuid'] as String;
        final currentCity = (c['city'] ?? '').toString();
        final address = (c['address'] ?? '').toString();
        final extracted = CityHelper.extractCity(currentCity, address);
        if (extracted != currentCity && extracted.isNotEmpty) {
          batch.update(
            'customers',
            {'city': extracted},
            where: 'uuid = ?',
            whereArgs: [uuid],
          );
          needsUpdate = true;
        }
      }

      if (needsUpdate) {
        await batch.commit(noResult: true);
      }
    } catch (_) {}
  }

  /// Returns list of all distinct cities currently present in invoices
  Future<List<String>> getDistinctCities() async {
    final db = await _db.database;
    final rows = await db.query('invoices', columns: ['customer_json']);
    final cities = <String>{};
    for (final r in rows) {
      final raw = r['customer_json'] as String?;
      if (raw != null && raw.isNotEmpty) {
        try {
          final map = jsonDecode(raw) as Map<String, dynamic>;
          final c = CityHelper.extractCity((map['city'] ?? '').toString(), (map['address'] ?? '').toString());
          if (c.isNotEmpty) cities.add(c);
        } catch (_) {}
      }
    }
    final list = cities.toList()..sort();
    return list;
  }
}
