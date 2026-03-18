import '../helpers/database_helper.dart';
import '../screens/product_list_screen.dart'; // Untuk memanggil class StockCartItem

class BulkStockController {
  // Fungsi ini dipanggil pas lu klik "SIMPAN & BUAT BUKTI MASUK" di layar Review
  Future<void> saveBulkStock(List<StockCartItem> items) async {
    final db = await DatabaseHelper.instance.database;

    // Kita pakai db.transaction biar aman.
    // Kalau ada 1 barang gagal disimpen, semuanya bakal di-cancel (gak akan ada data nyangkut)
    await db.transaction((txn) async {
      for (var item in items) {
        // 1. UPDATE JUMLAH STOK DI TABEL PRODUK
        await txn.rawUpdate(
          'UPDATE products SET stock = stock + ? WHERE id = ?',
          [item.finalStockAdd, item.product.id],
        );

        // 2. (OPSIONAL) CATAT KE TABEL LOG/HISTORY STOK
        // Kalau lu punya tabel history stok, logikanya dimasukin ke sini.
        // Contoh kasarnya begini (Bisa disesuaikan atau dihapus kalau lu belum pakai tabel log):
        try {
          int modalSatuan = item.finalStockAdd > 0
              ? (item.totalExpense / item.finalStockAdd).round()
              : 0;

          await txn.rawInsert(
            '''INSERT INTO stock_logs 
               (product_id, type, quantity, price, note, date) 
               VALUES (?, ?, ?, ?, ?, ?)''',
            [
              item.product.id,
              item.product.type, // 'KAYU', 'RENG', dll
              item.finalStockAdd,
              modalSatuan,
              'Restock Gudang',
              DateTime.now().toIso8601String(),
            ],
          );
        } catch (e) {
          // Kalau tabel stock_logs beda strukturnya/gak ada, biarin aja errornya numpang lewat,
          // yang penting stok utamanya udah nambah di langkah 1.
          print(
            "Catatan: Lewati insert log karena struktur tabel mungkin berbeda.",
          );
        }
      }
    });
  }
}
