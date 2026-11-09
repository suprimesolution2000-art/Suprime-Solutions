import '../../core/constants/app_constants.dart';

class CustomerModel {
  final String uuid;
  final String name;
  final String businessName;
  final String phone;
  final String email;
  final String gstin;
  final String address;
  final String city;
  final String state;
  final String stateCode;
  final String pincode;
  final double outstandingBalance;
  final double totalBilled;
  final double totalPaid;
  final bool active;

  CustomerModel({
    required this.uuid,
    required this.name,
    this.businessName = '',
    required this.phone,
    this.email = '',
    this.gstin = '',
    this.address = '',
    this.city = AppConstants.defaultCity,
    this.state = AppConstants.defaultState,
    this.stateCode = AppConstants.defaultStateCode,
    this.pincode = '',
    this.outstandingBalance = 0.0,
    this.totalBilled = 0.0,
    this.totalPaid = 0.0,
    this.active = true,
  });

  Map<String, dynamic> toMap() {
    return {
      'uuid': uuid,
      'name': name,
      'business_name': businessName,
      'phone': phone,
      'email': email,
      'gstin': gstin,
      'address': address,
      'city': city,
      'state': state,
      'state_code': stateCode,
      'pincode': pincode,
      'outstanding_balance': outstandingBalance,
      'total_billed': totalBilled,
      'total_paid': totalPaid,
      'active': active ? 1 : 0,
    };
  }

  factory CustomerModel.fromMap(Map<String, dynamic> map) {
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

    return CustomerModel(
      uuid: rawUuid,
      name: (map['name'] ?? '').toString(),
      businessName: (map['business_name'] ?? map['businessName'] ?? '').toString(),
      phone: (map['phone'] ?? '').toString(),
      email: (map['email'] ?? '').toString(),
      gstin: (map['gstin'] ?? '').toString(),
      address: (map['address'] ?? '').toString(),
      city: (map['city'] ?? 'Bilaspur').toString(),
      state: (map['state'] ?? 'Chhattisgarh').toString(),
      stateCode: (map['state_code'] ?? map['stateCode'] ?? '22').toString(),
      pincode: (map['pincode'] ?? '').toString(),
      outstandingBalance: parseNum(map['outstanding_balance'] ?? map['outstandingBalance']),
      totalBilled: parseNum(map['total_billed'] ?? map['totalBilled']),
      totalPaid: parseNum(map['total_paid'] ?? map['totalPaid']),
      active: isActive,
    );
  }

  CustomerModel copyWith({
    String? uuid,
    String? name,
    String? businessName,
    String? phone,
    String? email,
    String? gstin,
    String? address,
    String? city,
    String? state,
    String? stateCode,
    String? pincode,
    double? outstandingBalance,
    double? totalBilled,
    double? totalPaid,
    bool? active,
  }) {
    return CustomerModel(
      uuid: uuid ?? this.uuid,
      name: name ?? this.name,
      businessName: businessName ?? this.businessName,
      phone: phone ?? this.phone,
      email: email ?? this.email,
      gstin: gstin ?? this.gstin,
      address: address ?? this.address,
      city: city ?? this.city,
      state: state ?? this.state,
      stateCode: stateCode ?? this.stateCode,
      pincode: pincode ?? this.pincode,
      outstandingBalance: outstandingBalance ?? this.outstandingBalance,
      totalBilled: totalBilled ?? this.totalBilled,
      totalPaid: totalPaid ?? this.totalPaid,
      active: active ?? this.active,
    );
  }
}
