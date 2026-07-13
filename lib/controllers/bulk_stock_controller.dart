import 'package:cloud_firestore/cloud_firestore.dart';
import '../helpers/session_manager.dart';
import '../data/datasources/firebase/product_firebase_datasource.dart';
import '../models/product.dart';
import '../screens/product_list_screen.dart'; 

class BulkStockController {
  final ProductFirebaseDataSource _productDS = ProductFirebaseDataSource();

  Future<void> saveBulkStock(List<StockCartItem> items, String exactDate) async {
    WriteBatch batch = FirebaseFirestore.instance.batch();
    String storeId = SessionManager().uid ?? 'UNKNOWN_STORE';

    // 🔥 1. KELOMPOKKAN ITEM BERDASARKAN ID PRODUK 🔥
    // Biar kalau ada 1 Kotak dan 8 Pcs (barang sama), nggak saling tindih (overwrite) di Firebase
    Map<int, List<StockCartItem>> groupedItems = {};
    for (var item in items) {
      int pid = item.product.id!;
      if (!groupedItems.containsKey(pid)) {
        groupedItems[pid] = [];
      }
      groupedItems[pid]!.add(item);
    }

    // 🔥 2. LOOPING PER PRODUK (BUKAN PER BARIS KERANJANG) 🔥
    for (var pid in groupedItems.keys) {
      var productItems = groupedItems[pid]!;
      
      double totalAddedStockForProduct = 0;
      int totalExpenseForProduct = 0;
      Product baseProduct = productItems.first.product;

      for (var item in productItems) {
        totalAddedStockForProduct += item.finalStockAdd;
        totalExpenseForProduct += item.totalExpense;
        
        // Simpan log riwayat untuk masing-masing baris (Biar di histori tetep misah 1 Kotak & 8 Pcs)
        int modalSatuanTeknis = 0;
        if (item.addedQty > 0) {
          modalSatuanTeknis = (item.totalExpense / item.addedQty).round();
        }

        await _productDS.addStockLog(
          pid,
          item.product.type,
          item.addedQty,          
          modalSatuanTeknis, 
          "Stok Tambahan (${item.unitName})", 
          totalExpense: item.totalExpense, 
          inputQty: item.addedQty,         
          inputUnit: item.unitName,
          exactDate: exactDate 
        );
      }

      double oldStock = baseProduct.stock;
      int finalBuyPriceUnit = baseProduct.buyPriceUnit;
      int finalBuyPriceCubic = baseProduct.buyPriceCubic;

      // 🔥 3. MODAL LANGSUNG REPLACE DENGAN HARGA BELI BARU 🔥
      // Tidak lagi rata-rata tertimbang. Modal baru = harga beli baru per satuan.
      if (totalAddedStockForProduct > 0 && totalExpenseForProduct > 0) {
        double rawUnit = totalExpenseForProduct / totalAddedStockForProduct;
        // Bulatkan ke kelipatan 5 terdekat
        finalBuyPriceUnit = ((rawUnit.round() + 2) ~/ 5) * 5;

        if (baseProduct.buyPriceUnit > 0 && baseProduct.buyPriceCubic > 0) {
          double ratio = baseProduct.buyPriceCubic / baseProduct.buyPriceUnit;
          int rawCubic = (finalBuyPriceUnit * ratio).round();
          finalBuyPriceCubic = ((rawCubic + 2) ~/ 5) * 5;
        }
      }

      // 🔥 4. UPDATE DATABASE CUMA 1 KALI PER PRODUK DENGAN TOTAL GABUNGAN 🔥
      // Di sini 1 Kotak (12) + 8 Pcs dikirim sebagai 1 perintah: "Increment(20)"
      DocumentReference prodRef = FirebaseFirestore.instance
          .collection('stores')
          .doc(storeId)
          .collection('products')
          .doc(pid.toString());

      batch.set(prodRef, {
        'stock': FieldValue.increment(totalAddedStockForProduct),
        'buy_price_unit': finalBuyPriceUnit,
        'buy_price_cubic': finalBuyPriceCubic,
      }, SetOptions(merge: true));
    }
    
    // Eksekusi ke database secara bersamaan
    await batch.commit();
  }
}