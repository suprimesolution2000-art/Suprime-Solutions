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

  Future<List<PaymentModel>> getPaymentsForInvoice(String invoiceUuid) => getPaymentsByInvoice(invoiceUuid);

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
    if (payment.amount <= 0) return;
    final db = await _db.database;
    await db.transaction((txn) async {
      // Check idempotency (D4): if payment with this UUID already exists, do not double credit!
      final existingPayment = await txn.query(
        'payments',
        where: 'uuid = ?',
        whereArgs: [payment.uuid],
        limit: 1,
      );
      if (existingPayment.isNotEmpty) {
        return; // Idempotent: payment already recorded
      }

      // 1. Insert payment record
      await txn.insert(
        'payments',
        payment.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      // 2. Adjust invoice balances atomically
      bool isTemporary = false;
      if (payment.invoiceId.isNotEmpty) {
        final invRes = await txn.query(
          'invoices',
          columns: ['status', 'grand_total', 'total_paid', 'balance_due', 'invoice_type'],
          where: 'uuid = ?',
          whereArgs: [payment.invoiceId],
          limit: 1,
        );

        if (invRes.isNotEmpty) {
          final invoiceStatus = (invRes.first['status'] as String?)?.toLowerCase();
          if (invoiceStatus == 'cancelled') {
            throw Exception('Cannot record payment against a cancelled invoice.');
          }

          isTemporary = (invRes.first['invoice_type'] as String?) == 'temporary';
          final grandTotal = double.tryParse(invRes.first['grand_total']?.toString() ?? '') ?? 0.0;
          final currentPaid = double.tryParse(invRes.first['total_paid']?.toString() ?? '') ?? 0.0;
          final currentDue = double.tryParse(invRes.first['balance_due']?.toString() ?? '') ?? (grandTotal - currentPaid);

          if (currentDue <= 0.005 || payment.amount > (currentDue + 0.01)) {
            throw Exception('Payment amount (₹${payment.amount}) exceeds outstanding balance due (₹${currentDue.toStringAsFixed(2)}).');
          }

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

      // 3. Adjust customer ledger balance atomically (only for GST bills, not temporary bills)
      if (!isTemporary && payment.customerId.isNotEmpty) {
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
