class UserModel {
  final String? uid;
  final String role; // 'owner' atau 'karyawan'
  final String storeId; // ID Toko (penting untuk SaaS)
  final String? name;

  UserModel({
    this.uid,
    required this.role,
    required this.storeId,
    this.name,
  });

  // Convert dari JSON (Firestore) ke Object
  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      uid: json['uid'],
      role: json['role'] ?? 'karyawan',
      storeId: json['storeId'] ?? '',
      name: json['name'] ?? '',
    );
  }

  // Convert dari Object ke JSON (untuk simpan ke Firestore)
  Map<String, dynamic> toJson() {
    return {
      'uid': uid,
      'role': role,
      'storeId': storeId,
      'name': name,
    };
  }
}