class ProductModel {
  final String uuid;
  final String description;
  final String hsnCode;
  final String unit;
  final double defaultRate;
  final double gstRate;
  final bool active;

  ProductModel({
    required this.uuid,
    required this.description,
    this.hsnCode = '',
    this.unit = 'PCS',
    this.defaultRate = 0.0,
    this.gstRate = 18.0,
    this.active = true,
  });

  Map<String, dynamic> toMap() {
    return {
      'uuid': uuid,
      'description': description,
      'hsn_code': hsnCode,
      'unit': unit,
      'default_rate': defaultRate,
      'gst_rate': gstRate,
      'active': active ? 1 : 0,
    };
  }

  factory ProductModel.fromMap(Map<String, dynamic> map) {
    return ProductModel(
      uuid: map['uuid'] ?? '',
      description: map['description'] ?? '',
      hsnCode: map['hsn_code'] ?? map['hsnCode'] ?? '',
      unit: map['unit'] ?? 'PCS',
      defaultRate: (map['default_rate'] ?? map['defaultRate'] ?? 0.0).toDouble(),
      gstRate: (map['gst_rate'] ?? map['gstRate'] ?? 18.0).toDouble(),
      active: map['active'] == 1 || map['active'] == true,
    );
  }
}
