import 'package:intl/intl.dart';
import 'package:sqflite/sqflite.dart';
import '../../../models/product.dart';
import '../../../helpers/database_helper.dart';

class ProductLocalDataSource {
  final DatabaseHelper _dbHelper = DatabaseHelper.instance;

  Future<int> createProduct(Product p) async {
    final db = await _dbHelper.database;
    return await db.insert('products', p.toMap());
  }
  
  Future<List<Product>> getAllProducts() async {
    final db = await _dbHelper.database;
    final res = await db.query('products', orderBy: 'name ASC');
    return res.map((j) => Product.fromMap(j)).toList();
  }
  
  Future<int> updateProduct(Product p) async {
    final db = await _dbHelper.database;
    return await db.update('products', p.toMap(), where: 'id = ?', whereArgs: [p.id]);
  }
  
  Future<int> deleteProduct(int id) async {
    final db = await _dbHelper.database;
    await db.delete('stock_logs', where: 'product_id = ?', whereArgs: [id]);
    return await db.delete('products', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> updateStockQuick(int id, double newStock, int expense) async {
    final db = await _dbHelper.database;
    final old = await db.query('products', where: 'id = ?', whereArgs: [id]);
    if(old.isNotEmpty) {
      double oldStk = (old.first['stock'] as int).toDouble();
      double add = newStock - oldStk;
      if(add > 0) {
        int modal = (expense / add).round();
        if(expense == 0) modal = old.first['buy_price_unit'] as int;
        await addStockLog(id, old.first['type'] as String, add, modal, "Tambah Cepat");
      }
      await db.update('products', {'stock': newStock.toInt()}, where: 'id = ?', whereArgs: [id]);
    }
  }
  
  // =========================================================================
  // FIX ERROR MERAH DI SINI: NAMA KOLOM DISAMAKAN DENGAN DATABASE BARU
  // =========================================================================
  Future<void> addStockLog(int pid, String type, double qty, int modal, String note) async {
    final db = await _dbHelper.database;
    String dateNow = DateFormat('yyyy-MM-dd HH:mm:ss').format(DateTime.now());
    
    await db.insert('stock_logs', {
      'product_id': pid, 
      'type': type,             // Tadinya 'product_type'
      'quantity': qty.toInt(),  // Tadinya 'quantity_added'. Diubah ke int sesuai SQLite
      'price': modal,           // Tadinya 'capital_price'
      'date': dateNow, 
      'note': note
    });
  }
}