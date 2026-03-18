import '../data/datasources/local/transaction_local_datasource.dart';
import '../data/datasources/local/core_local_datasource.dart';
import '../models/product.dart'; 
import '../screens/cashier_screen.dart'; // Untuk mengambil definisi CartItem

class CheckoutController {
  final TransactionLocalDataSource _transDS = TransactionLocalDataSource();
  final CoreLocalDataSource _coreDS = CoreLocalDataSource();

  // Ambil daftar pelanggan untuk fitur Auto-Complete
  Future<List<String>> getSavedCustomers() async {
    return await _coreDS.getCustomers();
  }

  // Logika Utama Penyimpanan Transaksi
  Future<int> processTransaction({
    required List<CartItem> cartItems,
    required int totalPrice,
    required int operationalCost,
    required String customerName,
    required String paymentMethod,
    required String paymentStatus,
  }) async {
    // 1. Generate Nomor Antrean Otomatis
    int queueNumber = await _transDS.getNextQueueNumber();

    // 2. Mapping format CartItem (UI) ke CartItemModel (Database)
    List<CartItemModel> itemsToSave = cartItems.map((c) => CartItemModel(
      productId: c.product.id!,
      productName: c.product.name,
      productType: c.product.type,
      quantity: c.stockDeduction, // Qty Final yang memotong stok
      requestQty: c.qty,          // Qty asli yang diinput (misal: 5 Kubik)
      unitType: c.unitName,
      capitalPrice: c.capitalPrice,
      sellPrice: c.sellPrice,
    )).toList();

    // 3. Simpan Transaksi melalui Data Source
    String finalCustomerName = customerName.trim().isEmpty ? "Pelanggan Umum" : customerName.trim();
    
    int transId = await _transDS.createTransaction(
      totalPrice: totalPrice,
      operationalCost: operationalCost,
      customerName: finalCustomerName,
      paymentMethod: paymentMethod,
      paymentStatus: paymentStatus,
      queueNumber: queueNumber,
      items: itemsToSave,
    );

    // 4. Simpan Nama Pelanggan ke CRM (Jika belum ada)
    if (finalCustomerName != "Pelanggan Umum") {
      await _coreDS.saveCustomer(finalCustomerName);
    }

    return transId;
  }
}