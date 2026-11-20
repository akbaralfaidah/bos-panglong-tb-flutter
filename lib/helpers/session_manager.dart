import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SessionManager {
  static final SessionManager _instance = SessionManager._internal();
  factory SessionManager() => _instance;
  SessionManager._internal();

  // 🔥 UBAH JADI SECURE STORAGE BIAR HACKER LOKAL NANGIS
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  String? _activeRole;
  String? userName;
  String? userEmail;
  String? uid;
  String? employeeAuthUid;
  bool _isEmployeeLocked = false;

  bool get isLoggedIn => _activeRole != null && !isEmployeeLocked;
  bool get isOwner => _activeRole == 'OWNER';
  bool get isEmployee => _activeRole == 'EMPLOYEE';

  /// True jika karyawan login menggunakan akun Email & Password mandiri (tanpa akun Google Bos di HP).
  bool get isStandaloneEmployee =>
      isEmployee && employeeAuthUid != null && employeeAuthUid!.isNotEmpty;

  /// True jika perangkat karyawan sedang terkunci dan menunggu verifikasi Sidik Jari / Kunci Layar HP.
  bool get isEmployeeLocked => isStandaloneEmployee && _isEmployeeLocked;

  String get employeeDisplayName =>
      (userName != null && userName!.trim().isNotEmpty)
          ? userName!.trim()
          : 'Karyawan';

  Future<void> init() async {
    // Baca dari brankas enkripsi
    _activeRole = await _storage.read(key: 'role');
    userName = await _storage.read(key: 'name');
    userEmail = await _storage.read(key: 'email');
    uid = await _storage.read(key: 'uid');
    employeeAuthUid = await _storage.read(key: 'employee_auth_uid');
    _isEmployeeLocked =
        (await _storage.read(key: 'employee_session_locked')) == 'true';
  }

  Future<void> loginAsOwner({
    String? name,
    String? email,
    String? userId,
  }) async {
    _activeRole = 'OWNER';
    userName = name;
    userEmail = email;
    uid = userId;
    employeeAuthUid = null;
    _isEmployeeLocked = false;
    await _storage.delete(key: 'employee_auth_uid');
    await _storage.delete(key: 'employee_session_locked');
    await _saveToLocal();
  }

  Future<void> loginAsEmployee({
    String? name,
    String? email,
    String? userId,
    String? employeeAuthUid,
  }) async {
    _activeRole = 'EMPLOYEE';
    userName = name;
    userEmail = email;
    uid = userId;
    this.employeeAuthUid = employeeAuthUid;
    _isEmployeeLocked = false;
    if (employeeAuthUid == null || employeeAuthUid.isEmpty) {
      await _storage.delete(key: 'employee_auth_uid');
      await _storage.delete(key: 'employee_session_locked');
    } else {
      await _storage.write(key: 'employee_session_locked', value: 'false');
    }
    await _saveToLocal();
  }

  /// Mengunci sesi HP karyawan tanpa menghapus ikatan Email & Password toko,
  /// sehingga buka ulang cukup pakai Sidik Jari / Kunci Layar HP (tanpa akses mode Pemilik).
  Future<void> lockEmployeeSession() async {
    if (!isStandaloneEmployee) return;
    _isEmployeeLocked = true;
    await _storage.write(key: 'employee_session_locked', value: 'true');
  }

  /// Membuka kunci sesi HP karyawan setelah verifikasi biometrik/kunci layar berhasil.
  Future<void> unlockEmployeeSession({String? updatedName}) async {
    if (!isStandaloneEmployee) return;
    _isEmployeeLocked = false;
    if (updatedName != null && updatedName.trim().isNotEmpty) {
      userName = updatedName.trim();
      await _storage.write(key: 'name', value: userName!);
    }
    await _storage.write(key: 'employee_session_locked', value: 'false');
  }

  Future<void> _saveToLocal() async {
    // Tulis ke brankas enkripsi
    if (_activeRole != null) await _storage.write(key: 'role', value: _activeRole!);
    if (userName != null) await _storage.write(key: 'name', value: userName!);
    if (userEmail != null) await _storage.write(key: 'email', value: userEmail!);
    if (uid != null) await _storage.write(key: 'uid', value: uid!);
    if (employeeAuthUid != null && employeeAuthUid!.isNotEmpty) {
      await _storage.write(key: 'employee_auth_uid', value: employeeAuthUid!);
    }
  }

  Future<void> logout() async {
    _activeRole = null;
    userName = null;
    userEmail = null;
    uid = null;
    employeeAuthUid = null;
    _isEmployeeLocked = false;
    // Hancurkan semua kunci saat logout
    await _storage.deleteAll();
  }
}