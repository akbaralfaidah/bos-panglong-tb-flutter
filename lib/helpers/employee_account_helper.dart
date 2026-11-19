/// Model tautan akun login karyawan yang tersimpan di koleksi Firestore
/// `employee_accounts/{employeeAuthUid}` dan menunjuk ke `storeId` milik Pemilik Toko.
class EmployeeAccountLink {
  final String authUid;
  final String storeId;
  final String name;
  final String email;
  final String employeeDocId;
  final String storeName;
  final bool isActive;

  const EmployeeAccountLink({
    required this.authUid,
    required this.storeId,
    required this.name,
    required this.email,
    required this.employeeDocId,
    required this.storeName,
    required this.isActive,
  });

  static EmployeeAccountLink? fromMap(
    String authUid,
    Map<String, dynamic>? data,
  ) {
    if (data == null) return null;
    final String storeId = (data['storeId'] ?? '').toString().trim();
    if (storeId.isEmpty) return null;

    final String name = (data['name'] ?? 'Karyawan').toString().trim();
    final String email = (data['email'] ?? '').toString().trim().toLowerCase();
    final String employeeDocId = (data['employeeDocId'] ?? '').toString().trim();
    final String storeName = (data['storeName'] ?? '').toString().trim();
    final bool isActive = data['isActive'] != false;

    return EmployeeAccountLink(
      authUid: authUid,
      storeId: storeId,
      name: name.isEmpty ? 'Karyawan' : name,
      email: email,
      employeeDocId: employeeDocId,
      storeName: storeName,
      isActive: isActive,
    );
  }
}

/// Helper validasi & pesan error ramah pengguna untuk fitur akun login karyawan mandiri.
class EmployeeAccountHelper {
  static final RegExp _emailRegex = RegExp(
    r'^[^\s@]+@[^\s@]+\.[^\s@]+$',
  );

  static String normalizeEmail(String raw) => raw.trim().toLowerCase();

  /// Mengembalikan pesan error dalam Bahasa Indonesia jika input tidak valid, atau `null` jika valid.
  static String? validateNewEmployee({
    required String name,
    required String email,
    required String password,
  }) {
    if (name.trim().isEmpty) {
      return 'Nama karyawan wajib diisi.';
    }
    final cleanEmail = normalizeEmail(email);
    if (cleanEmail.isEmpty || !_emailRegex.hasMatch(cleanEmail)) {
      return 'Format email login tidak valid (contoh: budi@depot.com).';
    }
    if (password.trim().length < 6) {
      return 'Password minimal 6 karakter.';
    }
    return null;
  }

  /// Menerjemahkan kode error Firebase Auth ke pesan yang jelas untuk pemilik & karyawan.
  static String mapAuthErrorCode(String code) {
    switch (code) {
      case 'email-already-in-use':
        return 'Email ini sudah terdaftar. Gunakan email lain (misal: nama.kasir@depot.com).';
      case 'invalid-email':
        return 'Format email tidak valid.';
      case 'weak-password':
        return 'Password terlalu lemah. Gunakan minimal 6 karakter.';
      case 'user-not-found':
      case 'wrong-password':
      case 'invalid-credential':
        return 'Email atau password salah. Periksa kembali dari Pemilik Toko.';
      case 'user-disabled':
        return 'Akun karyawan ini sedang dinonaktifkan.';
      case 'too-many-requests':
        return 'Terlalu banyak percobaan login. Tunggu sebentar lalu coba lagi.';
      case 'network-request-failed':
        return 'Tidak ada koneksi internet. Pastikan internet aktif untuk login.';
      case 'operation-not-allowed':
        return 'Login Email/Password belum diaktifkan di Firebase Console (Authentication -> Sign-in method).';
      default:
        return 'Autentikasi gagal ($code).';
    }
  }
}
