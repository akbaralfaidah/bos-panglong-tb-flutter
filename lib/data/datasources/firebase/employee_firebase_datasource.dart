import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../helpers/session_manager.dart';

class EmployeeFirebaseDataSource {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Mengambil ID Bos (Owner)
  String get _bossId {
    final bossId = SessionManager().uid; // <-- FIX NYA DI SINI BRO
    if (bossId == null) throw Exception("Fatal Error: ID Bos tidak ditemukan di sesi! Pastikan routing login benar.");
    return bossId;
  }

  // Ambil data karyawan secara Real-time (Stream)
  Stream<QuerySnapshot> getEmployeesStream() {
    return _firestore
        .collection('users')
        .doc(_bossId)
        .collection('employees')
        .orderBy('createdAt', descending: true)
        .snapshots();
  }

  // Fungsi khusus untuk nampilin list karyawan di popup Login Screen
Stream<QuerySnapshot> getEmployeesForLogin(String bossId) {
    return _firestore
        .collection('users')
        .doc(bossId)
        .collection('employees')
        .orderBy('createdAt', descending: true)
        .snapshots();
  }

  // Tambah Karyawan Baru
  Future<void> addEmployee(String name) async {
    await _firestore
        .collection('users')
        .doc(_bossId)
        .collection('employees')
        .add({
      'name': name,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  // Hapus Karyawan
  Future<void> deleteEmployee(String employeeId) async {
    await _firestore
        .collection('users')
        .doc(_bossId)
        .collection('employees')
        .doc(employeeId)
        .delete();
  }
}