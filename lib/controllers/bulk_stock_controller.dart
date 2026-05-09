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
      
      int totalAddedStockForProduct = 0;
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

      int oldStock = baseProduct.stock.toInt();
      int finalBuyPriceUnit = baseProduct.buyPriceUnit;
      int finalBuyPriceCubic = baseProduct.buyPriceCubic;

      // 🔥 3. HITUNG RATA-RATA HARGA MODAL GABUNGAN 🔥
      if (oldStock > 0 && totalAddedStockForProduct > 0) { 
        int oldBuyPriceUnit = finalBuyPriceUnit;
        try {
          final oldDoc = await FirebaseFirestore.instance
              .collection('stores')
              .doc(storeId)
              .collection('products')
              .doc(pid.toString())
              .get();
          if (oldDoc.exists && oldDoc.data() != null) {
            oldBuyPriceUnit = (oldDoc.data()!['buy_price_unit'] as num?)?.toInt() ?? finalBuyPriceUnit;
            oldStock = (oldDoc.data()!['stock'] as num?)?.toInt() ?? oldStock;
          }
        } catch (_) {}

        int newStock = oldStock + totalAddedStockForProduct;
        int oldTotalValueUnit = oldStock * oldBuyPriceUnit;
        int newTotalValueUnit = totalExpenseForProduct; 

        double rawAvgUnit = (oldTotalValueUnit + newTotalValueUnit) / newStock;
        finalBuyPriceUnit = rawAvgUnit.round();

        if (baseProduct.buyPriceUnit > 0 && baseProduct.buyPriceCubic > 0) {
          double ratio = baseProduct.buyPriceCubic / baseProduct.buyPriceUnit;
          finalBuyPriceCubic = (rawAvgUnit * ratio).round();
        }
      } else if (oldStock <= 0 && totalAddedStockForProduct > 0) {
         finalBuyPriceUnit = (totalExpenseForProduct / totalAddedStockForProduct).round();
         if (baseProduct.buyPriceUnit > 0 && baseProduct.buyPriceCubic > 0) {
            double ratio = baseProduct.buyPriceCubic / baseProduct.buyPriceUnit;
            finalBuyPriceCubic = (finalBuyPriceUnit * ratio).round();
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