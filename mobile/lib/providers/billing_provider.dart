import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../data/database/app_database.dart';
import '../data/models/customer_model.dart';
import '../data/models/invoice_item_model.dart';
import '../data/models/invoice_model.dart';
import '../data/repositories/invoice_repository.dart';
import '../data/repositories/customer_repository.dart';
import '../data/repositories/product_repository.dart';
import '../core/utils/number_to_words.dart';
import '../core/constants/app_constants.dart';
import '../services/api/api_client.dart';
import '../services/sync/sync_service.dart';

class BillingState {
  final CustomerModel customer;
  final String invoiceNumber;
  final DateTime invoiceDate;
  final DateTime? dueDate;
  final String poNumber;
  final DateTime? poDate;
  final String challanNumber;
  final DateTime? challanDate;
  final List<InvoiceItemModel> items;
  final bool isSaving;
  final String? errorMessage;
  final InvoiceModel? lastSavedInvoice;
  final String? editingInvoiceUuid;
  final InvoiceModel? originalInvoice;

  BillingState({
    required this.customer,
    this.invoiceNumber = '',
    required this.invoiceDate,
    this.dueDate,
    this.poNumber = '',
    this.poDate,
    this.challanNumber = '',
    this.challanDate,
    this.items = const [],
    this.isSaving = false,
    this.errorMessage,
    this.lastSavedInvoice,
    this.editingInvoiceUuid,
    this.originalInvoice,
  });

  bool get isEditMode => editingInvoiceUuid != null;

  bool get isInterState => customer.stateCode.trim() != AppConstants.stateCode;

  double get netAmount {
    return items.fold(0.0, (sum, itm) => sum + itm.taxableValue);
  }

  double get cgstTotal {
    if (isInterState) return 0.0;
    return items.fold(0.0, (sum, itm) => sum + itm.cgstAmount);
  }

  double get sgstTotal {
    if (isInterState) return 0.0;
    return items.fold(0.0, (sum, itm) => sum + itm.sgstAmount);
  }

  double get igstTotal {
    if (!isInterState) return 0.0;
    return items.fold(0.0, (sum, itm) => sum + itm.igstAmount);
  }

  double get unroundedTotal => netAmount + cgstTotal + sgstTotal + igstTotal;

  double get grandTotal => unroundedTotal.roundToDouble();

  double get roundOff => ((grandTotal - unroundedTotal) * 100).round() / 100;

  String get amountInWords => NumberToWords.convert(grandTotal);

  BillingState copyWith({
    CustomerModel? customer,
    String? invoiceNumber,
    DateTime? invoiceDate,
    DateTime? dueDate,
    String? poNumber,
    DateTime? poDate,
    String? challanNumber,
    DateTime? challanDate,
    List<InvoiceItemModel>? items,
    bool? isSaving,
    String? errorMessage,
    InvoiceModel? lastSavedInvoice,
    String? editingInvoiceUuid,
    InvoiceModel? originalInvoice,
  }) {
    return BillingState(
      customer: customer ?? this.customer,
      invoiceNumber: invoiceNumber ?? this.invoiceNumber,
      invoiceDate: invoiceDate ?? this.invoiceDate,
      dueDate: dueDate ?? this.dueDate,
      poNumber: poNumber ?? this.poNumber,
      poDate: poDate ?? this.poDate,
      challanNumber: challanNumber ?? this.challanNumber,
      challanDate: challanDate ?? this.challanDate,
      items: items ?? this.items,
      isSaving: isSaving ?? this.isSaving,
      errorMessage: errorMessage,
      lastSavedInvoice: lastSavedInvoice ?? this.lastSavedInvoice,
      editingInvoiceUuid: editingInvoiceUuid ?? this.editingInvoiceUuid,
      originalInvoice: originalInvoice ?? this.originalInvoice,
    );
  }
}

class BillingNotifier extends StateNotifier<BillingState> {
  final InvoiceRepository _invoiceRepo = InvoiceRepository();
  final CustomerRepository _customerRepo = CustomerRepository();

  BillingNotifier()
      : super(
          BillingState(
            customer: CustomerModel(
              uuid: const Uuid().v4(),
              name: '',
              phone: '',
              state: AppConstants.state,
              stateCode: AppConstants.stateCode,
            ),
            invoiceDate: DateTime.now(),
          ),
        ) {
    loadNextInvoiceNumber();
  }

