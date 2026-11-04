import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import '../../data/database/app_database.dart';
import '../api/api_client.dart';
import '../../data/models/invoice_model.dart';
import '../../data/models/customer_model.dart';
import '../../data/models/payment_model.dart';
import '../../data/models/product_model.dart';
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
        'active': c['active'] == 1 || c['active'] == true,
      }).toList();

      // Collect local products to sync
      final localProducts = await db.query('products');
      final productsToPush = localProducts.map((p) => {
        'uuid': p['uuid'],
        'description': p['description'],
        'hsnCode': p['hsn_code'] ?? '',
        'unit': p['unit'] ?? 'PCS',
        'defaultRate': p['default_rate'] ?? 0.0,
        'gstRate': p['gst_rate'] ?? 18.0,
        'active': p['active'] == 1 || p['active'] == true,
      }).toList();

      // Collect local payments to sync
      final localPayments = await db.query('payments');
      final paymentsToPush = localPayments.map((p) => {
        'uuid': p['uuid'],
        'invoiceId': p['invoice_id'],
        'invoiceNumber': p['invoice_number'],
        'customerId': p['customer_id'],
        'customerName': p['customer_name'],
        'amount': p['amount'],
        'paymentMethod': p['payment_method'],
        'referenceNumber': p['reference_number'] ?? '',
        'paymentDate': p['payment_date'],
        'notes': p['notes'] ?? '',
        'receivedBy': p['received_by'] ?? 'Admin',
        'deviceId': p['device_id'] ?? deviceId,
      }).toList();

      // Process pending cloud deletions (tombstones recorded while offline)
      final allSettings = await db.query('app_settings');
      for (final s in allSettings) {
        final key = s['key'] as String;
        if (key.startsWith('deleted_invoice_')) {
          final uuid = key.replaceFirst('deleted_invoice_', '');
          try {
            await ApiClient.instance.deleteInvoice(uuid);
            await db.delete('app_settings', where: 'key = ?', whereArgs: [key]);
          } catch (_) {}
        } else if (key.startsWith('deleted_customer_')) {
          final uuid = key.replaceFirst('deleted_customer_', '');
          try {
            await ApiClient.instance.deleteCustomer(uuid);
            await db.delete('app_settings', where: 'key = ?', whereArgs: [key]);
          } catch (_) {}
        } else if (key.startsWith('deleted_product_')) {
          final uuid = key.replaceFirst('deleted_product_', '');
          try {
            await ApiClient.instance.deleteProduct(uuid);
            await db.delete('app_settings', where: 'key = ?', whereArgs: [key]);
          } catch (_) {}
        }
      }

      // 2. Push to backend if any
      if (invoicesToPush.isNotEmpty || customersToPush.isNotEmpty || productsToPush.isNotEmpty || paymentsToPush.isNotEmpty) {
        final pushRes = await ApiClient.instance.pushSync(
          deviceId: deviceId,
          customers: customersToPush,
          invoices: invoicesToPush,
          payments: paymentsToPush,
          products: productsToPush,
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

        final activeTombstones = (await db.query('app_settings'))
            .map((r) => r['key'] as String)
            .toSet();

        // 3a. Save cloud customers to local SQLite (ignoring deleted customers)
        final serverCustomers = data['customers'] as List? ?? [];
        for (final item in serverCustomers) {
          final custMap = Map<String, dynamic>.from(item);
          final serverCust = CustomerModel.fromMap(custMap);
          if (activeTombstones.contains('deleted_customer_${serverCust.uuid}')) {
            continue;
          }
          if (custMap['active'] == false || custMap['active'] == 0 || custMap['active'] == 'false') {
            await db.update('customers', {'active': 0}, where: 'uuid = ?', whereArgs: [serverCust.uuid]);
            continue;
          }
          if (serverCust.name.trim().isNotEmpty) {
            await custRepo.saveCustomer(serverCust);
          }
        }

        // 3b. Save cloud invoices (skipping deleted invoices and protecting unsynced local drafts)
        final serverInvoices = data['invoices'] as List? ?? [];
        for (final item in serverInvoices) {
          final invMap = Map<String, dynamic>.from(item);
          final serverInv = InvoiceModel.fromMap(invMap);
          if (activeTombstones.contains('deleted_invoice_${serverInv.uuid}') ||
              serverInv.status == 'cancelled' ||
              invMap['active'] == false) {
            // Deleted or cancelled invoice: remove from local DB and clean up orphaned payments
            await db.delete('invoices', where: 'uuid = ?', whereArgs: [serverInv.uuid]);
            await db.delete('payments', where: 'invoice_id = ?', whereArgs: [serverInv.uuid]);
            continue;
          }

          final localExisting = await db.query(
            'invoices',
            where: 'uuid = ?',
            whereArgs: [serverInv.uuid],
            limit: 1,
          );
          if (localExisting.isNotEmpty && localExisting.first['sync_status'] != 'synced') {
            continue; // Protect local offline changes
          }

          await db.insert(
            'invoices',
            serverInv.toMap(),
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
          if (serverInv.customer.name.trim().isNotEmpty &&
              !activeTombstones.contains('deleted_customer_${serverInv.customer.uuid}')) {
            final existingCust = await db.query(
              'customers',
              where: 'uuid = ?',
              whereArgs: [serverInv.customer.uuid],
              limit: 1,
            );
            if (existingCust.isEmpty || (existingCust.first['active'] == 1 || existingCust.first['active'] == 'true')) {
              await custRepo.saveCustomer(serverInv.customer);
            }
          }
        }

        // 3c. Save cloud payments
        final serverPayments = data['payments'] as List? ?? [];
        for (final item in serverPayments) {
          final payMap = Map<String, dynamic>.from(item);
          final serverPay = PaymentModel.fromMap(payMap);
          if (serverPay.uuid.isNotEmpty && !activeTombstones.contains('deleted_invoice_${serverPay.invoiceId}')) {
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
          final serverProd = ProductModel.fromMap(p);
          if (activeTombstones.contains('deleted_product_${serverProd.uuid}')) {
            continue;
          }
          if (p['active'] == false || p['active'] == 0 || p['active'] == 'false') {
            await db.update('products', {'active': 0}, where: 'uuid = ?', whereArgs: [serverProd.uuid]);
            continue;
          }
          if (serverProd.description.trim().isNotEmpty) {
            await prodRepo.saveProduct(serverProd);
          }
        }

        // 3e. Auto-recalculate customer balances from all synced invoices
        try {
          await custRepo.recalculateCustomerBalances();
        } catch (_) {}
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
