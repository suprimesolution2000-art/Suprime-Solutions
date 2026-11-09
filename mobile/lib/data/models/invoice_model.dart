import 'dart:convert';
import 'customer_model.dart';
import 'invoice_item_model.dart';

class InvoiceModel {
  final String uuid;
  final String invoiceNumber;
  final int sequenceNumber;
  final String financialYear;
  final DateTime invoiceDate;
  final DateTime? dueDate;
  final String poNumber;
  final DateTime? poDate;
  final String challanNumber;
  final DateTime? challanDate;
  final CustomerModel customer;
  final bool isInterState;
  final List<InvoiceItemModel> items;
  final double netAmount;
  final double cgstTotal;
  final double sgstTotal;
  final double igstTotal;
  final double roundOff;
  final double grandTotal;
  final String amountInWords;
  final String status; // 'draft', 'finalized', 'cancelled'
  final String paymentStatus; // 'unpaid', 'partially_paid', 'paid', 'overdue'
  final double totalPaid;
  final double balanceDue;
  final String deviceId;
  final String createdBy;
  final String syncStatus; // 'synced', 'waiting_for_internet', 'syncing', 'failed'
  final String invoiceType; // 'gst', 'temporary'

  InvoiceModel({
    required this.uuid,
    required this.invoiceNumber,
    required this.sequenceNumber,
    required this.financialYear,
    required this.invoiceDate,
    this.dueDate,
    this.poNumber = '',
    this.poDate,
    this.challanNumber = '',
    this.challanDate,
    required this.customer,
    this.isInterState = false,
    required this.items,
    required this.netAmount,
    this.cgstTotal = 0.0,
    this.sgstTotal = 0.0,
    this.igstTotal = 0.0,
    this.roundOff = 0.0,
    required this.grandTotal,
    required this.amountInWords,
    this.status = 'finalized',
    this.paymentStatus = 'unpaid',
    this.totalPaid = 0.0,
    required this.balanceDue,
    this.deviceId = '',
    this.createdBy = 'Admin',
    this.syncStatus = 'synced',
    this.invoiceType = 'gst',
  });

  Map<String, dynamic> toMap() {
    return {
      'uuid': uuid,
      'invoice_number': invoiceNumber,
      'sequence_number': sequenceNumber,
      'financial_year': financialYear,
      'invoice_date': invoiceDate.toIso8601String(),
      'due_date': dueDate?.toIso8601String(),
      'po_number': poNumber,
      'po_date': poDate?.toIso8601String(),
      'challan_number': challanNumber,
      'challan_date': challanDate?.toIso8601String(),
      'customer_json': jsonEncode(customer.toMap()),
      'is_inter_state': isInterState ? 1 : 0,
      'items_json': jsonEncode(items.map((e) => e.toMap()).toList()),
      'net_amount': netAmount,
      'cgst_total': cgstTotal,
      'sgst_total': sgstTotal,
      'igst_total': igstTotal,
      'round_off': roundOff,
      'grand_total': grandTotal,
      'amount_in_words': amountInWords,
      'status': status,
      'payment_status': paymentStatus,
      'total_paid': totalPaid,
      'balance_due': balanceDue,
      'device_id': deviceId,
      'created_by': createdBy,
      'sync_status': syncStatus,
      'invoice_type': invoiceType,
    };
  }

