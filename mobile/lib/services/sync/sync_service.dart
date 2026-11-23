import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import '../../data/database/app_database.dart';
import '../api/api_client.dart';
import '../../data/models/invoice_model.dart';
import '../../data/models/customer_model.dart';
import '../../data/models/payment_model.dart';
import '../../data/models/product_model.dart';
import '../../data/repositories/customer_repository.dart';
import '../../data/repositories/invoice_repository.dart';
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
  bool get isSyncing => _status == SyncStatus.syncing || _isSyncing;
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

    // Start periodic background sync for active sessions (every 3 minutes)
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
    // Periodic background sync every 3 minutes (180s) to avoid continuous spinning
    _foregroundTimer = Timer.periodic(const Duration(minutes: 3), (timer) {
      if (!_isSyncing) {
        synchronize(forceFullSync: true);
      }
    });
  }

  void _stopForegroundTimer() {
    _foregroundTimer?.cancel();
    _foregroundTimer = null;
  }

  Future<int> checkPendingQueue() async {
    try {
      final db = await AppDatabase.instance.database;
      // SYNC-02: Count pending invoices, payments, and offline deletion tombstones
      final invRes = await db.rawQuery('''
        SELECT COUNT(*) as count 
        FROM invoices 
        WHERE sync_status != 'synced' 
          AND (status IS NULL OR status != 'cancelled')
      ''');
      final payRes = await db.rawQuery('''
        SELECT COUNT(*) as count 
        FROM payments 
        WHERE sync_status != 'synced' OR sync_status IS NULL
      ''');
      final tombRes = await db.rawQuery('''
        SELECT COUNT(*) as count 
        FROM app_settings 
        WHERE key LIKE 'deleted_%'
      ''');

      final invCount = (invRes.first['count'] as int?) ?? 0;
      final payCount = (payRes.first['count'] as int?) ?? 0;
      final tombCount = (tombRes.first['count'] as int?) ?? 0;
      _pendingCount = invCount + payCount + tombCount;
      notifyListeners();
      return _pendingCount;
    } catch (e) {
      debugPrint('[SyncService] checkPendingQueue error: $e');
      return _pendingCount;
    }
  }

  void stopSync() {
    _stopForegroundTimer();
    _isSyncing = false;
    _status = SyncStatus.offline;
    _statusMessage = 'Offline';
    notifyListeners();
  }

  // Trigger synchronization across bills, customers, products, and payments
  Future<bool> synchronize({bool forceFullSync = false}) async {
    if (_isSyncing) return false;

    // S14: Do not attempt network sync if unauthenticated/logged out
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('access_token');
    if (token == null || token.isEmpty) {
      _status = SyncStatus.offline;
      _statusMessage = 'Offline';
      notifyListeners();
      return false;
    }

    _isSyncing = true;
    _status = SyncStatus.syncing;
    _statusMessage = _pendingCount > 0
        ? 'Syncing $_pendingCount bills with cloud...'
        : 'Syncing bills with cloud...';
    notifyListeners();

    try {
      bool ok = false;
      for (int attempt = 1; attempt <= 2; attempt++) {
        try {
          ok = await _executeSync(forceFullSync: forceFullSync);
          if (ok) break;
        } catch (attemptErr) {
          debugPrint('[SyncService] Sync attempt $attempt failed: $attemptErr');
          if (attempt < 2) {
            // Wait 2.5s for cold start wake-up
            await Future.delayed(const Duration(milliseconds: 2500));
          }
        }
      }

      await checkPendingQueue();
      if (ok) {
        _status = _pendingCount > 0 ? SyncStatus.offline : SyncStatus.synced;
        _statusMessage = _pendingCount > 0
            ? '$_pendingCount bills waiting for internet'
            : 'Up to date';
      } else {
        _status = SyncStatus.offline;
        _statusMessage = _pendingCount > 0
            ? '$_pendingCount bills waiting for internet'
            : 'Offline mode';
      }
      notifyListeners();
      return ok;
    } catch (e) {
      debugPrint('[SyncService] Sync error: $e');
      await checkPendingQueue();
      _status = SyncStatus.offline;
      _statusMessage = _pendingCount > 0
          ? '$_pendingCount bills waiting for internet'
          : 'Offline mode';
      notifyListeners();
      return false;
    } finally {
      _isSyncing = false;
      await checkPendingQueue();
      if (_status == SyncStatus.syncing) {
        _status = _pendingCount > 0 ? SyncStatus.offline : SyncStatus.synced;
        notifyListeners();
      }
    }
  }

  Future<bool> _executeSync({bool forceFullSync = false}) async {
    try {
      if (!_isSyncing) return false;
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
        final map = inv.toApiMap();
        map['deviceId'] = deviceId;
        if ((map['createdBy'] ?? '').toString().isEmpty) {
          map['createdBy'] = 'Administrator';
        }
        return map;
      }).toList();

      // Collect local customers to sync (include active customers so standalone creations/edits are synced)
      final List<Map<String, dynamic>> localCustomers = await db.query(
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

      // Collect products (push active catalogue products so offline additions/edits are synced)
      final List<Map<String, dynamic>> localProducts = await db.query(
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

      // Collect payments (only un-synced payments unless forceFullSync)
      final localPayments = forceFullSync
          ? await db.query('payments')
          : await db.query('payments', where: "sync_status != 'synced' OR sync_status IS NULL");
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
      // If 403 Forbidden (not allowed for role) or 404 (already deleted), delete tombstone to avoid infinite sync loops (S11)
      final allSettings = await db.query('app_settings');
      for (final s in allSettings) {
        final key = s['key'] as String;
        if (key.startsWith('deleted_invoice_')) {
          final uuid = key.replaceFirst('deleted_invoice_', '');
          try {
            await ApiClient.instance.deleteInvoice(uuid);
            await db.delete('app_settings', where: 'key = ?', whereArgs: [key]);
          } on DioException catch (dioErr) {
            if (dioErr.response?.statusCode == 403 || dioErr.response?.statusCode == 404) {
              await db.delete('app_settings', where: 'key = ?', whereArgs: [key]);
            }
          } catch (_) {}
        } else if (key.startsWith('deleted_customer_')) {
          final uuid = key.replaceFirst('deleted_customer_', '');
          try {
            await ApiClient.instance.deleteCustomer(uuid);
            await db.delete('app_settings', where: 'key = ?', whereArgs: [key]);
          } on DioException catch (dioErr) {
            if (dioErr.response?.statusCode == 403 || dioErr.response?.statusCode == 404) {
              await db.delete('app_settings', where: 'key = ?', whereArgs: [key]);
            }
          } catch (_) {}
        } else if (key.startsWith('deleted_product_')) {
          final uuid = key.replaceFirst('deleted_product_', '');
          try {
            await ApiClient.instance.deleteProduct(uuid);
            await db.delete('app_settings', where: 'key = ?', whereArgs: [key]);
          } on DioException catch (dioErr) {
            if (dioErr.response?.statusCode == 403 || dioErr.response?.statusCode == 404) {
              await db.delete('app_settings', where: 'key = ?', whereArgs: [key]);
            }
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

        if (pushRes.statusCode == 200 && pushRes.data != null) {
          final resData = pushRes.data as Map<String, dynamic>? ?? {};
          final results = resData['results'] as Map<String, dynamic>? ?? {};
          final syncedList = (results['syncedInvoiceUuids'] as List?)
                  ?.map((e) => e.toString())
                  .toSet() ??
              <String>{};
          final syncedPaymentsList = (results['syncedPaymentUuids'] as List?)
                  ?.map((e) => e.toString())
                  .toSet() ??
              <String>{};

          for (final row in pendingInvoicesData) {
            final uuid = row['uuid'] as String;
            if (syncedList.contains(uuid)) {
              await db.update(
                'invoices',
                {'sync_status': 'synced'},
                where: 'uuid = ?',
                whereArgs: [uuid],
              );
            }
          }

          // SYNC-01: Only mark payments as synced if explicitly confirmed by server response
          for (final pay in paymentsToPush) {
            final payUuid = pay['uuid'] as String?;
            if (payUuid != null && payUuid.isNotEmpty && syncedPaymentsList.contains(payUuid)) {
              await db.update('payments', {'sync_status': 'synced'}, where: 'uuid = ?', whereArgs: [payUuid]);
            }
          }
        }
      }

      if (!_isSyncing) return false;
      // Step 2: Request delta sync or full sync
      String? lastSyncTimestamp;
      if (!forceFullSync) {
        final lastSyncSetting = await db.query('app_settings', where: 'key = ?', whereArgs: ['last_sync_timestamp']);
        if (lastSyncSetting.isNotEmpty) {
          lastSyncTimestamp = lastSyncSetting.first['value'] as String?;
        }
      }
      final pullRes = await ApiClient.instance.pullSync(lastSyncTimestamp);
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
            await custRepo.saveCustomer(serverCust, preserveInactive: true, preserveBalancesIfZero: true);
          }
        }

        // 2b. Save cloud invoices
        final serverInvoices = data['invoices'] as List? ?? [];
        int maxServerGstSeq = 0;
        int maxServerTempSeq = 0;
        final currentFy = InvoiceRepository.getFinancialYear(DateTime.now());

        for (final item in serverInvoices) {
          final invMap = Map<String, dynamic>.from(item);
          final serverInv = InvoiceModel.fromMap(invMap);

          final invFy = serverInv.financialYear.isNotEmpty
              ? serverInv.financialYear
              : InvoiceRepository.getFinancialYear(serverInv.invoiceDate);

          // Only track sequence max for the current financial year to avoid past FY corruption (S5)
          if (invFy == currentFy) {
            final seq = serverInv.sequenceNumber;
            if (serverInv.invoiceType == 'temporary') {
              if (seq > maxServerTempSeq) maxServerTempSeq = seq;
            } else {
              if (seq > maxServerGstSeq) maxServerGstSeq = seq;
            }
          }

          if (activeTombstones.contains('deleted_invoice_${serverInv.uuid}')) {
            await db.delete('invoices', where: 'uuid = ?', whereArgs: [serverInv.uuid]);
            await db.delete('payments', where: 'invoice_id = ?', whereArgs: [serverInv.uuid]);
            continue;
          }

          // DATA-17: Cancelled tax invoices must be retained in SQLite for GST audit compliance, not hard-deleted
          if (serverInv.status == 'cancelled' || invMap['active'] == false) {
            await db.update(
              'invoices',
              {'status': 'cancelled', 'sync_status': 'synced'},
              where: 'uuid = ?',
              whereArgs: [serverInv.uuid],
            );
            continue;
          }

          final localExisting = await db.query(
            'invoices',
            where: 'uuid = ?',
            whereArgs: [serverInv.uuid],
            limit: 1,
          );
          if (localExisting.isNotEmpty) {
            final localSyncStatus = localExisting.first['sync_status'] as String?;
            if (localSyncStatus == 'waiting_for_internet' || localSyncStatus == 'pending') {
              // Local offline edits are pending sync — do not overwrite
              continue;
            }
            // Already present in local DB! Ensure copy is updated and marked synced
            await db.update(
              'invoices',
              serverInv.copyWith(syncStatus: 'synced').toMap(),
              where: 'uuid = ?',
              whereArgs: [serverInv.uuid],
            );
          } else {
            await db.insert(
              'invoices',
              serverInv.copyWith(syncStatus: 'synced').toMap(),
              conflictAlgorithm: ConflictAlgorithm.replace,
            );
          }
        }

        // Keep local sequence counters aligned with cloud maximum
        if (maxServerGstSeq > 0) {
          final fy = InvoiceRepository.getFinancialYear(DateTime.now());
          final currentNextRes = await db.query('app_settings', where: 'key = ?', whereArgs: ['next_usable_number_$fy']);
          final currentNext = currentNextRes.isNotEmpty ? (int.tryParse(currentNextRes.first['value'] as String) ?? 1) : 1;
          if (maxServerGstSeq + 1 > currentNext) {
            await db.insert(
              'app_settings',
              {'key': 'next_usable_number_$fy', 'value': (maxServerGstSeq + 1).toString()},
              conflictAlgorithm: ConflictAlgorithm.replace,
            );
            await db.insert(
              'app_settings',
              {'key': 'next_usable_number', 'value': (maxServerGstSeq + 1).toString()},
              conflictAlgorithm: ConflictAlgorithm.replace,
            );
          }
        }

        if (maxServerTempSeq > 0) {
          final currentTempRes = await db.query('app_settings', where: 'key = ?', whereArgs: ['next_temporary_number']);
          final currentTemp = currentTempRes.isNotEmpty ? (int.tryParse(currentTempRes.first['value'] as String) ?? 1) : 1;
          if (maxServerTempSeq + 1 > currentTemp) {
            await db.insert(
              'app_settings',
              {'key': 'next_temporary_number', 'value': (maxServerTempSeq + 1).toString()},
              conflictAlgorithm: ConflictAlgorithm.replace,
            );
          }
        }

        // 2c. Save cloud payments
        final serverPayments = data['payments'] as List? ?? [];
        for (final item in serverPayments) {
          final payMap = Map<String, dynamic>.from(item);
          payMap['sync_status'] = 'synced';
          final serverPay = PaymentModel.fromMap(payMap);
          if (serverPay.uuid.isNotEmpty && !activeTombstones.contains('deleted_invoice_${serverPay.invoiceId}')) {
            await db.insert(
              'payments',
              serverPay.toMap(),
              conflictAlgorithm: ConflictAlgorithm.replace,
            );

            // SYNC-05: Update invoice total_paid and balance_due in SQLite when new cloud payment arrives
            if (serverPay.invoiceId.isNotEmpty) {
              final allInvPayments = await db.query(
                'payments',
                columns: ['amount'],
                where: 'invoice_id = ?',
                whereArgs: [serverPay.invoiceId],
              );
              final totalPaidSum = allInvPayments.fold(0.0, (acc, p) => acc + ((p['amount'] as num?)?.toDouble() ?? 0.0));
              final invRows = await db.query(
                'invoices',
                columns: ['grand_total'],
                where: 'uuid = ?',
                whereArgs: [serverPay.invoiceId],
                limit: 1,
              );
              if (invRows.isNotEmpty) {
                final gt = (invRows.first['grand_total'] as num?)?.toDouble() ?? 0.0;
                final newBal = (gt - totalPaidSum).clamp(0.0, double.infinity);
                final newStatus = newBal <= 0.005 ? 'paid' : (totalPaidSum > 0 ? 'partially_paid' : 'unpaid');
                await db.update(
                  'invoices',
                  {
                    'total_paid': totalPaidSum,
                    'balance_due': newBal,
                    'payment_status': newStatus,
                  },
                  where: 'uuid = ?',
                  whereArgs: [serverPay.invoiceId],
                );
              }
            }
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

        // SYNC-03: If server response hit 1,000 item limit, do not advance timestamp so remainder can be pulled
        final isTruncated = serverCustomers.length >= 1000 ||
            serverInvoices.length >= 1000 ||
            serverPayments.length >= 1000 ||
            serverProducts.length >= 1000;

        final serverTime = pullRes.data['timestamp'] as String?;
        if (serverTime != null) {
          _lastSyncTime = DateTime.tryParse(serverTime) ?? DateTime.now();
        } else {
          _lastSyncTime = DateTime.now();
        }
        await prefs.setString('last_sync_time', _lastSyncTime!.toIso8601String());
        if (!isTruncated) {
          await db.insert(
            'app_settings',
            {'key': 'last_sync_timestamp', 'value': serverTime ?? _lastSyncTime!.toIso8601String()},
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
      }
      return true;
    } catch (e) {
      debugPrint('[_executeSync] error: $e');
      rethrow;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopForegroundTimer();
    super.dispose();
  }
}
