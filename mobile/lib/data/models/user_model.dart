class UserModel {
  final String id;
  final String name;
  final String username;
  final String role; // 'owner' or 'employee'
  final String? phone;
  final bool active;

  UserModel({
    required this.id,
    required this.name,
    required this.username,
    required this.role,
    this.phone,
    this.active = true,
  });

  bool get isOwner => role == 'owner';
  bool get isEmployee => role == 'employee';

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'username': username,
      'role': role,
      'phone': phone,
      'active': active,
    };
  }

  factory UserModel.fromMap(Map<String, dynamic> map) {
    return UserModel(
      id: (map['id'] ?? map['_id'] ?? '').toString(),
      name: (map['name'] ?? '').toString(),
      username: (map['username'] ?? '').toString(),
      role: (map['role'] ?? 'employee').toString(),
      phone: map['phone']?.toString(),
      active: map['active'] == null
          ? true
          : (map['active'] == true ||
              map['active'] == 1 ||
              map['active'].toString().toLowerCase() == 'true' ||
              map['active'].toString() == '1'),
    );
  }
}
