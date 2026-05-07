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
      Get.snackbar("Peringatan", "Nama karyawan tidak boleh kosong, bro!", 
          snackPosition: SnackPosition.BOTTOM);
      return;
    }

    try {
      isLoading.value = true;
      await _dataSource.addEmployee(name.trim());
      Get.snackbar("Sukses", "Karyawan $name berhasil ditambahkan", 
          snackPosition: SnackPosition.BOTTOM);
    } catch (e) {
      Get.snackbar("Gagal", "Database error: $e", 
          snackPosition: SnackPosition.BOTTOM);
    } finally {
      isLoading.value = false;
    }
  }

  // Fungsi Hapus
  Future<void> deleteEmployee(String id, String name) async {
    try {
      isLoading.value = true;
      await _dataSource.deleteEmployee(id);
      Get.snackbar("Sukses", "Karyawan $name sudah dihapus dari sistem", 
          snackPosition: SnackPosition.BOTTOM);
    } catch (e) {
      Get.snackbar("Gagal", "Gagal menghapus data: $e", 
          snackPosition: SnackPosition.BOTTOM);
    } finally {
      isLoading.value = false;
    }
  }
}