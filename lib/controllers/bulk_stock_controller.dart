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

    for (var item in items) {
      int pid = item.product.id!;
      double actualQtyAdded = item.finalStockAdd.toDouble(); 
      int oldStock = item.product.stock.toInt();
      int addedStock = item.finalStockAdd;

      int finalBuyPriceUnit = item.product.buyPriceUnit;
      int finalBuyPriceCubic = item.product.buyPriceCubic;

      // 🔥 PERBAIKAN RATA-RATA HARGA 🔥
      if (oldStock > 0 && addedStock > 0) { 
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

        int newStock = oldStock + addedStock;
        int oldTotalValueUnit = oldStock * oldBuyPriceUnit;
        int newTotalValueUnit = item.totalExpense; 

        double rawAvgUnit = (oldTotalValueUnit + newTotalValueUnit) / newStock;
        finalBuyPriceUnit = rawAvgUnit.round();

        if (item.product.buyPriceUnit > 0 && item.product.buyPriceCubic > 0) {
          double ratio = item.product.buyPriceCubic / item.product.buyPriceUnit;
          finalBuyPriceCubic = (rawAvgUnit * ratio).round();
        }
      }

      // 🔥 SOLUSI RACE CONDITION (ANTI GAIB): Pakai FieldValue.increment 🔥
      DocumentReference prodRef = FirebaseFirestore.instance
          .collection('stores')
          .doc(storeId)
          .collection('products')
          .doc(pid.toString());

      batch.set(prodRef, {
        'stock': FieldValue.increment(addedStock),
        'buy_price_unit': finalBuyPriceUnit,
        'buy_price_cubic': finalBuyPriceCubic,
      }, SetOptions(merge: true));

      int modalSatuanTeknis = 0;
      if (actualQtyAdded > 0) {
        modalSatuanTeknis = (item.totalExpense / actualQtyAdded).round();
      }

      // Simpan riwayat historis
      await _productDS.addStockLog(
        pid,
        item.product.type,
        actualQtyAdded,          
        modalSatuanTeknis, 
        "Stok Tambahan (Masal)", 
        totalExpense: item.totalExpense, 
        inputQty: item.addedQty,         
        inputUnit: item.unitName,
        exactDate: exactDate 
      );
    }
    
    // Eksekusi semua penambahan stok secara bersamaan tanpa takut ketimpa!
    await batch.commit();
  }
}