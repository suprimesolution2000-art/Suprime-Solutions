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
    int? limit,
    int offset = 0,
  }) async {
    final db = await _db.database;
    final whereClauses = <String>[];
    final whereArgs = <dynamic>[];

    // 1. Universal Search (D20: search term safely matching content values)
    if (searchQuery != null && searchQuery.trim().isNotEmpty) {
      final term = '%${searchQuery.trim()}%';
      final cleanTerm = searchQuery.trim().toLowerCase();
      final jsonKeys = {
        'name', 'rate', 'city', 'unit', 'gst', 'phone', 'items', 'state',
        'address', 'amount', 'status', 'description', 'hsn', 'total',
        'code', 'balance', 'uuid', 'pincode', 'email', 'price', 'quantity', 'qty'
      };
      final isJsonKey = jsonKeys.contains(cleanTerm);
      final jsonPattern = isJsonKey ? '%:"%$cleanTerm%"%' : term;

      whereClauses.add('''
        (
          invoice_number LIKE ? OR
          customer_json LIKE ? OR
          items_json LIKE ? OR
          po_number LIKE ? OR
          challan_number LIKE ?
        )
      ''');
      whereArgs.addAll([term, jsonPattern, jsonPattern, term, term]);
    }

    // 2. Invoice Type filter (GST vs Temporary)
    if (invoiceType != null && invoiceType.isNotEmpty) {
      if (invoiceType == 'temporary') {
        whereClauses.add("invoice_type = 'temporary'");
      } else if (invoiceType == 'gst') {
        whereClauses.add("(invoice_type IS NULL OR invoice_type != 'temporary')");
      }
    }

    // 2.5 City filter applied directly in SQL before LIMIT/OFFSET (D7 / S7)
    if (cityFilter != null && cityFilter.isNotEmpty && cityFilter != 'all') {
      whereClauses.add('LOWER(customer_json) LIKE ?');
      whereArgs.add('%"city":"${cityFilter.trim().toLowerCase()}"%');
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
      final end = DateTime(endDate.year, endDate.month, endDate.day, 23, 59, 59, 999);
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
      whereClauses.add('(customer_id = ? OR customer_json LIKE ?)');
      whereArgs.addAll([customerUuid, '%"uuid":"$customerUuid"%']);
    }

    final whereString = whereClauses.isNotEmpty ? whereClauses.join(' AND ') : null;

    // Determine initial SQL orderBy based on requested sort (S7 / D8)
    String sqlOrderBy = 'sequence_number DESC';
    if (sortBy == 'unpaid_first') {
      sqlOrderBy = "CASE LOWER(payment_status) WHEN 'unpaid' THEN 0 WHEN 'partially_paid' THEN 1 WHEN 'partial' THEN 1 WHEN 'overdue' THEN 1 WHEN 'paid' THEN 2 ELSE 3 END, invoice_date DESC, sequence_number DESC";
    } else if (sortBy == 'paid_first') {
      sqlOrderBy = "CASE LOWER(payment_status) WHEN 'paid' THEN 0 WHEN 'partially_paid' THEN 1 WHEN 'partial' THEN 1 WHEN 'overdue' THEN 1 WHEN 'unpaid' THEN 2 ELSE 3 END, invoice_date DESC, sequence_number DESC";
    } else if (sortBy == 'date_asc') {
      sqlOrderBy = 'invoice_date ASC, sequence_number ASC';
    } else if (sortBy == 'date_desc' || sortBy == 'invoice_date') {
      sqlOrderBy = 'invoice_date DESC, sequence_number DESC';
    } else if (sortBy == 'amount_asc') {
      sqlOrderBy = 'grand_total ASC, invoice_date DESC';
    } else if (sortBy == 'amount_desc') {
      sqlOrderBy = 'grand_total DESC, invoice_date DESC';
    } else if (sortBy == 'city_unpaid_first') {
      sqlOrderBy = "LOWER(COALESCE(json_extract(customer_json, '\$.city'), '')) ASC, CASE LOWER(payment_status) WHEN 'unpaid' THEN 0 WHEN 'partially_paid' THEN 1 WHEN 'partial' THEN 1 WHEN 'overdue' THEN 1 WHEN 'paid' THEN 2 ELSE 3 END, invoice_date DESC, sequence_number DESC";
    } else if (sortBy == 'city_paid_first') {
      sqlOrderBy = "LOWER(COALESCE(json_extract(customer_json, '\$.city'), '')) ASC, CASE LOWER(payment_status) WHEN 'paid' THEN 0 WHEN 'partially_paid' THEN 1 WHEN 'partial' THEN 1 WHEN 'overdue' THEN 1 WHEN 'unpaid' THEN 2 ELSE 3 END, invoice_date DESC, sequence_number DESC";
    }

    final results = await db.query(
      'invoices',
      where: whereString,
      whereArgs: whereArgs.isNotEmpty ? whereArgs : null,
      orderBy: sqlOrderBy,
      limit: limit,
      offset: offset,
    );

    var invoices = results.map((m) => InvoiceModel.fromMap(m)).toList();

    int paymentPriority(String status, {bool unpaidFirst = true}) {
      final s = status.toLowerCase();
      if (unpaidFirst) {
        if (s == 'unpaid') return 0;
        if (s == 'partially_paid' || s == 'partial' || s == 'overdue') return 1;
        if (s == 'paid') return 2;
        return 3;
      } else {
        if (s == 'paid') return 0;
        if (s == 'partially_paid' || s == 'partial' || s == 'overdue') return 1;
        if (s == 'unpaid') return 2;
        return 3;
      }
    }

    // Explicit in-memory sorting: guarantees 100% accurate ordering for all 6 options
    if (sortBy == 'date_desc' || sortBy == 'invoice_date') {
      invoices.sort((a, b) {
        final dCmp = b.invoiceDate.compareTo(a.invoiceDate);
        if (dCmp != 0) return dCmp;
        return b.sequenceNumber.compareTo(a.sequenceNumber);
      });
    } else if (sortBy == 'date_asc') {
      invoices.sort((a, b) {
        final dCmp = a.invoiceDate.compareTo(b.invoiceDate);
        if (dCmp != 0) return dCmp;
        return a.sequenceNumber.compareTo(b.sequenceNumber);
      });
    } else if (sortBy == 'amount_desc') {
      invoices.sort((a, b) {
        final aCmp = b.grandTotal.compareTo(a.grandTotal);
        if (aCmp != 0) return aCmp;
        return b.invoiceDate.compareTo(a.invoiceDate);
      });
    } else if (sortBy == 'amount_asc') {
      invoices.sort((a, b) {
        final aCmp = a.grandTotal.compareTo(b.grandTotal);
        if (aCmp != 0) return aCmp;
        return b.invoiceDate.compareTo(a.invoiceDate);
      });
    } else if (sortBy == 'unpaid_first') {
      invoices.sort((a, b) {
        final pCmp = paymentPriority(a.paymentStatus, unpaidFirst: true)
            .compareTo(paymentPriority(b.paymentStatus, unpaidFirst: true));
        if (pCmp != 0) return pCmp;
        return b.invoiceDate.compareTo(a.invoiceDate);
      });
    } else if (sortBy == 'paid_first') {
      invoices.sort((a, b) {
        final pCmp = paymentPriority(a.paymentStatus, unpaidFirst: false)
            .compareTo(paymentPriority(b.paymentStatus, unpaidFirst: false));
        if (pCmp != 0) return pCmp;
        return b.invoiceDate.compareTo(a.invoiceDate);
      });
    } else if (sortBy == 'city_unpaid_first') {
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
    final end = DateTime(to.year, to.month, to.day, 23, 59, 59, 999).toIso8601String();

    final results = await db.query(
      'invoices',
      where: "status != 'cancelled' AND (invoice_type IS NULL OR invoice_type != 'temporary') AND invoice_date >= ? AND invoice_date <= ?",
      whereArgs: [start, end],
      orderBy: 'invoice_date ASC, sequence_number ASC',
    );

    return results.map((m) => InvoiceModel.fromMap(m)).toList();
  }

  /// Get all active Temporary Bills for a date range in chronological ascending order
  Future<List<InvoiceModel>> getTemporaryInvoicesForDateRange(DateTime from, DateTime to) async {
    final db = await _db.database;
    final start = DateTime(from.year, from.month, from.day).toIso8601String();
    final end = DateTime(to.year, to.month, to.day, 23, 59, 59, 999).toIso8601String();

    final results = await db.query(
      'invoices',
      where: "status != 'cancelled' AND invoice_type = 'temporary' AND invoice_date >= ? AND invoice_date <= ?",
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
      unawaited(SyncService.instance.synchronize(forceFullSync: false));
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
        'sync_status': 'waiting_for_internet',
      },
      where: 'uuid = ?',
      whereArgs: [invoiceUuid],
    );
    try {
      await CustomerRepository().recalculateCustomerBalances();
      await SyncService.instance.checkPendingQueue();
      unawaited(SyncService.instance.synchronize(forceFullSync: false));
    } catch (_) {}
  }

  Future<void> cancelInvoice(String invoiceUuid) async {
    final db = await _db.database;
    await db.update(
      'invoices',
      {
        'status': 'cancelled',
        'sync_status': 'waiting_for_internet',
      },
      where: 'uuid = ?',
      whereArgs: [invoiceUuid],
    );
    try {
      await CustomerRepository().recalculateCustomerBalances();
      await SyncService.instance.checkPendingQueue();
      unawaited(SyncService.instance.synchronize(forceFullSync: false));
    } catch (_) {}
  }

  Future<void> updateInvoice(
    InvoiceModel invoice, {
    double deltaGrandTotal = 0.0,
    double deltaBalanceDue = 0.0,
  }) async {
    final db = await _db.database;
    await db.transaction((txn) async {
      await txn.update(
        'invoices',
        invoice.toMap(),
        where: 'uuid = ?',
        whereArgs: [invoice.uuid],
      );

      // Adjust customer ledger balance
      final custRows = await txn.query('customers', where: 'uuid = ?', whereArgs: [invoice.customer.uuid], limit: 1);
      if (custRows.isNotEmpty) {
        final currentBilled = double.tryParse(custRows.first['total_billed']?.toString() ?? '') ?? 0.0;
        final currentDue = double.tryParse(custRows.first['outstanding_balance']?.toString() ?? '') ?? 0.0;
        await txn.update(
          'customers',
          {
            'total_billed': (currentBilled + deltaGrandTotal).clamp(0.0, double.infinity),
            'outstanding_balance': (currentDue + deltaBalanceDue).clamp(0.0, double.infinity),
          },
          where: 'uuid = ?',
          whereArgs: [invoice.customer.uuid],
        );
      }
    });

    try {
      await CustomerRepository().recalculateCustomerBalances(targetCustomerUuid: invoice.customer.uuid);
      await SyncService.instance.checkPendingQueue();
      unawaited(SyncService.instance.synchronize(forceFullSync: false));
    } catch (_) {}
  }

  Future<void> deleteInvoice(String invoiceUuid) async {
    final db = await _db.database;
    final inv = await getInvoiceByUuid(invoiceUuid);

    await db.transaction((txn) async {
      if (inv != null && inv.status != 'cancelled' && inv.invoiceType != 'temporary') {
        // Revert customer outstanding balance and payments
        List<Map<String, dynamic>> custRows = [];
        if (inv.customer.uuid.isNotEmpty) {
          custRows = await txn.query('customers', where: 'uuid = ?', whereArgs: [inv.customer.uuid], limit: 1);
        }
        if (custRows.isEmpty && inv.customer.phone.isNotEmpty) {
          custRows = await txn.query('customers', where: 'phone = ?', whereArgs: [inv.customer.phone], limit: 1);
        }
        if (custRows.isEmpty && inv.customer.name.trim().isNotEmpty) {
          custRows = await txn.query('customers', where: 'LOWER(name) = ?', whereArgs: [inv.customer.name.trim().toLowerCase()], limit: 1);
        }
        if (custRows.isNotEmpty) {
          final matchedCustUuid = custRows.first['uuid'] as String;
          final currentBilled = double.tryParse(custRows.first['total_billed']?.toString() ?? '') ?? 0.0;
          final currentPaid = double.tryParse(custRows.first['total_paid']?.toString() ?? '') ?? 0.0;
          final currentDue = double.tryParse(custRows.first['outstanding_balance']?.toString() ?? '') ?? 0.0;
          await txn.update(
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
      }

      // Clean up any payments associated with this deleted invoice
      await txn.delete(
        'payments',
        where: 'invoice_id = ?',
        whereArgs: [invoiceUuid],
      );

      // Record tombstone so cloud pullSync does not resurrect this deleted invoice
      await txn.insert(
        'app_settings',
        {'key': 'deleted_invoice_$invoiceUuid', 'value': DateTime.now().toIso8601String()},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      await txn.delete(
        'invoices',
        where: 'uuid = ?',
        whereArgs: [invoiceUuid],
      );
    });

    try {
      await CustomerRepository().recalculateCustomerBalances();
      await SyncService.instance.checkPendingQueue();
      unawaited(SyncService.instance.synchronize(forceFullSync: false));
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

    final maxRes = await db.rawQuery(
      "SELECT MAX(sequence_number) as max_seq FROM invoices WHERE (invoice_type IS NULL OR invoice_type != 'temporary') AND financial_year = ?",
      [fy],
    );
    int maxSeq = 0;
    if (maxRes.isNotEmpty && maxRes.first['max_seq'] != null) {
      maxSeq = int.tryParse(maxRes.first['max_seq']?.toString() ?? '') ?? 0;
    }

    final nextNumRes = await db.query('app_settings', where: 'key = ?', whereArgs: ['next_usable_number_$fy']);
    int savedNum = 1;
    if (nextNumRes.isNotEmpty) {
      savedNum = int.tryParse(nextNumRes.first['value'] as String) ?? 1;
    } else if (fy == '26-27') {
      final legacyRes = await db.query('app_settings', where: 'key = ?', whereArgs: ['next_usable_number']);
      if (legacyRes.isNotEmpty) {
        savedNum = int.tryParse(legacyRes.first['value'] as String) ?? 1;
      }
    }

    int nextNum = savedNum > (maxSeq + 1) ? savedNum : (maxSeq + 1);

    // Collision check preview
    while (true) {
      final existing = await db.rawQuery(
        "SELECT 1 FROM invoices WHERE (invoice_type IS NULL OR invoice_type != 'temporary') AND financial_year = ? AND sequence_number = ?",
        [fy, nextNum],
      );
      if (existing.isEmpty) break;
      nextNum++;
    }

    final prefixRes = await db.query('app_settings', where: 'key = ?', whereArgs: ['invoice_prefix']);
    final prefix = prefixRes.isNotEmpty ? (prefixRes.first['value'] as String? ?? '') : '';

    return prefix.isNotEmpty ? '$prefix$nextNum' : '$nextNum';
  }

  // Preview next temporary bill number without advancing the sequence (Temporary bills)
  Future<String> getNextTemporaryInvoiceNumberPreview(DateTime date) async {
    final db = await _db.database;
    final fy = getFinancialYear(date);

    final maxRes = await db.rawQuery(
      "SELECT MAX(sequence_number) as max_seq FROM invoices WHERE invoice_type = 'temporary' AND financial_year = ?",
      [fy],
    );
    int maxSeq = 0;
    if (maxRes.isNotEmpty && maxRes.first['max_seq'] != null) {
      maxSeq = int.tryParse(maxRes.first['max_seq']?.toString() ?? '') ?? 0;
    }

    // DATA-15: Financial-year partitioned temporary bill counter
    final nextNumRes = await db.query('app_settings', where: 'key = ?', whereArgs: ['next_temporary_number_$fy']);
    int savedNum = 1;
    if (nextNumRes.isNotEmpty) {
      savedNum = int.tryParse(nextNumRes.first['value'] as String) ?? 1;
    } else if (fy == '26-27') {
      final legacyRes = await db.query('app_settings', where: 'key = ?', whereArgs: ['next_temporary_number']);
      if (legacyRes.isNotEmpty) {
        savedNum = int.tryParse(legacyRes.first['value'] as String) ?? 1;
      }
    }

    int nextNum = savedNum > (maxSeq + 1) ? savedNum : (maxSeq + 1);

    // Ensure candidate doesn't already exist locally in this FY
    while (true) {
      final existing = await db.rawQuery(
        "SELECT 1 FROM invoices WHERE invoice_type = 'temporary' AND financial_year = ? AND (invoice_number = ? OR sequence_number = ?)",
        [fy, nextNum.toString(), nextNum],
      );
      if (existing.isEmpty) break;
      nextNum++;
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
      final maxRes = await txn.rawQuery(
        "SELECT MAX(sequence_number) as max_seq FROM invoices WHERE (invoice_type IS NULL OR invoice_type != 'temporary') AND financial_year = ?",
        [fy],
      );
      int maxSeq = 0;
      if (maxRes.isNotEmpty && maxRes.first['max_seq'] != null) {
        maxSeq = int.tryParse(maxRes.first['max_seq']?.toString() ?? '') ?? 0;
      }

      final nextNumRes = await txn.query('app_settings', where: 'key = ?', whereArgs: ['next_usable_number_$fy']);
      int savedNum = 1;
      if (nextNumRes.isNotEmpty) {
        savedNum = int.tryParse(nextNumRes.first['value'] as String) ?? 1;
      } else if (fy == '26-27') {
        final legacyRes = await txn.query('app_settings', where: 'key = ?', whereArgs: ['next_usable_number']);
        if (legacyRes.isNotEmpty) {
          savedNum = int.tryParse(legacyRes.first['value'] as String) ?? 1;
        }
      }

      int nextNum = savedNum > (maxSeq + 1) ? savedNum : (maxSeq + 1);

      // Ensure candidate doesn't already exist locally
      while (true) {
        final existing = await txn.rawQuery(
          "SELECT 1 FROM invoices WHERE (invoice_type IS NULL OR invoice_type != 'temporary') AND financial_year = ? AND sequence_number = ?",
          [fy, nextNum],
        );
        if (existing.isEmpty) break;
        nextNum++;
      }

      final prefixRes = await txn.query('app_settings', where: 'key = ?', whereArgs: ['invoice_prefix']);
      final prefix = prefixRes.isNotEmpty ? (prefixRes.first['value'] as String? ?? '') : '';

      String invoiceNumber;
      int seqNum;

      if (customInvoiceNumber != null && customInvoiceNumber.trim().isNotEmpty) {
        final candidate = customInvoiceNumber.trim();
        final duplicate = await txn.rawQuery(
          "SELECT 1 FROM invoices WHERE invoice_number = ? AND financial_year = ? AND (invoice_type IS NULL OR invoice_type != 'temporary')",
          [candidate, fy],
        );
        if (duplicate.isNotEmpty) {
          throw Exception('Invoice number "$candidate" already exists for financial year $fy.');
        }
        invoiceNumber = candidate;
        final match = RegExp(r'(\d+)$').firstMatch(invoiceNumber) ?? RegExp(r'(\d+)').firstMatch(invoiceNumber);
        final parsed = match != null ? int.tryParse(match.group(1)!) : null;
        if (parsed != null) {
          final seqDuplicate = await txn.rawQuery(
            "SELECT 1 FROM invoices WHERE sequence_number = ? AND financial_year = ? AND (invoice_type IS NULL OR invoice_type != 'temporary')",
            [parsed, fy],
          );
          seqNum = seqDuplicate.isEmpty ? parsed : nextNum;
        } else {
          seqNum = nextNum;
        }
        nextNum = (seqNum >= nextNum) ? seqNum + 1 : nextNum + 1;
      } else {
        invoiceNumber = prefix.isNotEmpty ? '$prefix$nextNum' : '$nextNum';
        seqNum = nextNum;
        nextNum = nextNum + 1;
      }

      // Increment and save next usable number partitioned by financial year
      await txn.insert(
        'app_settings',
        {'key': 'next_usable_number_$fy', 'value': nextNum.toString()},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
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
      final maxRes = await txn.rawQuery(
        "SELECT MAX(sequence_number) as max_seq FROM invoices WHERE invoice_type = 'temporary' AND financial_year = ?",
        [fy],
      );
      int maxSeq = 0;
      if (maxRes.isNotEmpty && maxRes.first['max_seq'] != null) {
        maxSeq = int.tryParse(maxRes.first['max_seq']?.toString() ?? '') ?? 0;
      }

      final nextNumRes = await txn.query('app_settings', where: 'key = ?', whereArgs: ['next_temporary_number_$fy']);
      int savedNum = 1;
      if (nextNumRes.isNotEmpty) {
        savedNum = int.tryParse(nextNumRes.first['value'] as String) ?? 1;
      } else if (fy == '26-27') {
        final legacyRes = await txn.query('app_settings', where: 'key = ?', whereArgs: ['next_temporary_number']);
        if (legacyRes.isNotEmpty) {
          savedNum = int.tryParse(legacyRes.first['value'] as String) ?? 1;
        }
      }

      int nextNum = savedNum > (maxSeq + 1) ? savedNum : (maxSeq + 1);

      // Verify nextNum doesn't collide with existing invoice in this FY
      while (true) {
        final existing = await txn.rawQuery(
          "SELECT 1 FROM invoices WHERE invoice_type = 'temporary' AND financial_year = ? AND (invoice_number = ? OR sequence_number = ?)",
          [fy, nextNum.toString(), nextNum],
        );
        if (existing.isEmpty) break;
        nextNum++;
      }

      final prefixRes = await txn.query('app_settings', where: 'key = ?', whereArgs: ['temporary_invoice_prefix']);
      final prefix = prefixRes.isNotEmpty ? (prefixRes.first['value'] as String? ?? '') : '';

      String invoiceNumber;
      int seqNum;

      if (customInvoiceNumber != null && customInvoiceNumber.trim().isNotEmpty) {
        final candidateStr = customInvoiceNumber.trim();
        // Check if candidateStr already exists in this FY
        final existing = await txn.rawQuery(
          "SELECT 1 FROM invoices WHERE invoice_type = 'temporary' AND financial_year = ? AND invoice_number = ?",
          [fy, candidateStr],
        );
        if (existing.isEmpty) {
          invoiceNumber = candidateStr;
          final match = RegExp(r'(\d+)$').firstMatch(invoiceNumber) ?? RegExp(r'(\d+)').firstMatch(invoiceNumber);
          final parsed = match != null ? int.tryParse(match.group(1)!) : null;
          if (parsed != null) {
            final seqDuplicate = await txn.rawQuery(
              "SELECT 1 FROM invoices WHERE invoice_type = 'temporary' AND financial_year = ? AND sequence_number = ?",
              [parsed, fy],
            );
            seqNum = seqDuplicate.isEmpty ? parsed : nextNum;
          } else {
            seqNum = nextNum;
          }
          nextNum = (seqNum >= nextNum) ? seqNum + 1 : nextNum + 1;
        } else {
          // If candidateStr was already taken, assign next fresh sequential number
          invoiceNumber = prefix.isNotEmpty ? '$prefix$nextNum' : '$nextNum';
          seqNum = nextNum;
          nextNum = nextNum + 1;
        }
      } else {
        invoiceNumber = prefix.isNotEmpty ? '$prefix$nextNum' : '$nextNum';
        seqNum = nextNum;
        nextNum = nextNum + 1;
      }

      // Persist the incremented counter partitioned by financial year
      await txn.insert(
        'app_settings',
        {'key': 'next_temporary_number_$fy', 'value': nextNum.toString()},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
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
    final todayEnd = DateTime(now.year, now.month, now.day, 23, 59, 59, 999).toIso8601String();
    final monthStart = DateTime(now.year, now.month, 1).toIso8601String();
    final monthEnd = DateTime(now.year, now.month + 1, 0, 23, 59, 59, 999).toIso8601String();

    // Today's sales (Excludes cancelled & temporary bills; upper bounded to prevent future-dated bill inflation)
    final todayRes = await db.rawQuery('''
      SELECT SUM(grand_total) as total, COUNT(*) as count 
      FROM invoices 
      WHERE invoice_date >= ? AND invoice_date <= ? AND status != 'cancelled' AND (invoice_type IS NULL OR invoice_type != 'temporary')
    ''', [todayStart, todayEnd]);

    // Month's sales (Excludes cancelled & temporary bills; upper bounded to prevent future-dated bill inflation)
    final monthRes = await db.rawQuery('''
      SELECT SUM(grand_total) as total, COUNT(*) as count 
      FROM invoices 
      WHERE invoice_date >= ? AND invoice_date <= ? AND status != 'cancelled' AND (invoice_type IS NULL OR invoice_type != 'temporary')
    ''', [monthStart, monthEnd]);

    // Pending payments (Excludes cancelled & temporary bills)
    final pendingRes = await db.rawQuery('''
      SELECT SUM(balance_due) as total, COUNT(*) as count 
      FROM invoices 
      WHERE status != 'cancelled' AND (invoice_type IS NULL OR invoice_type != 'temporary') AND payment_status IN ('unpaid', 'partially_paid', 'overdue')
    ''');

    // Customer count
    final custRes = await db.rawQuery("SELECT COUNT(*) as count FROM customers WHERE (active = 1 OR active IS NULL OR active = 'true')");

    return {
      'todaySales': double.tryParse(todayRes.first['total']?.toString() ?? '') ?? 0.0,
      'todayCount': int.tryParse(todayRes.first['count']?.toString() ?? '') ?? 0,
      'monthlySales': double.tryParse(monthRes.first['total']?.toString() ?? '') ?? 0.0,
      'monthlyCount': int.tryParse(monthRes.first['count']?.toString() ?? '') ?? 0,
      'pendingPayments': double.tryParse(pendingRes.first['total']?.toString() ?? '') ?? 0.0,
      'pendingCount': int.tryParse(pendingRes.first['count']?.toString() ?? '') ?? 0,
      'customerCount': int.tryParse(custRes.first['count']?.toString() ?? '') ?? 0,
    };
  }
  /// Automatically extracts and repairs city data for legacy bills and customers
  Future<void> autoRepairLegacyCities() async {
    try {
      final db = await _db.database;
      final rows = await db.query('invoices', columns: ['uuid', 'customer_json', 'invoice_type', 'invoice_number', 'sequence_number']);
      final batch = db.batch();
      bool needsUpdate = false;

      for (final r in rows) {
        final uuid = r['uuid'] as String;
        final rawCust = r['customer_json'] as String?;
        if (rawCust == null || rawCust.isEmpty) continue;
        try {
          final custMap = jsonDecode(rawCust) as Map<String, dynamic>;
          final custName = (custMap['name'] ?? '').toString().toLowerCase();
          final currentCity = (custMap['city'] ?? '').toString();
          final address = (custMap['address'] ?? '').toString();
          String extracted = CityHelper.extractCity(currentCity, address);

          // Explicit Bhagyodaya / Nashik fix
          if (custName.contains('bhagyodaya') || address.toLowerCase().contains('nasik') || address.toLowerCase().contains('nashik')) {
            extracted = 'Nashik';
          }

          if (extracted != currentCity && extracted.isNotEmpty) {
            custMap['city'] = extracted;
            batch.update(
              'invoices',
              {
                'customer_json': jsonEncode(custMap),
                'sync_status': 'waiting_for_internet',
              },
              where: 'uuid = ?',
              whereArgs: [uuid],
            );
            needsUpdate = true;
          }
        } catch (_) {}
      }

      final custRows = await db.query('customers', columns: ['uuid', 'name', 'city', 'address']);
      for (final c in custRows) {
        final uuid = c['uuid'] as String;
        final name = (c['name'] ?? '').toString().toLowerCase();
        final currentCity = (c['city'] ?? '').toString();
        final address = (c['address'] ?? '').toString();
        String extracted = CityHelper.extractCity(currentCity, address);

        if (name.contains('bhagyodaya') || address.toLowerCase().contains('nasik') || address.toLowerCase().contains('nashik')) {
          extracted = 'Nashik';
        }

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

      // Ensure local next_temporary_number counter is aligned with existing invoices
      final maxTempRes = await db.rawQuery(
        "SELECT MAX(sequence_number) as max_seq FROM invoices WHERE invoice_type = 'temporary'"
      );
      if (maxTempRes.isNotEmpty && maxTempRes.first['max_seq'] != null) {
        final maxSeq = int.tryParse(maxTempRes.first['max_seq']?.toString() ?? '') ?? 0;
        final currentTempRes = await db.query('app_settings', where: 'key = ?', whereArgs: ['next_temporary_number']);
        final currentTemp = currentTempRes.isNotEmpty ? (int.tryParse(currentTempRes.first['value'] as String) ?? 1) : 1;
        if (maxSeq + 1 > currentTemp) {
          batch.insert(
            'app_settings',
            {'key': 'next_temporary_number', 'value': (maxSeq + 1).toString()},
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
          needsUpdate = true;
        }
      }

      if (needsUpdate) {
        await batch.commit(noResult: true);
      }
    } catch (_) {}
  }

  /// Returns a map of city name -> number of bills in that city
  Future<Map<String, int>> getCityBillCounts() async {
    final db = await _db.database;
    final rows = await db.query('invoices', columns: ['customer_json']);
    final counts = <String, int>{};
    for (final r in rows) {
      final raw = r['customer_json'] as String?;
      if (raw != null && raw.isNotEmpty) {
        try {
          final map = jsonDecode(raw) as Map<String, dynamic>;
          final c = CityHelper.extractCity((map['city'] ?? '').toString(), (map['address'] ?? '').toString());
          if (c.isNotEmpty) {
            counts[c] = (counts[c] ?? 0) + 1;
          }
        } catch (_) {}
      }
    }
    return counts;
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
