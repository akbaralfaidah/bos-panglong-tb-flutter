import '../data/datasources/firebase/core_firebase_datasource.dart';

class CustomerController {
  // SWAP MESIN KE FIREBASE
  final CoreFirebaseDataSource _coreDS = CoreFirebaseDataSource();

  // Ambil daftar nama pelanggan
  Future<List<String>> getAllCustomers() async {
    return await _coreDS.getCustomers();
  }

  // Ambil transaksi spesifik berdasarkan nama pelanggan (TIPE DATA KEMBALI SEPERTI SEMULA: LIST)
  Future<List<Map<String, dynamic>>> getTransactionsByCustomer(String name) async {
    return await _coreDS.getTransactionsByCustomer(name);
  }
}