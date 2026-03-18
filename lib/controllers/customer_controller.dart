import '../data/datasources/local/core_local_datasource.dart';

class CustomerController {
  final CoreLocalDataSource _coreDS = CoreLocalDataSource();

  // Ambil daftar nama pelanggan
  Future<List<String>> getAllCustomers() async {
    return await _coreDS.getCustomers();
  }

  // Ambil transaksi spesifik berdasarkan nama pelanggan
  Future<List<Map<String, dynamic>>> getTransactionsByCustomer(String name) async {
    return await _coreDS.getTransactionsByCustomer(name);
  }
}