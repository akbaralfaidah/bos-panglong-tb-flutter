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

  bool get isLoggedIn => _activeRole != null;
  bool get isOwner => _activeRole == 'OWNER';
  bool get isEmployee => _activeRole == 'EMPLOYEE';

  Future<void> init() async {
    // Baca dari brankas enkripsi
    _activeRole = await _storage.read(key: 'role');
    userName = await _storage.read(key: 'name');
    userEmail = await _storage.read(key: 'email');
    uid = await _storage.read(key: 'uid');
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
    await _saveToLocal();
  }

  Future<void> loginAsEmployee({
    String? name,
    String? email,
    String? userId,
  }) async {
    _activeRole = 'EMPLOYEE';
    userName = name;
    userEmail = email;
    uid = userId;
    await _saveToLocal();
  }

  Future<void> _saveToLocal() async {
    // Tulis ke brankas enkripsi
    if (_activeRole != null) await _storage.write(key: 'role', value: _activeRole!);
    if (userName != null) await _storage.write(key: 'name', value: userName!);
    if (userEmail != null) await _storage.write(key: 'email', value: userEmail!);
    if (uid != null) await _storage.write(key: 'uid', value: uid!);
  }

  Future<void> logout() async {
    _activeRole = null;
    userName = null;
    userEmail = null;
    uid = null;
    // Hancurkan semua kunci saat logout
    await _storage.deleteAll();
  }
}