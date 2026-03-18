import 'package:sqflite/sqflite.dart';
import '../helpers/database_helper.dart';
import '../data/datasources/local/product_local_datasource.dart';
import '../models/product.dart';

class ProductController {
  final ProductLocalDataSource _productDS = ProductLocalDataSource();

  // AMBIL LALU URUTKAN BERDASARKAN HASIL DRAG & DROP
  Future<List<Product>> getAllProducts() async {
    List<Product> list = await _productDS.getAllProducts();
    list.sort((a, b) => a.orderIndex.compareTo(b.orderIndex));
    return list;
  }

  Future<int> createProduct(Product product) async {
    return await _productDS.createProduct(product);
  }

  Future<int> updateProduct(Product product) async {
    return await _productDS.updateProduct(product);
  }

  Future<int> deleteProduct(int id) async {
    return await _productDS.deleteProduct(id);
  }

  Future<void> updateStockQuick(int id, double newStock, int expense) async {
    await _productDS.updateStockQuick(id, newStock, expense);
  }

  Future<void> addStockLog(int pid, String type, double qty, int modal, String note) async {
    await _productDS.addStockLog(pid, type, qty, modal, note);
  }

  // SIMPAN POSISI URUTAN BARU KE DATABASE 
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
}