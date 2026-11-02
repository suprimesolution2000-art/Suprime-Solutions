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

  Map<String, dynamic> toApiMap() {
    return {
      'uuid': uuid,
      'description': description,
      'hsnCode': hsnCode,
      'unit': unit,
      'defaultRate': defaultRate,
      'gstRate': gstRate,
      'active': active,
    };
  }

  factory ProductModel.fromMap(Map<String, dynamic> map) {
    double parseNum(dynamic val) {
      if (val == null) return 0.0;
      if (val is num) return val.toDouble();
      return double.tryParse(val.toString()) ?? 0.0;
    }

    final rawUuid = (map['uuid'] ?? map['_id'] ?? '').toString();
    final isActive = map['active'] == null ||
        map['active'] == 1 ||
        map['active'] == true ||
        map['active'] == '1' ||
        map['active'] == 'true';

    return ProductModel(
      uuid: rawUuid,
      description: (map['description'] ?? '').toString(),
      hsnCode: (map['hsn_code'] ?? map['hsnCode'] ?? '').toString(),
      unit: (map['unit'] ?? 'PCS').toString(),
      defaultRate: parseNum(map['default_rate'] ?? map['defaultRate']),
      gstRate: parseNum(map['gst_rate'] ?? map['gstRate'] ?? 18.0),
      active: isActive,
    );
  }
}
