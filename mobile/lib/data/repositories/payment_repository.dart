import 'package:sqflite/sqflite.dart';
import '../database/app_database.dart';
import '../models/payment_model.dart';

class PaymentRepository {
  final AppDatabase _db = AppDatabase.instance;

  Future<List<PaymentModel>> getPaymentsByInvoice(String invoiceUuid) async {
    final db = await _db.database;
    final results = await db.query(
      'payments',
      where: 'invoice_id = ?',
      whereArgs: [invoiceUuid],
      orderBy: 'payment_date DESC',
    );
    return results.map((m) => PaymentModel.fromMap(m)).toList();
  }

  Future<List<PaymentModel>> getPaymentsByCustomer(String customerUuid) async {
    final db = await _db.database;
    final results = await db.query(
      'payments',
      where: 'customer_id = ?',
      whereArgs: [customerUuid],
      orderBy: 'payment_date DESC',
    );
    return results.map((m) => PaymentModel.fromMap(m)).toList();
  }

  Future<void> savePayment(PaymentModel payment) async {
    final db = await _db.database;
    await db.transaction((txn) async {
      // 1. Insert or replace payment record
      await txn.insert(
        'payments',
        payment.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      // 2. Adjust invoice balances atomically
      if (payment.invoiceId.isNotEmpty) {
        final invRes = await txn.query(
          'invoices',
          columns: ['grand_total', 'total_paid', 'balance_due'],
          where: 'uuid = ?',
          whereArgs: [payment.invoiceId],
          limit: 1,
        );

        if (invRes.isNotEmpty) {
          final grandTotal = (invRes.first['grand_total'] as num?)?.toDouble() ?? 0.0;
          final currentPaid = (invRes.first['total_paid'] as num?)?.toDouble() ?? 0.0;
          final newPaid = currentPaid + payment.amount;
          final newBalanceDue = (grandTotal - newPaid).clamp(0.0, double.infinity);
          final newStatus = newBalanceDue <= 0.005
              ? 'paid'
              : (newPaid > 0.0 ? 'partially_paid' : 'unpaid');

          await txn.update(
            'invoices',
            {
              'total_paid': newPaid,
              'balance_due': newBalanceDue,
              'payment_status': newStatus,
              'sync_status': 'waiting_for_internet',
            },
            where: 'uuid = ?',
            whereArgs: [payment.invoiceId],
          );
        }
      }

      // 3. Adjust customer ledger balance atomically
      if (payment.customerId.isNotEmpty) {
        await txn.rawUpdate('''
          UPDATE customers 
          SET total_paid = COALESCE(total_paid, 0) + ?,
              outstanding_balance = MAX(0.0, COALESCE(outstanding_balance, 0) - ?)
          WHERE uuid = ?
        ''', [payment.amount, payment.amount, payment.customerId]);
      }
    });
  }
}
