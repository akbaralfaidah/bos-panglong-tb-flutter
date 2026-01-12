import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:intl/intl.dart';
import 'dart:io'; 
import '../models/product.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('panglong_v5.db'); 
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);

    return await openDatabase(
      path,
      version: 1,
      onCreate: _createDB,
    );
  }

  // --- FUNGSI PENTING UNTUK BACKUP & RESTORE ---
  
  // 1. Ambil Lokasi File Database
  Future<String> getDbPath() async {
    final dbPath = await getDatabasesPath();
    return join(dbPath, 'panglong_v5.db');
  }

  // 2. Tutup Koneksi Database (Wajib sebelum Restore)
  Future<void> close() async {
    final db = await instance.database;
    db.close();
    _database = null; // Reset instance biar nanti buka baru
  }
  // ----------------------------------------------

  Future _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE products (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        type TEXT NOT NULL,
        stock INTEGER NOT NULL,
        source TEXT,
        dimensions TEXT,
        buy_price_unit INTEGER,
        buy_price_cubic INTEGER,
        sell_price_unit INTEGER,
        sell_price_cubic INTEGER,
        pack_content INTEGER
      )
    ''');

    await db.execute('''
      CREATE TABLE transactions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        total_price INTEGER,
        operational_cost INTEGER,
        customer_name TEXT,
        payment_method TEXT,
        payment_status TEXT,
        queue_number INTEGER, 
        transaction_date TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE transaction_items (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        transaction_id INTEGER,
        product_id INTEGER,
        product_name TEXT,
        product_type TEXT,
        quantity INTEGER,
        unit_type TEXT,
        capital_price INTEGER,
        sell_price INTEGER
      )
    ''');

    await db.execute('''
      CREATE TABLE stock_logs (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        product_id INTEGER,
        product_type TEXT,
        quantity_added REAL,
        capital_price INTEGER,
        date TEXT,
        note TEXT
      )
    ''');

    await db.execute('CREATE TABLE settings (key TEXT PRIMARY KEY, value TEXT)');
    await db.execute('CREATE TABLE customers (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT UNIQUE)');
  }

  // --- QUERY LAPORAN & TRANSAKSI ---

  Future<List<Map<String, dynamic>>> getTransactionHistory({required String startDate, required String endDate}) async {
    final db = await instance.database;
    String start = "$startDate 00:00:00";
    String end = "$endDate 23:59:59";
    
    return await db.query(
      'transactions', 
      where: 'transaction_date BETWEEN ? AND ?', 
      whereArgs: [start, end],
      // REVISI: Urutkan berdasarkan TANGGAL, bukan ID. Biar data 'masa lalu' tampil di bawah.
      orderBy: 'transaction_date DESC' 
    );
  }

  Future<List<Map<String, dynamic>>> getAllDebtHistory() async {
    final db = await instance.database;
    return await db.query(
      'transactions',
      where: 'payment_method = ?',
      whereArgs: ['HUTANG'],
      orderBy: 'transaction_date DESC'
    );
  }

  Future<List<Map<String, dynamic>>> getTransactionItems(int transactionId) async {
    final db = await instance.database;
    return await db.query(
      'transaction_items',
      where: 'transaction_id = ?',
      whereArgs: [transactionId],
    );
  }

  Future<void> updateTransactionStatus(int id, String status) async {
    final db = await instance.database;
    String dateNow = DateFormat('yyyy-MM-dd HH:mm:ss').format(DateTime.now());
    
    await db.update(
      'transactions', 
      {
        'payment_status': status,
        'transaction_date': dateNow 
      }, 
      where: 'id = ?', 
      whereArgs: [id]
    );
  }

  Future<int> getTotalPiutangAllTime() async {
    final db = await instance.database;
    final result = await db.rawQuery(
      "SELECT SUM(total_price) as total FROM transactions WHERE payment_status = 'Belum Lunas'"
    );
    return (result.first['total'] as int?) ?? 0;
  }

  Future<List<Map<String, dynamic>>> getSoldItemsDetail({required String startDate, required String endDate}) async {
    final db = await instance.database;
    String start = "$startDate 00:00:00";
    String end = "$endDate 23:59:59";

    return await db.rawQuery('''
      SELECT i.*, t.transaction_date, t.customer_name, t.id as trans_id 
      FROM transaction_items i 
      JOIN transactions t ON i.transaction_id = t.id 
      WHERE t.transaction_date BETWEEN ? AND ? 
      ORDER BY t.transaction_date DESC
    ''', [start, end]);
  }

  Future<List<Map<String, dynamic>>> getStockLogsDetail({required String startDate, required String endDate}) async {
    final db = await instance.database;
    String start = "$startDate 00:00:00";
    String end = "$endDate 23:59:59";

    return await db.rawQuery('''
      SELECT s.*, p.name as product_name 
      FROM stock_logs s 
      LEFT JOIN products p ON s.product_id = p.id 
      WHERE s.date BETWEEN ? AND ? AND s.quantity_added > 0
      ORDER BY s.date DESC
    ''', [start, end]);
  }

  // --- QUERY KHUSUS LAPORAN EXCEL & ANALISA ---

  Future<List<Map<String, dynamic>>> getCompleteReportData({required String startDate, required String endDate}) async {
    final db = await instance.database;
    String start = "$startDate 00:00:00";
    String end = "$endDate 23:59:59";

    return await db.rawQuery('''
      SELECT 
        t.transaction_date, 
        t.id as invoice_id, 
        t.customer_name, 
        t.payment_status,
        i.product_name, 
        i.quantity, 
        i.unit_type,
        i.capital_price, 
        i.sell_price 
      FROM transactions t
      JOIN transaction_items i ON t.id = i.transaction_id
      WHERE t.transaction_date BETWEEN ? AND ?
      ORDER BY t.transaction_date DESC
    ''', [start, end]);
  }

  Future<List<Map<String, dynamic>>> getTopProducts({required String startDate, required String endDate}) async {
    final db = await instance.database;
    String start = "$startDate 00:00:00";
    String end = "$endDate 23:59:59";

    return await db.rawQuery('''
      SELECT 
        i.product_name, 
        SUM(i.quantity) as total_qty,
        i.unit_type
      FROM transaction_items i
      JOIN transactions t ON i.transaction_id = t.id
      WHERE t.transaction_date BETWEEN ? AND ?
      GROUP BY i.product_name
      ORDER BY total_qty DESC
      LIMIT 5
    ''', [start, end]);
  }

  // --- FUNGSI TRANSAKSI CORE ---

  Future<int> createTransaction({
    required int totalPrice, required int operational_cost, required String customerName, 
    required String paymentMethod, required String paymentStatus, required int queueNumber, 
    required List<dynamic> items,
    String? transaction_date // REVISI: Tambah parameter opsional biar bisa inject tanggal masa lalu
  }) async {
    final db = await instance.database;
    String dateNow = transaction_date ?? DateFormat('yyyy-MM-dd HH:mm:ss').format(DateTime.now());
    
    try {
      return await db.transaction((txn) async {
        int tId = await txn.insert('transactions', {
          'total_price': totalPrice, 
          'operational_cost': operational_cost, 
          'customer_name': customerName,
          'payment_method': paymentMethod, 
          'payment_status': paymentStatus, 
          'queue_number': queueNumber, 
          'transaction_date': dateNow 
        });

        for (var item in items) {
          await txn.insert('transaction_items', {
            'transaction_id': tId, 
            'product_id': item.productId, 
            'product_name': item.productName,
            'product_type': item.productType, 
            'quantity': item.quantity, 
            'unit_type': item.unitType,
            'capital_price': item.capitalPrice, 
            'sell_price': item.sellPrice
          });
          
          await txn.rawUpdate(
            'UPDATE products SET stock = stock - ? WHERE id = ?', 
            [item.quantity, item.productId]
          );
        }
        return tId;
      });
    } catch (e) { return -1; }
  }

  Future<int> getNextQueueNumber() async {
    final db = await instance.database;
    String todayStart = DateFormat('yyyy-MM-dd').format(DateTime.now()) + " 00:00:00";
    String todayEnd = DateFormat('yyyy-MM-dd').format(DateTime.now()) + " 23:59:59";
    
    final result = await db.rawQuery(
      "SELECT MAX(queue_number) as max_q FROM transactions WHERE transaction_date BETWEEN ? AND ?",
      [todayStart, todayEnd]
    );
    int lastQ = (result.first['max_q'] as int?) ?? 0;
    return lastQ + 1;
  }

  // --- CRUD PRODUK ---
  
  Future<int> createProduct(Product p) async {
    final db = await instance.database;
    return await db.insert('products', p.toMap());
  }
  
  Future<List<Product>> getAllProducts() async {
    final db = await instance.database;
    final res = await db.query('products', orderBy: 'name ASC');
    return res.map((j) => Product.fromMap(j)).toList();
  }
  
  Future<int> updateProduct(Product p) async {
    final db = await instance.database;
    return await db.update('products', p.toMap(), where: 'id = ?', whereArgs: [p.id]);
  }
  
  Future<int> deleteProduct(int id) async {
    final db = await instance.database;
    await db.delete('stock_logs', where: 'product_id = ?', whereArgs: [id]);
    return await db.delete('products', where: 'id = ?', whereArgs: [id]);
  }
  
  // --- SETTINGS & CUSTOMER ---
  Future<void> saveSetting(String k, String v) async {
    final db = await instance.database;
    await db.insert('settings', {'key': k, 'value': v}, conflictAlgorithm: ConflictAlgorithm.replace);
  }
  Future<String?> getSetting(String k) async {
    final db = await instance.database;
    final m = await db.query('settings', where: 'key = ?', whereArgs: [k]);
    return m.isNotEmpty ? m.first['value'] as String : null;
  }
  Future<void> saveCustomer(String name) async {
    final db = await instance.database;
    await db.rawInsert('INSERT OR IGNORE INTO customers(name) VALUES(?)', [name]);
  }
  Future<List<String>> getCustomers() async {
    final db = await instance.database;
    final r = await db.query('customers', orderBy: 'name ASC');
    return r.map((e) => e['name'] as String).toList();
  }

  // --- STOK LOGIC ---
  Future<void> updateStockQuick(int id, double newStock, int expense) async {
    final db = await instance.database;
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
  
  Future<void> addStockLog(int pid, String type, double qty, int modal, String note) async {
    final db = await instance.database;
    String dateNow = DateFormat('yyyy-MM-dd HH:mm:ss').format(DateTime.now());
    
    await db.insert('stock_logs', {
      'product_id': pid, 
      'product_type': type, 
      'quantity_added': qty, 
      'capital_price': modal, 
      'date': dateNow,
      'note': note
    });
  }
}