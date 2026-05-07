import '../data/datasources/firebase/product_firebase_datasource.dart'; // IMPORT FIREBASE
import '../models/product.dart';

class CashierController {
  // SWAP MESIN KE FIREBASE
  final ProductFirebaseDataSource _productDS = ProductFirebaseDataSource();

  // AMBIL PRODUK LALU URUTKAN BERDASARKAN HASIL DRAG & DROP
  Future<List<Product>> getAllProducts() async {
    List<Product> list = await _productDS.getAllProducts();
    list.sort((a, b) => a.orderIndex.compareTo(b.orderIndex));
    return list;
  }

  // SIMPAN POSISI URUTAN BARU KE FIREBASE
  Future<void> updateProductOrder(List<Product> products) async {
    for (var p in products) {
      await _productDS.updateProduct(p);
    }
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