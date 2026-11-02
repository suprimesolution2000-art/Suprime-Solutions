class InvoiceItemModel {
  final int sno;
  final String description;
  final String hsnCode;
  final double quantity;
  final String unit;
  final double rate;
  final double discount;
  final double taxableValue;
  final double gstRate;
  final double cgstRate;
  final double cgstAmount;
  final double sgstRate;
  final double sgstAmount;
  final double igstRate;
  final double igstAmount;
  final double totalAmount;

  InvoiceItemModel({
    required this.sno,
    required this.description,
    this.hsnCode = '',
    required this.quantity,
    this.unit = 'PCS',
    required this.rate,
    this.discount = 0.0,
    required this.taxableValue,
    this.gstRate = 18.0,
    this.cgstRate = 9.0,
    this.cgstAmount = 0.0,
    this.sgstRate = 9.0,
    this.sgstAmount = 0.0,
    this.igstRate = 0.0,
    this.igstAmount = 0.0,
    required this.totalAmount,
  });

  Map<String, dynamic> toMap() {
    return {
      'sno': sno,
      'description': description,
      'hsn_code': hsnCode,
      'quantity': quantity,
      'unit': unit,
      'rate': rate,
      'discount': discount,
      'taxable_value': taxableValue,
      'gst_rate': gstRate,
      'cgst_rate': cgstRate,
      'cgst_amount': cgstAmount,
      'sgst_rate': sgstRate,
      'sgst_amount': sgstAmount,
      'igst_rate': igstRate,
      'igst_amount': igstAmount,
      'total_amount': totalAmount,
    };
  }

  Map<String, dynamic> toApiMap() {
    return {
      'sno': sno,
      'description': description,
      'hsnCode': hsnCode,
      'quantity': quantity,
      'unit': unit,
      'rate': rate,
      'discount': discount,
      'taxableValue': taxableValue,
      'gstRate': gstRate,
      'cgstRate': cgstRate,
      'cgstAmount': cgstAmount,
      'sgstRate': sgstRate,
      'sgstAmount': sgstAmount,
      'igstRate': igstRate,
      'igstAmount': igstAmount,
      'totalAmount': totalAmount,
    };
  }

  factory InvoiceItemModel.fromMap(Map<String, dynamic> map) {
    return InvoiceItemModel(
      sno: (map['sno'] ?? 1) as int,
      description: map['description'] ?? '',
      hsnCode: map['hsn_code'] ?? map['hsnCode'] ?? '',
      quantity: (map['quantity'] ?? 0.0).toDouble(),
      unit: map['unit'] ?? 'PCS',
      rate: (map['rate'] ?? 0.0).toDouble(),
      discount: (map['discount'] ?? 0.0).toDouble(),
      taxableValue: (map['taxable_value'] ?? map['taxableValue'] ?? 0.0).toDouble(),
      gstRate: (map['gst_rate'] ?? map['gstRate'] ?? 18.0).toDouble(),
      cgstRate: (map['cgst_rate'] ?? map['cgstRate'] ?? 0.0).toDouble(),
      cgstAmount: (map['cgst_amount'] ?? map['cgstAmount'] ?? 0.0).toDouble(),
      sgstRate: (map['sgst_rate'] ?? map['sgstRate'] ?? 0.0).toDouble(),
      sgstAmount: (map['sgst_amount'] ?? map['sgstAmount'] ?? 0.0).toDouble(),
      igstRate: (map['igst_rate'] ?? map['igstRate'] ?? 0.0).toDouble(),
      igstAmount: (map['igst_amount'] ?? map['igstAmount'] ?? 0.0).toDouble(),
      totalAmount: (map['total_amount'] ?? map['totalAmount'] ?? 0.0).toDouble(),
    );
  }
}
