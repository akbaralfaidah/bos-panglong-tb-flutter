import '../data/datasources/firebase/product_firebase_datasource.dart';
import '../models/product.dart';

class ProductController {
  
  final ProductFirebaseDataSource _productDS = ProductFirebaseDataSource();

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

  // 🔥 UPDATE: MENDUKUNG TANGGAL CUSTOM 🔥
  Future<void> addStockLog(int pid, String type, double qty, int modal, String note, {int? totalExpense, double? inputQty, String? inputUnit, String? exactDate}) async {
    await _productDS.addStockLog(pid, type, qty, modal, note, totalExpense: totalExpense, inputQty: inputQty, inputUnit: inputUnit, exactDate: exactDate);
  }

  Future<void> updateProductOrder(List<Product> products) async {
    for (var p in products) {
      await _productDS.updateProduct(p);
    }
  }

  Future<void> voidStockReceipt(String exactDate) async {
    await _productDS.voidStockReceipt(exactDate);
  }

  // 🔥 HAPUS STOK: RESET STOCK KE 0 🔥
  Future<void> resetStockBatch(List<int> productIds) async {
    await _productDS.resetStockBatch(productIds);
  }
}