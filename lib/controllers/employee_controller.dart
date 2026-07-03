import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../data/datasources/firebase/employee_firebase_datasource.dart';

class EmployeeController extends GetxController {
  // Panggil Datasource yang udah dikarantina
  final EmployeeFirebaseDataSource _dataSource = EmployeeFirebaseDataSource();

  // State untuk loading biar UI tahu kapan harus muter-muter
  var isLoading = false.obs;

  // Stream data langsung diteruskan ke UI biar UI murni nampilin doang
  Stream<QuerySnapshot> get employeeStream => _dataSource.getEmployeesStream();

  // Fungsi Tambah
  Future<void> addEmployee(String name) async {
    if (name.trim().isEmpty) {
      Get.snackbar(
        "Peringatan",
        "Nama karyawan tidak boleh kosong, bro!",
        snackPosition: SnackPosition.TOP,
        backgroundColor: const Color(0xFF78350F).withOpacity(0.88),
        colorText: Colors.white,
        borderRadius: 20,
        margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        icon: const Icon(Icons.warning_rounded, color: Color(0xFFF59E0B)),
        shouldIconPulse: false,
        duration: const Duration(seconds: 3),
      );
      return;
    }

    try {
      isLoading.value = true;
      await _dataSource.addEmployee(name.trim());
      Get.snackbar(
        "Sukses",
        "Karyawan $name berhasil ditambahkan",
        snackPosition: SnackPosition.TOP,
        backgroundColor: const Color(0xFF14532D).withOpacity(0.88),
        colorText: Colors.white,
        borderRadius: 20,
        margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        icon: const Icon(Icons.check_circle_rounded, color: Color(0xFF22C55E)),
        shouldIconPulse: false,
        duration: const Duration(seconds: 3),
      );
    } catch (e) {
      Get.snackbar(
        "Gagal",
        "Database error: $e",
        snackPosition: SnackPosition.TOP,
        backgroundColor: const Color(0xFF7F1D1D).withOpacity(0.88),
        colorText: Colors.white,
        borderRadius: 20,
        margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        icon: const Icon(Icons.cancel_rounded, color: Color(0xFFEF4444)),
        shouldIconPulse: false,
        duration: const Duration(seconds: 3),
      );
    } finally {
      isLoading.value = false;
    }
  }

  // Fungsi Hapus
  Future<void> deleteEmployee(String id, String name) async {
    try {
      isLoading.value = true;
      await _dataSource.deleteEmployee(id);
      Get.snackbar(
        "Sukses",
        "Karyawan $name sudah dihapus dari sistem",
        snackPosition: SnackPosition.TOP,
        backgroundColor: const Color(0xFF14532D).withOpacity(0.88),
        colorText: Colors.white,
        borderRadius: 20,
        margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        icon: const Icon(Icons.check_circle_rounded, color: Color(0xFF22C55E)),
        shouldIconPulse: false,
        duration: const Duration(seconds: 3),
      );
    } catch (e) {
      Get.snackbar(
        "Gagal",
        "Gagal menghapus data: $e",
        snackPosition: SnackPosition.TOP,
        backgroundColor: const Color(0xFF7F1D1D).withOpacity(0.88),
        colorText: Colors.white,
        borderRadius: 20,
        margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        icon: const Icon(Icons.cancel_rounded, color: Color(0xFFEF4444)),
        shouldIconPulse: false,
        duration: const Duration(seconds: 3),
      );
    } finally {
      isLoading.value = false;
    }
  }
}