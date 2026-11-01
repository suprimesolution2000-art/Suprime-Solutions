class UserModel {
  final String id;
  final String name;
  final String username;
  final String role; // 'owner' or 'employee'

  UserModel({
    required this.id,
    required this.name,
    required this.username,
    required this.role,
  });

  bool get isOwner => role == 'owner';
  bool get isEmployee => role == 'employee';

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'username': username,
      'role': role,
    };
  }

  factory UserModel.fromMap(Map<String, dynamic> map) {
    return UserModel(
      id: map['id'] ?? map['_id'] ?? '',
      name: map['name'] ?? '',
      username: map['username'] ?? '',
      role: map['role'] ?? 'owner',
    );
  }
}
