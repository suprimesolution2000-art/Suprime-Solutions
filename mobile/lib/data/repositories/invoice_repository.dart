import 'package:sqflite/sqflite.dart';
import '../database/app_database.dart';
import '../models/invoice_model.dart';

class InvoiceRepository {
  final AppDatabase _db = AppDatabase.instance;

  // Universal search and filtering in SQLite
  Future<List<InvoiceModel>> getInvoices({
    String? searchQuery,
    String? paymentFilter, // 'paid', 'unpaid', 'partially_paid', 'overdue'
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

    // 2. Payment status filter
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

    final results = await db.query(
      'invoices',
      where: whereString,
      whereArgs: whereArgs.isNotEmpty ? whereArgs : null,
      orderBy: '$sortBy $orderDirection',
      limit: limit,
      offset: offset,
    );

    return results.map((m) => InvoiceModel.fromMap(m)).toList();
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

  Future<void> saveInvoice(InvoiceModel invoice) async {
    final db = await _db.database;
    await db.insert(
      'invoices',
      invoice.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
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
  }

  Future<void> cancelInvoice(String invoiceUuid) async {
    final db = await _db.database;
    await db.update(
      'invoices',
      {'status': 'cancelled'},
      where: 'uuid = ?',
      whereArgs: [invoiceUuid],
    );
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

  // Preview next simple invoice number without advancing the sequence
  Future<String> getNextInvoiceNumberPreview(DateTime date) async {
    final db = await _db.database;
    final fy = getFinancialYear(date);

    final nextNumRes = await db.query('app_settings', where: 'key = ?', whereArgs: ['next_usable_number']);

    int nextNum = 1;
    if (nextNumRes.isNotEmpty) {
      nextNum = int.tryParse(nextNumRes.first['value'] as String) ?? 1;
    } else {
      final maxRes = await db.rawQuery(
        'SELECT MAX(sequence_number) as max_seq FROM invoices WHERE financial_year = ?',
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

  // Allocate next sequential invoice number locally (Simple format: "1", "2", "3" or "SS-1")
  Future<Map<String, dynamic>> allocateNextLocalInvoiceNumber(
    DateTime date, {
    String? customInvoiceNumber,
  }) async {
    final db = await _db.database;
    final fy = getFinancialYear(date);

    final nextNumRes = await db.query('app_settings', where: 'key = ?', whereArgs: ['next_usable_number']);

    int nextNum = 1;
    if (nextNumRes.isNotEmpty) {
      nextNum = int.tryParse(nextNumRes.first['value'] as String) ?? 1;
    } else {
      // Find highest existing sequence in this FY
      final maxRes = await db.rawQuery(
        'SELECT MAX(sequence_number) as max_seq FROM invoices WHERE financial_year = ?',
        [fy],
      );
      if (maxRes.isNotEmpty && maxRes.first['max_seq'] != null) {
        nextNum = (maxRes.first['max_seq'] as int) + 1;
      }
    }

    final prefixRes = await db.query('app_settings', where: 'key = ?', whereArgs: ['invoice_prefix']);
    final prefix = prefixRes.isNotEmpty ? (prefixRes.first['value'] as String? ?? '') : '';

    String invoiceNumber;
    int seqNum;

    if (customInvoiceNumber != null && customInvoiceNumber.trim().isNotEmpty) {
      invoiceNumber = customInvoiceNumber.trim();
      final parsed = int.tryParse(RegExp(r'\d+').stringMatch(invoiceNumber) ?? '');
      seqNum = parsed ?? nextNum;
      nextNum = (parsed != null && parsed >= nextNum) ? parsed + 1 : nextNum + 1;
    } else {
      // Simple format: e.g. "1", "2", "3" or "SS-1"
      invoiceNumber = prefix.isNotEmpty ? '$prefix$nextNum' : '$nextNum';
      seqNum = nextNum;
      nextNum = nextNum + 1;
    }

    // Increment and save next usable number
    await db.insert(
      'app_settings',
      {'key': 'next_usable_number', 'value': nextNum.toString()},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    return {
      'invoiceNumber': invoiceNumber,
      'sequenceNumber': seqNum,
      'financialYear': fy,
    };
  }

  // Summary figures for Home Dashboard
  Future<Map<String, dynamic>> getDashboardSummary() async {
    final db = await _db.database;
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day).toIso8601String();
    final monthStart = DateTime(now.year, now.month, 1).toIso8601String();

    // Today's sales
    final todayRes = await db.rawQuery('''
      SELECT SUM(grand_total) as total, COUNT(*) as count 
      FROM invoices 
      WHERE invoice_date >= ? AND status != 'cancelled'
    ''', [todayStart]);

    // Month's sales
    final monthRes = await db.rawQuery('''
      SELECT SUM(grand_total) as total, COUNT(*) as count 
      FROM invoices 
      WHERE invoice_date >= ? AND status != 'cancelled'
    ''', [monthStart]);

    // Pending payments
    final pendingRes = await db.rawQuery('''
      SELECT SUM(balance_due) as total, COUNT(*) as count 
      FROM invoices 
      WHERE status != 'cancelled' AND payment_status IN ('unpaid', 'partially_paid', 'overdue')
    ''');

    // Customer count
    final custRes = await db.rawQuery('SELECT COUNT(*) as count FROM customers WHERE active = 1');

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
}
