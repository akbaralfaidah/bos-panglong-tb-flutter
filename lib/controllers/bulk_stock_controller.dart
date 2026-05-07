import 'package:cloud_firestore/cloud_firestore.dart';
import '../helpers/session_manager.dart';
import '../data/datasources/firebase/product_firebase_datasource.dart';
import '../models/product.dart';
import '../screens/product_list_screen.dart'; 

class BulkStockController {
  final ProductFirebaseDataSource _productDS = ProductFirebaseDataSource();

  Future<void> saveBulkStock(List<StockCartItem> items, String exactDate) async {
    for (var item in items) {
      int pid = item.product.id!;
      double actualQtyAdded = item.finalStockAdd.toDouble(); 
      int oldStock = item.product.stock.toInt();
      int addedStock = item.finalStockAdd;
      int newStock = oldStock + addedStock;

      int finalBuyPriceUnit = item.product.buyPriceUnit;
      int finalBuyPriceCubic = item.product.buyPriceCubic;

      // 🔥 PERBAIKAN MUTLAK: Rata-rata tertimbang HANYA JALAN jika stok lama masih ada (> 0).
      // Jika stok lama 0, sistem BYPASS hitungan ini dan langsung save modal 23.300 / 655.000 sesuai ketikan Bos!
      if (oldStock > 0 && addedStock > 0) { 
        int oldBuyPriceUnit = finalBuyPriceUnit;
        
        try {
          // Ambil modal lama asli dari Database untuk akurasi tingkat tinggi
          final oldDoc = await FirebaseFirestore.instance
              .collection('stores')
              .doc(SessionManager().uid ?? 'UNKNOWN_STORE')
              .collection('products')
              .doc(pid.toString())
              .get();
          if (oldDoc.exists) {
            oldBuyPriceUnit = (oldDoc.data()!['buy_price_unit'] as num?)?.toInt() ?? finalBuyPriceUnit;
          }
        } catch (_) {}

        int oldTotalValueUnit = oldStock * oldBuyPriceUnit;
        int newTotalValueUnit = item.totalExpense; 

        double rawAvgUnit = (oldTotalValueUnit + newTotalValueUnit) / newStock;
        finalBuyPriceUnit = rawAvgUnit.round();

        if (item.product.buyPriceUnit > 0 && item.product.buyPriceCubic > 0) {
          double ratio = item.product.buyPriceCubic / item.product.buyPriceUnit;
          finalBuyPriceCubic = (rawAvgUnit * ratio).round();
        }
      }

      Map<String, dynamic> productMap = item.product.toMap();
      productMap['stock'] = newStock;
      productMap['buy_price_unit'] = finalBuyPriceUnit; 
      productMap['buy_price_cubic'] = finalBuyPriceCubic; 

      Product updatedProduct = Product.fromMap(productMap);

      await _productDS.updateProduct(updatedProduct);

      int modalSatuanTeknis = 0;
      if (actualQtyAdded > 0) {
        modalSatuanTeknis = (item.totalExpense / actualQtyAdded).round();
      }

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
  }
}