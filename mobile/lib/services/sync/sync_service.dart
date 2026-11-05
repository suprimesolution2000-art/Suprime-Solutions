import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
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

class SyncService extends ChangeNotifier with WidgetsBindingObserver {
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

  bool _isSyncing = false;
  Timer? _foregroundTimer;

  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    final lastSyncStr = prefs.getString('last_sync_time');
    if (lastSyncStr != null) {
      _lastSyncTime = DateTime.tryParse(lastSyncStr);
    }

    // Register app lifecycle observer to sync on open, resume, and close
    WidgetsBinding.instance.addObserver(this);

    // Auto-heal local customers from existing local bills if any exist
    try {
      await CustomerRepository().recoverCustomersFromInvoices();
    } catch (_) {}

    await checkPendingQueue();

    // Start periodic background sync for active sessions (every 25 seconds)
    _startForegroundTimer();

    // Initial full sync on app startup
    unawaited(synchronize(forceFullSync: true));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      debugPrint('[SyncService] App resumed: Triggering immediate full refresh of bills, customers, products...');
      _startForegroundTimer();
      synchronize(forceFullSync: true);
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      debugPrint('[SyncService] App closing / backgrounding: Flushing pending bills to cloud...');
      _stopForegroundTimer();
      // Immediately push all local pending records before app is suspended/closed
      synchronize(forceFullSync: false);
    }
  }

  void _startForegroundTimer() {
    _stopForegroundTimer();
    _foregroundTimer = Timer.periodic(const Duration(seconds: 25), (timer) {
      if (!_isSyncing) {
        synchronize(forceFullSync: true);
      }
    });
  }

  void _stopForegroundTimer() {
    _foregroundTimer?.cancel();
    _foregroundTimer = null;
  }

  Future<void> checkPendingQueue() async {
    final db = await AppDatabase.instance.database;
    final res = await db.rawQuery(
      "SELECT COUNT(*) as count FROM invoices WHERE sync_status != 'synced'",
    );
    _pendingCount = (res.first['count'] as int?) ?? 0;
    notifyListeners();
  }

  // Trigger synchronization across bills, customers, products, and payments
  Future<bool> synchronize({bool forceFullSync = false}) async {
    if (_isSyncing) return false;
    _isSyncing = true;
    _status = SyncStatus.syncing;
    _statusMessage = 'Syncing bills with cloud...';
    notifyListeners();

    try {
      final db = await AppDatabase.instance.database;
      final prefs = await SharedPreferences.getInstance();

      final deviceId = prefs.getString('device_id') ?? 'android_mobile_1';

      // 1. Collect pending invoices created/edited on this device
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

      // Collect products
      final localProducts = await db.query(
        'products',
        where: "active = 1 OR active IS NULL OR active = 'true'",
      );
      final productsToPush = localProducts.map((p) => {
        'uuid': p['uuid'],
        'description': p['description'],
        'hsnCode': p['hsn_code'] ?? '',
        'unit': p['unit'] ?? 'PCS',
        'defaultRate': p['default_rate'] ?? 0.0,
        'gstRate': p['gst_rate'] ?? 18.0,
        'active': p['active'] == 1 || p['active'] == true,
      }).toList();

      // Collect payments
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

      // Step 1: Push to backend if any pending items
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

      // Step 2: Always request full sync to eliminate device clock and timezone drift between devices
      final pullRes = await ApiClient.instance.pullSync(null);
      if (pullRes.statusCode == 200 && pullRes.data['success'] == true) {
        final data = pullRes.data['data'];
        final custRepo = CustomerRepository();

        final activeTombstones = (await db.query('app_settings'))
            .map((r) => r['key'] as String)
            .toSet();

        // 2a. Save cloud customers
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

        // 2b. Save cloud invoices
        final serverInvoices = data['invoices'] as List? ?? [];
        int maxServerSeq = 0;
        for (final item in serverInvoices) {
          final invMap = Map<String, dynamic>.from(item);
          final serverInv = InvoiceModel.fromMap(invMap);

          final seq = serverInv.sequenceNumber;
          if (seq > maxServerSeq) maxServerSeq = seq;

          if (activeTombstones.contains('deleted_invoice_${serverInv.uuid}') ||
              serverInv.status == 'cancelled' ||
              invMap['active'] == false) {
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

          // Clean up any conflicting local row with same invoice_number but different uuid
          await db.delete(
            'invoices',
            where: 'invoice_number = ? AND uuid != ?',
            whereArgs: [serverInv.invoiceNumber, serverInv.uuid],
          );

          await db.insert(
            'invoices',
            serverInv.toMap(),
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }

        // Keep local sequence counter aligned with cloud maximum
        if (maxServerSeq > 0) {
          final currentNextRes = await db.query('app_settings', where: 'key = ?', whereArgs: ['next_usable_number']);
          final currentNext = currentNextRes.isNotEmpty ? (int.tryParse(currentNextRes.first['value'] as String) ?? 1) : 1;
          if (maxServerSeq + 1 > currentNext) {
            await db.insert(
              'app_settings',
              {'key': 'next_usable_number', 'value': (maxServerSeq + 1).toString()},
              conflictAlgorithm: ConflictAlgorithm.replace,
            );
          }
        }

        // 2c. Save cloud payments
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

        // 2d. Save products catalogue
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

        // 2e. Reconcile all customer balances from freshly synced invoices
        try {
          await custRepo.recalculateCustomerBalances();
        } catch (_) {}

        final serverTime = pullRes.data['timestamp'] as String?;
        if (serverTime != null) {
          _lastSyncTime = DateTime.tryParse(serverTime) ?? DateTime.now();
        } else {
          _lastSyncTime = DateTime.now();
        }
        await prefs.setString('last_sync_time', _lastSyncTime!.toIso8601String());
      }

      await checkPendingQueue();
      _status = SyncStatus.synced;
      _statusMessage = 'Up to date';
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('[SyncService] Sync error: $e');
      _status = SyncStatus.failed;
      _statusMessage = 'Sync failed. Will retry automatically.';
      notifyListeners();
      return false;
    } finally {
      _isSyncing = false;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopForegroundTimer();
    super.dispose();
  }
}