  Future<void> loadNextInvoiceNumber() async {
    try {
      final nextNum = await _invoiceRepo.getNextInvoiceNumberPreview(state.invoiceDate);
      state = state.copyWith(invoiceNumber: nextNum);
    } catch (_) {}
  }

  void setCustomInvoiceNumber(String num) {
    state = state.copyWith(invoiceNumber: num.trim());
  }

  void setCustomer(CustomerModel customer) {
    state = state.copyWith(customer: customer);
    _recalculateTaxes();
  }

  void updateCustomerDetails({
    String? name,
    String? phone,
    String? gstin,
    String? address,
    String? stateName,
    String? stateCode,
  }) {
    state = state.copyWith(
      customer: state.customer.copyWith(
        name: name,
        phone: phone,
        gstin: gstin,
        address: address,
        state: stateName,
        stateCode: stateCode,
      ),
    );
    _recalculateTaxes();
  }

  void setInvoiceDate(DateTime date) {
    state = state.copyWith(invoiceDate: date);
  }

  void setPoDetails(String poNumber, DateTime? poDate) {
    state = state.copyWith(poNumber: poNumber, poDate: poDate);
  }

  void setChallanDetails(String challanNumber, DateTime? challanDate) {
    state = state.copyWith(challanNumber: challanNumber, challanDate: challanDate);
  }

  void addItem({
    required String description,
    required String hsnCode,
    required double quantity,
    required String unit,
    required double rate,
    double discount = 0.0,
    double gstRate = 18.0,
  }) {
    final taxableValue = ((quantity * rate - discount) * 100).round() / 100;
    final isInter = state.isInterState;

    double cgstRate = 0.0, cgstAmount = 0.0;
    double sgstRate = 0.0, sgstAmount = 0.0;
    double igstRate = 0.0, igstAmount = 0.0;

    if (isInter) {
      igstRate = gstRate;
      igstAmount = ((taxableValue * (igstRate / 100)) * 100).round() / 100;
    } else {
      cgstRate = gstRate / 2;
      sgstRate = gstRate / 2;
      cgstAmount = ((taxableValue * (cgstRate / 100)) * 100).round() / 100;
      sgstAmount = ((taxableValue * (sgstRate / 100)) * 100).round() / 100;
    }

    final total = ((taxableValue + cgstAmount + sgstAmount + igstAmount) * 100).round() / 100;

    final newItem = InvoiceItemModel(
      sno: state.items.length + 1,
      description: description,
      hsnCode: hsnCode,
      quantity: quantity,
      unit: unit,
      rate: rate,
      discount: discount,
      taxableValue: taxableValue,
      gstRate: gstRate,
      cgstRate: cgstRate,
      cgstAmount: cgstAmount,
      sgstRate: sgstRate,
      sgstAmount: sgstAmount,
      igstRate: igstRate,
      igstAmount: igstAmount,
      totalAmount: total,
    );

    state = state.copyWith(items: [...state.items, newItem]);
  }

  void removeItem(int index) {
    final updated = List<InvoiceItemModel>.from(state.items);
    updated.removeAt(index);
    // Renumber
    for (var i = 0; i < updated.length; i++) {
      final old = updated[i];
      updated[i] = InvoiceItemModel(
        sno: i + 1,
        description: old.description,
        hsnCode: old.hsnCode,
        quantity: old.quantity,
        unit: old.unit,
        rate: old.rate,
        discount: old.discount,
        taxableValue: old.taxableValue,
        gstRate: old.gstRate,
        cgstRate: old.cgstRate,
        cgstAmount: old.cgstAmount,
        sgstRate: old.sgstRate,
        sgstAmount: old.sgstAmount,
        igstRate: old.igstRate,
        igstAmount: old.igstAmount,
        totalAmount: old.totalAmount,
      );
    }
    state = state.copyWith(items: updated);
  }

