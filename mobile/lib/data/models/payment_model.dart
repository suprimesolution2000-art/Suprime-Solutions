class PaymentModel {
  final String uuid;
  final String invoiceId;
  final String invoiceNumber;
  final String customerId;
  final String customerName;
  final double amount;
  final String paymentMethod;
  final String referenceNumber;
  final DateTime paymentDate;
  final String notes;
  final String receivedBy;
  final String deviceId;

  PaymentModel({
    required this.uuid,
    required this.invoiceId,
    required this.invoiceNumber,
    required this.customerId,
    required this.customerName,
    required this.amount,
    this.paymentMethod = 'UPI',
    this.referenceNumber = '',
    required this.paymentDate,
    this.notes = '',
    this.receivedBy = 'Admin',
    this.deviceId = '',
  });

  Map<String, dynamic> toMap() {
    return {
      'uuid': uuid,
      'invoice_id': invoiceId,
      'invoice_number': invoiceNumber,
      'customer_id': customerId,
      'customer_name': customerName,
      'amount': amount,
      'payment_method': paymentMethod,
      'reference_number': referenceNumber,
      'payment_date': paymentDate.toIso8601String(),
      'notes': notes,
      'received_by': receivedBy,
      'device_id': deviceId,
    };
  }

  factory PaymentModel.fromMap(Map<String, dynamic> map) {
    return PaymentModel(
      uuid: map['uuid'] ?? '',
      invoiceId: map['invoice_id'] ?? map['invoiceId'] ?? '',
      invoiceNumber: map['invoice_number'] ?? map['invoiceNumber'] ?? '',
      customerId: map['customer_id'] ?? map['customerId'] ?? '',
      customerName: map['customer_name'] ?? map['customerName'] ?? '',
      amount: (map['amount'] ?? 0.0).toDouble(),
      paymentMethod: map['payment_method'] ?? map['paymentMethod'] ?? 'UPI',
      referenceNumber: map['reference_number'] ?? map['referenceNumber'] ?? '',
      paymentDate: DateTime.tryParse(map['payment_date'] ?? map['paymentDate'] ?? '') ?? DateTime.now(),
      notes: map['notes'] ?? '',
      receivedBy: map['received_by'] ?? map['receivedBy'] ?? 'Admin',
      deviceId: map['device_id'] ?? map['deviceId'] ?? '',
    );
  }
}
