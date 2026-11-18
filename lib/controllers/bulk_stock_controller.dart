import 'package:cloud_firestore/cloud_firestore.dart';
import '../helpers/session_manager.dart';
import '../data/datasources/firebase/product_firebase_datasource.dart';
import '../helpers/stock_cost_calculator.dart';
import '../models/product.dart';
import '../screens/product_list_screen.dart'; 

class BulkStockController {
  Future<void> saveBulkStock(List<StockCartItem> items, String exactDate) async {
    final firestore = FirebaseFirestore.instance;
    String storeId = SessionManager().uid ?? 'UNKNOWN_STORE';
    final storeRef = firestore.collection('stores').doc(storeId);

    // 🔥 1. KELOMPOKKAN ITEM BERDASARKAN ID PRODUK 🔥
    // Menangani kasus baris ganda (misal 1 Kotak dan 8 Pcs untuk produk yang sama)
    Map<int, List<StockCartItem>> groupedItems = {};
    for (var item in items) {
      int pid = item.product.id!;
      if (!groupedItems.containsKey(pid)) {
        groupedItems[pid] = [];
      }
      groupedItems[pid]!.add(item);
    }

    // 🔥 2. JALANKAN DALAM FIRESTORE TRANSACTION ATOMIK 🔥
    // Memastikan pembacaan stok/modal lama dilakukan secara real-time saat write
    await firestore.runTransaction((transaction) async {
      // ═════════════════════════════════════════════════════════
      // FASE A: BACA SEMUA DOKUMEN PRODUK TERKINI (ALL READS FIRST)
      // ═════════════════════════════════════════════════════════
      Map<int, DocumentSnapshot> productSnapshots = {};
      for (var pid in groupedItems.keys) {
        DocumentReference prodRef = storeRef.collection('products').doc(pid.toString());
        DocumentSnapshot snap = await transaction.get(prodRef);
        productSnapshots[pid] = snap;
      }

      // ═════════════════════════════════════════════════════════
      // FASE B: PROSES PERHITUNGAN & PENULISAN ATOMIK (ALL WRITES)
      // ═════════════════════════════════════════════════════════
      for (var pid in groupedItems.keys) {
        var productItems = groupedItems[pid]!;
        DocumentReference prodRef = storeRef.collection('products').doc(pid.toString());
        DocumentSnapshot snap = productSnapshots[pid]!;

        Product baseProduct = productItems.first.product;

        // Ambil stok & modal segar dari snapshot database
        double dbStock = baseProduct.stock;
        int dbBuyPriceUnit = baseProduct.buyPriceUnit;
        int dbBuyPriceCubic = baseProduct.buyPriceCubic;
        String pType = baseProduct.type;

        if (snap.exists && snap.data() != null) {
          Map<String, dynamic> data = snap.data() as Map<String, dynamic>;
          dbStock = (data['stock'] as num?)?.toDouble() ?? dbStock;
          dbBuyPriceUnit = (data['buy_price_unit'] as num?)?.toInt() ?? dbBuyPriceUnit;
          dbBuyPriceCubic = (data['buy_price_cubic'] as num?)?.toInt() ?? dbBuyPriceCubic;
          pType = data['type'] as String? ?? pType;
        }

        // Hitung total fisik stok masuk dan total uang keluar untuk produk ini
        // (Agregasi baris ganda dihitung duluan sebelum di-blend dengan stok lama)
        double totalAddedStockForProduct = 0;
        int totalExpenseForProduct = 0;
        for (var item in productItems) {
          totalAddedStockForProduct += item.finalStockAdd;
          totalExpenseForProduct += item.totalExpense;
        }

        // Hitung modal baru (Rata-rata tertimbang untuk kayu, modal replace untuk bangunan)
        double fallbackRatio = 0.0;
        if (baseProduct.buyPriceUnit > 0 && baseProduct.buyPriceCubic > 0) {
          fallbackRatio = baseProduct.buyPriceCubic / baseProduct.buyPriceUnit;
        }

        final modalResult = StockCostCalculator.calculateNewStockModal(
          productType: pType,
          oldStock: dbStock,
          oldBuyPriceUnit: dbBuyPriceUnit,
          oldBuyPriceCubic: dbBuyPriceCubic,
          totalAddedStock: totalAddedStockForProduct,
          totalExpense: totalExpenseForProduct,
          fallbackRatio: fallbackRatio,
        );

        double newStock = dbStock + totalAddedStockForProduct;

        // Simpan log riwayat untuk masing-masing baris item dengan audit fields
        for (var item in productItems) {
          int logId = ProductFirebaseDataSource.generateUniqueLogId();
          int modalSatuanTeknis = 0;
          if (item.addedQty > 0) {
            modalSatuanTeknis = (item.totalExpense / item.addedQty).round();
          }

          DocumentReference logRef = storeRef.collection('stock_logs').doc(logId.toString());

          Map<String, dynamic> logData = {
            'id': logId,
            'product_id': pid,
            'type': item.product.type,
            'quantity': item.addedQty,
            'price': modalSatuanTeknis,
            'total_price': item.totalExpense,
            'input_qty': item.addedQty,
            'input_unit': item.unitName,
            'note': "Stok Tambahan (${item.unitName})",
            'date': exactDate,
            'cashier_name': SessionManager().userName ?? 'Tidak Diketahui',
            // 🔥 AUDIT FIELDS LENGKAP 🔥
            'stok_sebelum': dbStock,
            'stok_sesudah': newStock,
            'modal_sebelum': dbBuyPriceUnit,
            'modal_masuk': modalResult.incomingCostUnit,
            'modal_sesudah': modalResult.buyPriceUnit,
          };

          transaction.set(logRef, logData);
        }

        // Update master produk (stok dan modal) dalam transaksi yang sama
        transaction.set(prodRef, {
          'stock': newStock,
          'buy_price_unit': modalResult.buyPriceUnit,
          'buy_price_cubic': modalResult.buyPriceCubic,
        }, SetOptions(merge: true));
      }
    });
  }
}