  void _recalculateTaxes() {
    final isInter = state.isInterState;
    final updated = state.items.map((old) {
      final taxable = old.taxableValue;
      double cgstRate = 0.0, cgstAmount = 0.0;
      double sgstRate = 0.0, sgstAmount = 0.0;
      double igstRate = 0.0, igstAmount = 0.0;

      if (isInter) {
        igstRate = old.gstRate;
        igstAmount = ((taxable * (igstRate / 100)) * 100).round() / 100;
      } else {
        cgstRate = old.gstRate / 2;
        sgstRate = old.gstRate / 2;
        cgstAmount = ((taxable * (cgstRate / 100)) * 100).round() / 100;
        sgstAmount = ((taxable * (sgstRate / 100)) * 100).round() / 100;
      }

      final total = ((taxable + cgstAmount + sgstAmount + igstAmount) * 100).round() / 100;

      return InvoiceItemModel(
        sno: old.sno,
        description: old.description,
        hsnCode: old.hsnCode,
        quantity: old.quantity,
        unit: old.unit,
        rate: old.rate,
        discount: old.discount,
        taxableValue: taxable,
        gstRate: old.gstRate,
        cgstRate: cgstRate,
        cgstAmount: cgstAmount,
        sgstRate: sgstRate,
        sgstAmount: sgstAmount,
        igstRate: igstRate,
        igstAmount: igstAmount,
        totalAmount: total,
      );
    }).toList();

    state = state.copyWith(items: updated);
  }

  Future<InvoiceModel?> saveAndIssueInvoice() async {
    if (state.customer.name.trim().isEmpty) {
      state = state.copyWith(errorMessage: 'Please enter customer name');
      return null;
    }
    if (state.items.isEmpty) {
      state = state.copyWith(errorMessage: 'Please add at least one item');
      return null;
    }

    state = state.copyWith(isSaving: true, errorMessage: null);

    try {
      // 1. Allocate next simple sequential invoice number
      final alloc = await _invoiceRepo.allocateNextLocalInvoiceNumber(
        state.invoiceDate,
        customInvoiceNumber: state.invoiceNumber,
      );
      final invoiceNumber = alloc['invoiceNumber'] as String;
      final seqNum = alloc['sequenceNumber'] as int;
      final fy = alloc['financialYear'] as String;

      final invoiceUuid = const Uuid().v4();

      // 2. Save / update customer
      final customerToSave = state.customer.copyWith(
        uuid: state.customer.uuid.isNotEmpty ? state.customer.uuid : const Uuid().v4(),
        totalBilled: state.customer.totalBilled + state.grandTotal,
        outstandingBalance: state.customer.outstandingBalance + state.grandTotal,
      );
      await _customerRepo.saveCustomer(customerToSave);

      // 3. Assemble InvoiceModel
      final prefs = await SharedPreferences.getInstance();
      final loggedInName = prefs.getString('user_name') ?? 'Admin';

      final invoice = InvoiceModel(
        uuid: invoiceUuid,
        invoiceNumber: invoiceNumber,
        sequenceNumber: seqNum,
        financialYear: fy,
        invoiceDate: state.invoiceDate,
        dueDate: state.dueDate,
        poNumber: state.poNumber,
        poDate: state.poDate,
        challanNumber: state.challanNumber,
        challanDate: state.challanDate,
        customer: customerToSave,
        isInterState: state.isInterState,
        items: state.items,
        netAmount: state.netAmount,
        cgstTotal: state.cgstTotal,
        sgstTotal: state.sgstTotal,
        igstTotal: state.igstTotal,
        roundOff: state.roundOff,
        grandTotal: state.grandTotal,
        amountInWords: state.amountInWords,
        status: 'finalized',
        paymentStatus: 'unpaid',
        totalPaid: 0.0,
        balanceDue: state.grandTotal,
        createdBy: loggedInName,
        syncStatus: 'waiting_for_internet',
      );

      // 4. Save to local SQLite
      await _invoiceRepo.saveInvoice(invoice);

      // 5. Automatically save all products and HSN codes to catalogue for future bills
      final prodRepo = ProductRepository();
      for (final itm in state.items) {
        if (itm.description.trim().isNotEmpty) {
          await prodRepo.saveOrUpdateProduct(
            description: itm.description,
            hsnCode: itm.hsnCode,
            unit: itm.unit,
            defaultRate: itm.rate,
            gstRate: itm.gstRate,
          );
        }
      }

      // 6. Trigger background sync attempt
      SyncService.instance.synchronize();

      state = state.copyWith(
        isSaving: false,
        lastSavedInvoice: invoice,
      );

      return invoice;
    } catch (e) {
      state = state.copyWith(isSaving: false, errorMessage: 'Failed to save bill: $e');
      return null;
    }
  }

  void initForEdit(InvoiceModel invoice) {
    state = BillingState(
      customer: invoice.customer,
      invoiceNumber: invoice.invoiceNumber,
      invoiceDate: invoice.invoiceDate,
      dueDate: invoice.dueDate,
      poNumber: invoice.poNumber,
      poDate: invoice.poDate,
      challanNumber: invoice.challanNumber,
      challanDate: invoice.challanDate,
      items: invoice.items,
      editingInvoiceUuid: invoice.uuid,
      originalInvoice: invoice,
    );
  }

