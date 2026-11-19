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

  bool get isLoggedIn => _activeRole != null;
  bool get isOwner => _activeRole == 'OWNER';
  bool get isEmployee => _activeRole == 'EMPLOYEE';

  /// True jika karyawan login menggunakan akun Email & Password mandiri (tanpa akun Google Bos di HP).
  bool get isStandaloneEmployee =>
      isEmployee && employeeAuthUid != null && employeeAuthUid!.isNotEmpty;

  Future<void> init() async {
    // Baca dari brankas enkripsi
    _activeRole = await _storage.read(key: 'role');
    userName = await _storage.read(key: 'name');
    userEmail = await _storage.read(key: 'email');
    uid = await _storage.read(key: 'uid');
    employeeAuthUid = await _storage.read(key: 'employee_auth_uid');
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
    await _storage.delete(key: 'employee_auth_uid');
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
    if (employeeAuthUid == null || employeeAuthUid.isEmpty) {
      await _storage.delete(key: 'employee_auth_uid');
    }
    await _saveToLocal();
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
    // Hancurkan semua kunci saat logout
    await _storage.deleteAll();
  }
}