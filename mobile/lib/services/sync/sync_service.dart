import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import '../../data/database/app_database.dart';
import '../api/api_client.dart';
import '../../data/models/invoice_model.dart';
import '../../data/models/customer_model.dart';
import '../../data/models/payment_model.dart';
import '../../data/repositories/customer_repository.dart';
import '../../data/repositories/product_repository.dart';

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
    // Auto-heal local customers from existing local bills if any exist
    try {
      await CustomerRepository().recoverCustomersFromInvoices();
    } catch (_) {}

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
  Future<bool> synchronize({bool forceFullSync = false}) async {
    _status = SyncStatus.syncing;
    _statusMessage = 'Syncing bills with cloud...';
    notifyListeners();

    try {
      final db = await AppDatabase.instance.database;
      final prefs = await SharedPreferences.getInstance();

      final deviceId = prefs.getString('device_id') ?? 'android_mobile_1';

      // Auto-heal customers from local invoices
      try {
        await CustomerRepository().recoverCustomersFromInvoices();
      } catch (_) {}

      // Self-healing check: Compare local invoices with cloud server
      try {
        final checkRes = await ApiClient.instance.pullSync(null);
        if (checkRes.statusCode == 200 && checkRes.data['success'] == true) {
          final serverList = checkRes.data['data']['invoices'] as List? ?? [];
          final serverUuids = serverList.map((i) => i['uuid']?.toString()).toSet();
          final allLocal = await db.query('invoices');
          for (final row in allLocal) {
            final u = row['uuid']?.toString();
            if (u != null && !serverUuids.contains(u)) {
              await db.update(
                'invoices',
                {'sync_status': 'waiting_for_internet'},
                where: 'uuid = ?',
                whereArgs: [u],
              );
            }
          }
        }
      } catch (_) {
        // Continue with normal sync flow if pre-check fails
      }

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
          'items': inv.items.map((e) => e.toApiMap()).toList(),
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
          'createdBy': inv.createdBy.isNotEmpty ? inv.createdBy : 'Administrator',
        };
      }).toList();

      // Collect all local customers to sync
      final localCustomers = await db.query(
        'customers',
        where: "active = 1 OR active IS NULL OR active = 'true'",
      );
      final customersToPush = localCustomers.map((c) => {
        'uuid': c['uuid'],
        'name': c['name'],
        'businessName': c['business_name'] ?? '',
        'phone': c['phone'] ?? '',
        'email': c['email'] ?? '',
        'gstin': c['gstin'] ?? '',
        'address': c['address'] ?? '',
        'city': c['city'] ?? '',
        'state': c['state'] ?? 'Chhattisgarh',
        'stateCode': c['state_code'] ?? '22',
        'pincode': c['pincode'] ?? '',
        'outstandingBalance': c['outstanding_balance'] ?? 0.0,
        'totalBilled': c['total_billed'] ?? 0.0,
        'totalPaid': c['total_paid'] ?? 0.0,
        'active': true,
      }).toList();

      // 2. Push to backend if any
      if (invoicesToPush.isNotEmpty || customersToPush.isNotEmpty) {
        final pushRes = await ApiClient.instance.pushSync(
          deviceId: deviceId,
          customers: customersToPush,
          invoices: invoicesToPush,
        );

        if (pushRes.statusCode == 200 && pushRes.data['success'] == true) {
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
      // If local DB has 0 customers or forceFullSync requested, ALWAYS do full sync
      final custCount = Sqflite.firstIntValue(
        await db.rawQuery("SELECT COUNT(*) FROM customers WHERE (active = 1 OR active IS NULL OR active = 'true')"),
      ) ?? 0;

      final bool doFullPull = forceFullSync || custCount == 0 || _lastSyncTime == null;
      final String? sinceParam = doFullPull ? null : _lastSyncTime?.toIso8601String();

      final pullRes = await ApiClient.instance.pullSync(sinceParam);
      if (pullRes.statusCode == 200 && pullRes.data['success'] == true) {
        final data = pullRes.data['data'];
        final custRepo = CustomerRepository();

        // 3a. Save cloud customers to local SQLite
        final serverCustomers = data['customers'] as List? ?? [];
        for (final item in serverCustomers) {
          final custMap = Map<String, dynamic>.from(item);
          final serverCust = CustomerModel.fromMap(custMap);
          if (serverCust.name.trim().isNotEmpty) {
            await custRepo.saveCustomer(serverCust);
          }
        }

        // 3b. Save cloud invoices and ensure invoice customer is saved locally
        final serverInvoices = data['invoices'] as List? ?? [];
        for (final item in serverInvoices) {
          final serverInv = InvoiceModel.fromMap(Map<String, dynamic>.from(item));
          await db.insert(
            'invoices',
            serverInv.toMap(),
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
          if (serverInv.customer.name.trim().isNotEmpty) {
            await custRepo.saveCustomer(serverInv.customer);
          }
        }

        // 3c. Save cloud payments
        final serverPayments = data['payments'] as List? ?? [];
        for (final item in serverPayments) {
          final payMap = Map<String, dynamic>.from(item);
          final serverPay = PaymentModel.fromMap(payMap);
          if (serverPay.uuid.isNotEmpty) {
            await db.insert(
              'payments',
              serverPay.toMap(),
              conflictAlgorithm: ConflictAlgorithm.replace,
            );
          }
        }

        // 3d. Save products catalogue
        final serverProducts = data['products'] as List? ?? [];
        final prodRepo = ProductRepository();
        for (final item in serverProducts) {
          final p = Map<String, dynamic>.from(item);
          if (p['description'] != null && (p['description'] as String).trim().isNotEmpty) {
            await prodRepo.saveOrUpdateProduct(
              description: p['description'],
              hsnCode: p['hsnCode'] ?? p['hsn_code'] ?? '',
              unit: p['unit'] ?? 'PCS',
              defaultRate: (p['defaultRate'] ?? p['default_rate'] ?? 0.0).toDouble(),
              gstRate: (p['gstRate'] ?? p['gst_rate'] ?? 18.0).toDouble(),
            );
          }
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