  Future<InvoiceModel?> updateExistingInvoice() async {
    if (state.originalInvoice == null || state.editingInvoiceUuid == null) {
      return null;
    }
    if (state.customer.name.trim().isEmpty) {
      state = state.copyWith(errorMessage: 'Please enter customer name');
      return null;
    }
    if (state.items.isEmpty) {
      state = state.copyWith(errorMessage: 'Please add at least one item');
      return null;
    }

    state = state.copyWith(isSaving: true, errorMessage: null);

    try {
      final orig = state.originalInvoice!;
      final deltaGrandTotal = state.grandTotal - orig.grandTotal;
      final newBalanceDue = (state.grandTotal - orig.totalPaid).clamp(0.0, double.infinity);
      final deltaBalanceDue = newBalanceDue - orig.balanceDue;

      final newPaymentStatus = newBalanceDue == 0.0
          ? 'paid'
          : (orig.totalPaid > 0.0 ? 'partially_paid' : 'unpaid');

      final updatedInvoice = orig.copyWith(
        customer: state.customer,
        invoiceDate: state.invoiceDate,
        dueDate: state.dueDate,
        poNumber: state.poNumber,
        poDate: state.poDate,
        challanNumber: state.challanNumber,
        challanDate: state.challanDate,
        isInterState: state.isInterState,
        items: state.items,
        netAmount: state.netAmount,
        cgstTotal: state.cgstTotal,
        sgstTotal: state.sgstTotal,
        igstTotal: state.igstTotal,
        roundOff: state.roundOff,
        grandTotal: state.grandTotal,
        amountInWords: state.amountInWords,
        paymentStatus: newPaymentStatus,
        balanceDue: newBalanceDue,
        syncStatus: 'waiting_for_internet',
      );

      // 1. Update SQLite
      await _invoiceRepo.updateInvoice(
        updatedInvoice,
        deltaGrandTotal: deltaGrandTotal,
        deltaBalanceDue: deltaBalanceDue,
      );

      // 2. Also save/update customer in SQLite
      await _customerRepo.saveCustomer(state.customer);

      // 3. Save products
      final prodRepo = ProductRepository();
      for (final itm in state.items) {
        if (itm.description.trim().isNotEmpty) {
          await prodRepo.saveOrUpdateProduct(
            description: itm.description,
            hsnCode: itm.hsnCode,
            unit: itm.unit,
            defaultRate: itm.rate,
            gstRate: itm.gstRate,
          );
        }
      }

      // 4. Try online sync or background sync
      try {
        final prefs = await SharedPreferences.getInstance();
        final deviceId = prefs.getString('device_id') ?? 'android_mobile_1';
        final body = {
          'customer': state.customer.toMap(),
          'items': state.items.map((e) => e.toApiMap()).toList(),
          'invoiceDate': state.invoiceDate.toIso8601String(),
          'dueDate': state.dueDate?.toIso8601String(),
          'poNumber': state.poNumber,
          'poDate': state.poDate?.toIso8601String(),
          'challanNumber': state.challanNumber,
          'challanDate': state.challanDate?.toIso8601String(),
          'deviceId': deviceId,
        };
        final res = await ApiClient.instance.updateInvoice(updatedInvoice.uuid, body);
        if (res.statusCode == 200) {
          final db = await AppDatabase.instance.database;
          await db.update(
            'invoices',
            {'sync_status': 'synced'},
            where: 'uuid = ?',
            whereArgs: [updatedInvoice.uuid],
          );
        }
      } catch (_) {
        // Will sync on next sync pass
      }

      SyncService.instance.synchronize();

      state = state.copyWith(
        isSaving: false,
        lastSavedInvoice: updatedInvoice,
      );
      return updatedInvoice;
    } catch (e) {
      state = state.copyWith(isSaving: false, errorMessage: 'Failed to update bill: $e');
      return null;
    }
  }

  void resetForm() {
    state = BillingState(
      customer: CustomerModel(
        uuid: const Uuid().v4(),
        name: '',
        phone: '',
        state: AppConstants.state,
        stateCode: AppConstants.stateCode,
      ),
      invoiceDate: DateTime.now(),
    );
    loadNextInvoiceNumber();
  }
}

final billingProvider = StateNotifierProvider<BillingNotifier, BillingState>((ref) {
  return BillingNotifier();
});
