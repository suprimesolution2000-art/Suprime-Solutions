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
    await db.insert(
      'payments',
      payment.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }
}
