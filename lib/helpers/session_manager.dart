class SessionManager {
  // Singleton Pattern (Agar data sesi bisa diakses dari mana saja)
  static final SessionManager _instance = SessionManager._internal();
  
  factory SessionManager() {
    return _instance;
  }
  
  SessionManager._internal();

  // Variabel untuk menyimpan peran (Role)
  // Nilai: 'OWNER' (Pemilik) atau 'EMPLOYEE' (Karyawan)
  String? _activeRole; 

  // --- GETTERS (Untuk Cek Status) ---
  
  // Cek apakah ada user yang sedang login
  bool get isLoggedIn => _activeRole != null;

  // Cek apakah yang login adalah PEMILIK
  bool get isOwner => _activeRole == 'OWNER';

  // Cek apakah yang login adalah KARYAWAN
  bool get isEmployee => _activeRole == 'EMPLOYEE';

  // --- METHODS (Aksi Login/Logout) ---

  void loginAsOwner() {
    _activeRole = 'OWNER';
  }

  void loginAsEmployee() {
    _activeRole = 'EMPLOYEE';
  }

  void logout() {
    _activeRole = null;
  }
}