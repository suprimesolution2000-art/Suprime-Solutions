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
    double parseDouble(dynamic val, [double def = 0.0]) {
      if (val == null) return def;
      if (val is num) return val.toDouble();
      return double.tryParse(val.toString()) ?? def;
    }
    int parseInt(dynamic val, [int def = 1]) {
      if (val == null) return def;
      if (val is num) return val.toInt();
      return int.tryParse(val.toString()) ?? def;
    }

    return InvoiceItemModel(
      sno: parseInt(map['sno'], 1),
      description: map['description'] ?? '',
      hsnCode: map['hsn_code'] ?? map['hsnCode'] ?? '',
      quantity: parseDouble(map['quantity'], 0.0),
      unit: map['unit'] ?? 'PCS',
      rate: parseDouble(map['rate'], 0.0),
      discount: parseDouble(map['discount'], 0.0),
      taxableValue: parseDouble(map['taxable_value'] ?? map['taxableValue'], 0.0),
      gstRate: parseDouble(map['gst_rate'] ?? map['gstRate'], 18.0),
      cgstRate: parseDouble(map['cgst_rate'] ?? map['cgstRate'], 0.0),
      cgstAmount: parseDouble(map['cgst_amount'] ?? map['cgstAmount'], 0.0),
      sgstRate: parseDouble(map['sgst_rate'] ?? map['sgstRate'], 0.0),
      sgstAmount: parseDouble(map['sgst_amount'] ?? map['sgstAmount'], 0.0),
      igstRate: parseDouble(map['igst_rate'] ?? map['igstRate'], 0.0),
      igstAmount: parseDouble(map['igst_amount'] ?? map['igstAmount'], 0.0),
      totalAmount: parseDouble(map['total_amount'] ?? map['totalAmount'], 0.0),
    );
  }
}
