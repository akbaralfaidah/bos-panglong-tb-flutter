import 'package:cloud_firestore/cloud_firestore.dart';
import '../helpers/session_manager.dart';
import '../data/datasources/local/transaction_local_datasource.dart';
import '../data/datasources/local/core_local_datasource.dart';
import '../models/product.dart'; 
import '../screens/cashier_screen.dart'; 

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
      quantity: c.stockDeduction, 
      requestQty: c.qty,          
      unitType: c.unitName,
      capitalPrice: c.capitalPrice,
      sellPrice: c.sellPrice,
    )).toList();

    String finalCustomerName = customerName.trim().isEmpty ? "Pelanggan Umum" : customerName.trim();
    
    // 3. Simpan Transaksi ke Laci Kasir (SQLite LOKAL)
    int transId = await _transDS.createTransaction(
      totalPrice: totalPrice,
      operationalCost: operationalCost,
      customerName: finalCustomerName,
      paymentMethod: paymentMethod,
      paymentStatus: paymentStatus,
      queueNumber: queueNumber,
      items: itemsToSave,
    );

    if (finalCustomerName != "Pelanggan Umum") {
      await _coreDS.saveCustomer(finalCustomerName);
    }

    // 🔥 4. SINKRONISASI MUTLAK KE FIREBASE (AKUNTAN) 🔥
    // Kalau Lunas, PAKSA lapor ke Firebase biar Modal Cair Nambah!
    if (paymentStatus.toLowerCase() == 'lunas') {
      try {
        WriteBatch batch = FirebaseFirestore.instance.batch();
        String storeId = SessionManager().uid ?? 'UNKNOWN_STORE';

        for (var c in cartItems) {
          // Ambil harga modal x jumlah barang yang dibeli pelanggan
          double addedModal = (c.capitalPrice * c.stockDeduction).toDouble();
          
          if (addedModal > 0) {
            DocumentReference prodRef = FirebaseFirestore.instance
                .collection('stores')
                .doc(storeId)
                .collection('products')
                .doc(c.product.id.toString());

            // Tambahkan duit modalnya ke Firebase sekarang juga!
            batch.set(prodRef, {
              'modal_cair': FieldValue.increment(addedModal) 
            }, SetOptions(merge: true));
          }
        }
        await batch.commit(); // Eksekusi pengiriman data
        print("SUKSES: Modal Cair Berhasil Disetor ke Firebase!");
      } catch (e) {
        print("ERROR: Gagal setor modal ke Firebase: $e");
      }
    }

    return transId;
  }
}