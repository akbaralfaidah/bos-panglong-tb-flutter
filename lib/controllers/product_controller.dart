import '../data/datasources/firebase/product_firebase_datasource.dart';
import '../models/product.dart';

class ProductController {
  
  final ProductFirebaseDataSource _productDS = ProductFirebaseDataSource();

  Stream<List<Product>> watchAllProducts() {
    return _productDS.watchAllProducts().map((list) {
      final sorted = List<Product>.from(list);
      sorted.sort((a, b) => a.orderIndex.compareTo(b.orderIndex));
      return sorted;
    });
  }

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

  Future<void> updateStockQuick(int id, double newStock, int expense, {String? exactDate}) async {
    await _productDS.updateStockQuick(id, newStock, expense, exactDate: exactDate);
  }

  Future<void> correctPhysicalStock({
    required Product product,
    required double newPhysicalStock,
    String note = '',
  }) async {
    await _productDS.correctPhysicalStock(
      product: product,
      newPhysicalStock: newPhysicalStock,
      note: note,
    );
  }

  Future<void> resetReservedStockToZero(Product product) async {
    await _productDS.resetReservedStockToZero(product);
  }

  // 🔥 UPDATE: MENDUKUNG TANGGAL CUSTOM & AUDIT FIELDS 🔥
  Future<void> addStockLog(
    int pid,
    String type,
    double qty,
    int modal,
    String note, {
    int? totalExpense,
    double? inputQty,
    String? inputUnit,
    String? exactDate,
    double? stokSebelum,
    double? stokSesudah,
    int? modalSebelum,
    int? modalMasuk,
    int? modalSesudah,
  }) async {
    await _productDS.addStockLog(
      pid,
      type,
      qty,
      modal,
      note,
      totalExpense: totalExpense,
      inputQty: inputQty,
      inputUnit: inputUnit,
      exactDate: exactDate,
      stokSebelum: stokSebelum,
      stokSesudah: stokSesudah,
      modalSebelum: modalSebelum,
      modalMasuk: modalMasuk,
      modalSesudah: modalSesudah,
    );
  }

  Future<void> updateProductOrder(List<Product> products) async {
    await _productDS.updateProductOrderBatch(products);
  }

  Future<void> voidStockReceipt(String exactDate) async {
    await _productDS.voidStockReceipt(exactDate);
  }

  // 🔥 HAPUS STOK: RESET STOCK KE 0 🔥
  Future<void> resetStockBatch(List<int> productIds) async {
    await _productDS.resetStockBatch(productIds);
  }
}