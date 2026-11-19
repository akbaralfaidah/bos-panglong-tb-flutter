import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../data/datasources/firebase/employee_firebase_datasource.dart';

class EmployeeController extends GetxController {
  final EmployeeFirebaseDataSource _dataSource = EmployeeFirebaseDataSource();

  var isLoading = false.obs;

  Stream<QuerySnapshot> get employeeStream => _dataSource.getEmployeesStream();

  void _showToast({
    required String title,
    required String message,
    required Color bg,
    required IconData icon,
    required Color iconColor,
  }) {
    Get.snackbar(
      title,
      message,
      snackPosition: SnackPosition.TOP,
      backgroundColor: bg.withValues(alpha: 0.92),
      colorText: Colors.white,
      borderRadius: 18,
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      icon: Icon(icon, color: iconColor),
      shouldIconPulse: false,
      duration: const Duration(seconds: 3),
    );
  }

  // Tambah karyawan shift biasa (tanpa email)
  Future<bool> addEmployee(String name) async {
    if (name.trim().isEmpty) {
      _showToast(
        title: "Peringatan",
        message: "Nama karyawan tidak boleh kosong.",
        bg: const Color(0xFF78350F),
        icon: Icons.warning_rounded,
        iconColor: const Color(0xFFF59E0B),
      );
      return false;
    }

    try {
      isLoading.value = true;
      await _dataSource.addEmployee(name.trim());
      _showToast(
        title: "Sukses",
        message: "Karyawan ${name.trim()} berhasil ditambahkan",
        bg: const Color(0xFF14532D),
        icon: Icons.check_circle_rounded,
        iconColor: const Color(0xFF22C55E),
      );
      return true;
    } catch (e) {
      _showToast(
        title: "Gagal",
        message: e.toString().replaceFirst('Exception: ', ''),
        bg: const Color(0xFF7F1D1D),
        icon: Icons.cancel_rounded,
        iconColor: const Color(0xFFEF4444),
      );
      return false;
    } finally {
      isLoading.value = false;
    }
  }

  // Tambah karyawan dengan akun Email & Password mandiri yang terhubung ke toko Bos
  Future<bool> addEmployeeWithAccount({
    required String name,
    required String email,
    required String password,
  }) async {
    try {
      isLoading.value = true;
      await _dataSource.addEmployeeWithAccount(
        name: name,
        email: email,
        password: password,
      );
      _showToast(
        title: "Akun Karyawan Dibuat",
        message:
            "${name.trim()} kini bisa login di HP sendiri dengan email ${email.trim().toLowerCase()}",
        bg: const Color(0xFF14532D),
        icon: Icons.check_circle_rounded,
        iconColor: const Color(0xFF22C55E),
      );
      return true;
    } catch (e) {
      _showToast(
        title: "Gagal Membuat Akun",
        message: e.toString().replaceFirst('Exception: ', ''),
        bg: const Color(0xFF7F1D1D),
        icon: Icons.cancel_rounded,
        iconColor: const Color(0xFFEF4444),
      );
      return false;
    } finally {
      isLoading.value = false;
    }
  }

  // Aktifkan / nonaktifkan akses login karyawan
  Future<void> toggleEmployeeActive({
    required String employeeDocId,
    String? authUid,
    required String name,
    required bool isActive,
  }) async {
    try {
      await _dataSource.setEmployeeActive(
        employeeDocId: employeeDocId,
        authUid: authUid,
        isActive: isActive,
      );
      _showToast(
        title: isActive ? "Akses Diaktifkan" : "Akses Dinonaktifkan",
        message: isActive
            ? "$name kini dapat login kembali."
            : "Akses login $name dihentikan sementara.",
        bg: isActive ? const Color(0xFF14532D) : const Color(0xFF78350F),
        icon: isActive ? Icons.check_circle_rounded : Icons.block_rounded,
        iconColor:
            isActive ? const Color(0xFF22C55E) : const Color(0xFFF59E0B),
      );
    } catch (e) {
      _showToast(
        title: "Gagal",
        message: "Gagal mengubah status akses: $e",
        bg: const Color(0xFF7F1D1D),
        icon: Icons.cancel_rounded,
        iconColor: const Color(0xFFEF4444),
      );
    }
  }

  // Hapus karyawan + cabut tautan akun loginnya
  Future<void> deleteEmployee(
    String id,
    String name, {
    String? authUid,
  }) async {
    try {
      isLoading.value = true;
      await _dataSource.deleteEmployee(id, authUid: authUid);
      _showToast(
        title: "Sukses",
        message: "Karyawan $name & akses loginnya telah dihapus",
        bg: const Color(0xFF14532D),
        icon: Icons.check_circle_rounded,
        iconColor: const Color(0xFF22C55E),
      );
    } catch (e) {
      _showToast(
        title: "Gagal",
        message: "Gagal menghapus data: $e",
        bg: const Color(0xFF7F1D1D),
        icon: Icons.cancel_rounded,
        iconColor: const Color(0xFFEF4444),
      );
    } finally {
      isLoading.value = false;
    }
  }
}
