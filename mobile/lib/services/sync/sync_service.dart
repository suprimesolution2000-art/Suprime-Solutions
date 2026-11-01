import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import '../../data/database/app_database.dart';
import '../api/api_client.dart';
import '../../data/models/invoice_model.dart';

enum SyncStatus {
  idle,
  syncing,
  synced,
  failed,
  offline
}

class SyncService extends ChangeNotifier {
  static final SyncService instance = SyncService._init();
  SyncService._init();

  SyncStatus _status = SyncStatus.idle;
  SyncStatus get status => _status;

  String _statusMessage = 'Up to date';
  String get statusMessage => _statusMessage;

  int _pendingCount = 0;
  int get pendingCount => _pendingCount;

  DateTime? _lastSyncTime;
  DateTime? get lastSyncTime => _lastSyncTime;

  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    final lastSyncStr = prefs.getString('last_sync_time');
    if (lastSyncStr != null) {
      _lastSyncTime = DateTime.tryParse(lastSyncStr);
    }
    await checkPendingQueue();
  }

  Future<void> checkPendingQueue() async {
    final db = await AppDatabase.instance.database;
    final res = await db.rawQuery(
      "SELECT COUNT(*) as count FROM invoices WHERE sync_status != 'synced'",
    );
    _pendingCount = (res.first['count'] as int?) ?? 0;
    notifyListeners();
  }

  // Trigger synchronization
  Future<bool> synchronize() async {
    _status = SyncStatus.syncing;
    _statusMessage = 'Syncing bills with cloud...';
    notifyListeners();

    try {
      final db = await AppDatabase.instance.database;
      final prefs = await SharedPreferences.getInstance();

      final deviceId = prefs.getString('device_id') ?? 'android_mobile_1';

      // 1. Collect pending invoices
      final pendingInvoicesData = await db.query(
        'invoices',
        where: "sync_status != 'synced'",
      );

      final invoicesToPush = pendingInvoicesData.map((row) {
        final inv = InvoiceModel.fromMap(row);
        return {
          'uuid': inv.uuid,
          'invoiceNumber': inv.invoiceNumber,
          'sequenceNumber': inv.sequenceNumber,
          'financialYear': inv.financialYear,
          'invoiceDate': inv.invoiceDate.toIso8601String(),
          'dueDate': inv.dueDate?.toIso8601String(),
          'poNumber': inv.poNumber,
          'poDate': inv.poDate?.toIso8601String(),
          'challanNumber': inv.challanNumber,
          'challanDate': inv.challanDate?.toIso8601String(),
          'customer': inv.customer.toMap(),
          'isInterState': inv.isInterState,
          'items': inv.items.map((e) => e.toMap()).toList(),
          'netAmount': inv.netAmount,
          'cgstTotal': inv.cgstTotal,
          'sgstTotal': inv.sgstTotal,
          'igstTotal': inv.igstTotal,
          'roundOff': inv.roundOff,
          'grandTotal': inv.grandTotal,
          'amountInWords': inv.amountInWords,
          'status': inv.status,
          'paymentStatus': inv.paymentStatus,
          'totalPaid': inv.totalPaid,
          'balanceDue': inv.balanceDue,
          'deviceId': deviceId,
        };
      }).toList();

      // 2. Push to backend if any
      if (invoicesToPush.isNotEmpty) {
        final pushRes = await ApiClient.instance.pushSync(
          deviceId: deviceId,
          invoices: invoicesToPush,
        );

        if (pushRes.statusCode == 200) {
          for (final row in pendingInvoicesData) {
            await db.update(
              'invoices',
              {'sync_status': 'synced'},
              where: 'uuid = ?',
              whereArgs: [row['uuid']],
            );
          }
        }
      }

      // 3. Pull updates from server
      final pullRes = await ApiClient.instance.pullSync(_lastSyncTime?.toIso8601String());
      if (pullRes.statusCode == 200 && pullRes.data['success'] == true) {
        final data = pullRes.data['data'];
        final serverInvoices = data['invoices'] as List? ?? [];

        for (final item in serverInvoices) {
          final serverInv = InvoiceModel.fromMap(Map<String, dynamic>.from(item));
          await db.insert(
            'invoices',
            serverInv.toMap(),
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
      }

      _lastSyncTime = DateTime.now();
      await prefs.setString('last_sync_time', _lastSyncTime!.toIso8601String());

      _status = SyncStatus.synced;
      _statusMessage = 'Cloud sync successful';
      _pendingCount = 0;
      notifyListeners();
      return true;
    } catch (e) {
      _status = SyncStatus.offline;
      _statusMessage = 'Offline: Saved locally, waiting for internet';
      await checkPendingQueue();
      notifyListeners();
      return false;
    }
  }
}