  factory InvoiceModel.fromMap(Map<String, dynamic> map) {
    CustomerModel customerObj;
    if (map['customer_json'] != null) {
      customerObj = CustomerModel.fromMap(jsonDecode(map['customer_json']));
    } else if (map['customer'] != null && map['customer'] is Map) {
      customerObj = CustomerModel.fromMap(Map<String, dynamic>.from(map['customer']));
    } else {
      customerObj = CustomerModel(uuid: '', name: 'Customer', phone: '');
    }

    List<InvoiceItemModel> itemsList = [];
    if (map['items_json'] != null) {
      final List decoded = jsonDecode(map['items_json']);
      itemsList = decoded.map((e) => InvoiceItemModel.fromMap(Map<String, dynamic>.from(e))).toList();
    } else if (map['items'] != null && map['items'] is List) {
      itemsList = (map['items'] as List).map((e) => InvoiceItemModel.fromMap(Map<String, dynamic>.from(e))).toList();
    }

    return InvoiceModel(
      uuid: map['uuid'] ?? '',
      invoiceNumber: map['invoice_number'] ?? map['invoiceNumber'] ?? '',
      sequenceNumber: ((map['sequence_number'] ?? map['sequenceNumber']) as num?)?.toInt() ?? 1,
      financialYear: map['financial_year'] ?? map['financialYear'] ?? '',
      invoiceDate: DateTime.tryParse(map['invoice_date'] ?? map['invoiceDate'] ?? '') ?? DateTime.now(),
      dueDate: map['due_date'] != null || map['dueDate'] != null ? DateTime.tryParse(map['due_date'] ?? map['dueDate']) : null,
      poNumber: map['po_number'] ?? map['poNumber'] ?? '',
      poDate: map['po_date'] != null || map['poDate'] != null ? DateTime.tryParse(map['po_date'] ?? map['poDate']) : null,
      challanNumber: map['challan_number'] ?? map['challanNumber'] ?? '',
      challanDate: map['challan_date'] != null || map['challanDate'] != null ? DateTime.tryParse(map['challan_date'] ?? map['challanDate']) : null,
      customer: customerObj,
      isInterState: map['is_inter_state'] == 1 || map['isInterState'] == true,
      items: itemsList,
      netAmount: ((map['net_amount'] ?? map['netAmount']) as num?)?.toDouble() ?? 0.0,
      cgstTotal: ((map['cgst_total'] ?? map['cgstTotal']) as num?)?.toDouble() ?? 0.0,
      sgstTotal: ((map['sgst_total'] ?? map['sgstTotal']) as num?)?.toDouble() ?? 0.0,
      igstTotal: ((map['igst_total'] ?? map['igstTotal']) as num?)?.toDouble() ?? 0.0,
      roundOff: ((map['round_off'] ?? map['roundOff']) as num?)?.toDouble() ?? 0.0,
      grandTotal: ((map['grand_total'] ?? map['grandTotal']) as num?)?.toDouble() ?? 0.0,
      amountInWords: map['amount_in_words'] ?? map['amountInWords'] ?? '',
      status: map['status'] ?? 'finalized',
      paymentStatus: map['payment_status'] ?? map['paymentStatus'] ?? 'unpaid',
      totalPaid: ((map['total_paid'] ?? map['totalPaid']) as num?)?.toDouble() ?? 0.0,
      balanceDue: ((map['balance_due'] ?? map['balanceDue']) as num?)?.toDouble() ?? 0.0,
      deviceId: map['device_id'] ?? map['deviceId'] ?? '',
      createdBy: map['created_by'] ?? map['createdBy'] ?? 'Admin',
      syncStatus: map['sync_status'] ?? map['syncStatus'] ?? 'synced',
      invoiceType: map['invoice_type'] ?? map['invoiceType'] ?? 'gst',
    );
  }

  InvoiceModel copyWith({
    String? uuid,
    String? invoiceNumber,
    int? sequenceNumber,
    String? financialYear,
    DateTime? invoiceDate,
    DateTime? dueDate,
    String? poNumber,
    DateTime? poDate,
    String? challanNumber,
    DateTime? challanDate,
    CustomerModel? customer,
    bool? isInterState,
    List<InvoiceItemModel>? items,
    double? netAmount,
    double? cgstTotal,
    double? sgstTotal,
    double? igstTotal,
    double? roundOff,
    double? grandTotal,
    String? amountInWords,
    String? status,
    String? paymentStatus,
    double? totalPaid,
    double? balanceDue,
    String? deviceId,
    String? createdBy,
    String? syncStatus,
    String? invoiceType,
  }) {
    return InvoiceModel(
      uuid: uuid ?? this.uuid,
      invoiceNumber: invoiceNumber ?? this.invoiceNumber,
      sequenceNumber: sequenceNumber ?? this.sequenceNumber,
      financialYear: financialYear ?? this.financialYear,
      invoiceDate: invoiceDate ?? this.invoiceDate,
      dueDate: dueDate ?? this.dueDate,
      poNumber: poNumber ?? this.poNumber,
      poDate: poDate ?? this.poDate,
      challanNumber: challanNumber ?? this.challanNumber,
      challanDate: challanDate ?? this.challanDate,
      customer: customer ?? this.customer,
      isInterState: isInterState ?? this.isInterState,
      items: items ?? this.items,
      netAmount: netAmount ?? this.netAmount,
      cgstTotal: cgstTotal ?? this.cgstTotal,
      sgstTotal: sgstTotal ?? this.sgstTotal,
      igstTotal: igstTotal ?? this.igstTotal,
      roundOff: roundOff ?? this.roundOff,
      grandTotal: grandTotal ?? this.grandTotal,
      amountInWords: amountInWords ?? this.amountInWords,
      status: status ?? this.status,
      paymentStatus: paymentStatus ?? this.paymentStatus,
      totalPaid: totalPaid ?? this.totalPaid,
      balanceDue: balanceDue ?? this.balanceDue,
      deviceId: deviceId ?? this.deviceId,
      createdBy: createdBy ?? this.createdBy,
      syncStatus: syncStatus ?? this.syncStatus,
      invoiceType: invoiceType ?? this.invoiceType,
    );
  }
}
