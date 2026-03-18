import 'package:sqflite/sqflite.dart';
import '../helpers/database_helper.dart';
import '../data/datasources/local/product_local_datasource.dart';
import '../models/product.dart';

class CashierController {
  final ProductLocalDataSource _productDS = ProductLocalDataSource();

  // AMBIL PRODUK LALU URUTKAN BERDASARKAN HASIL DRAG & DROP
  Future<List<Product>> getAllProducts() async {
    List<Product> list = await _productDS.getAllProducts();
    list.sort((a, b) => a.orderIndex.compareTo(b.orderIndex));
    return list;
  }

  // SIMPAN POSISI URUTAN BARU KE DATABASE (SEKALI UPDATE SEMUA)
  Future<void> updateProductOrder(List<Product> products) async {
    final db = await DatabaseHelper.instance.database;
    Batch batch = db.batch();
    for (var p in products) {
      batch.update(
        'products', 
        {'order_index': p.orderIndex}, 
        where: 'id = ?', 
        whereArgs: [p.id]
      );
    }
    await batch.commit(noResult: true);
  }

  int calculateRealStockDeduction(Product p, double inputQty, bool isGrosir) {
    if (!isGrosir) return inputQty.ceil(); 
    if (p.type == 'KAYU') {
      if (p.packContent > 0) return (inputQty * p.packContent).ceil();
      return 0; 
    } else {
      return (inputQty * p.packContent).toInt();
    }
  }
}