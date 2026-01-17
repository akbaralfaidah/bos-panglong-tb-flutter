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
      // VERSI 5 (Sesuai file terakhir)
      version: 5, 
      onCreate: _createDB,
      onUpgrade: _onUpgrade, 
    );
  }

  Future<String> getDbPath() async {
    final dbPath = await getDatabasesPath();
    return join(dbPath, 'panglong_v5.db');
  }

  Future<void> close() async {
    final db = await instance.database;
    db.close();
    _database = null; 
  }

  // LOGIC BIKIN DB BARU
  Future _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE products (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        type TEXT NOT NULL,
        stock INTEGER NOT NULL,
        source TEXT,
        dimensions TEXT,
        wood_class TEXT, 
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
        discount INTEGER DEFAULT 0, 
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
        request_qty REAL DEFAULT 0, 
        unit_type TEXT,
        capital_price INTEGER,
        sell_price INTEGER
      )
    ''');

    // REVISI: Tambah previous_stock
    await db.execute('''
      CREATE TABLE stock_logs (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        product_id INTEGER,
        product_type TEXT,
        quantity_added REAL,
        previous_stock REAL DEFAULT 0, -- KOLOM BARU (AUDIT)
        capital_price INTEGER,
        date TEXT,
        note TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE debt_payments (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        transaction_id INTEGER,
        amount_paid INTEGER,
        payment_date TEXT,
        note TEXT
      )
    ''');

    await db.execute('CREATE TABLE settings (key TEXT PRIMARY KEY, value TEXT)');
    await db.execute('CREATE TABLE customers (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT UNIQUE)');
  }

  // LOGIC UPDATE DB LAMA (MIGRASI)
  Future _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute('ALTER TABLE products ADD COLUMN wood_class TEXT');
    }
    if (oldVersion < 3) {
      await db.execute('ALTER TABLE transactions ADD COLUMN discount INTEGER DEFAULT 0');
    }
    if (oldVersion < 4) {
      await db.execute('ALTER TABLE transaction_items ADD COLUMN request_qty REAL DEFAULT 0');
    }
    // MIGRASI KE VERSI 5 (Audit Stok)
    if (oldVersion < 5) {
      await db.execute('ALTER TABLE stock_logs ADD COLUMN previous_stock REAL DEFAULT 0');
    }
  }

  // ==========================================
  // FITUR DATA PELANGGAN (CRM)
  // ==========================================

  Future<List<Map<String, dynamic>>> getTransactionsByCustomer(String name) async {
    final db = await instance.database;
    return await db.query(
      'transactions',
      where: 'customer_name LIKE ?',
      whereArgs: ['$name%'], 
      orderBy: 'transaction_date DESC'
    );
  }

  // ==========================================
  // LOGIKA HUTANG & CICILAN
  // ==========================================

  Future<List<Map<String, dynamic>>> getAllDebtHistory({String? startDate, String? endDate}) async {
    final db = await instance.database;
    String whereClause = 'payment_status = ?';
    List<dynamic> args = ['Belum Lunas'];

    if (startDate != null && endDate != null) {
      whereClause += ' AND transaction_date BETWEEN ? AND ?';
      args.add("$startDate 00:00:00");
      args.add("$endDate 23:59:59");
    }

    return await db.query(
      'transactions',
      where: whereClause,
      whereArgs: args,
      orderBy: 'transaction_date DESC'
    );
  }

  Future<List<Map<String, dynamic>>> getDebtPayments(int transactionId) async {
    final db = await instance.database;
    return await db.query(
      'debt_payments',
      where: 'transaction_id = ?',
      whereArgs: [transactionId],
      orderBy: 'payment_date ASC'
    );
  }

  Future<void> addDebtPayment(int transId, int amount, String note) async {
    final db = await instance.database;
    String dateNow = DateFormat('yyyy-MM-dd HH:mm:ss').format(DateTime.now());

    await db.transaction((txn) async {
      await txn.insert('debt_payments', {
        'transaction_id': transId,
        'amount_paid': amount,
        'payment_date': dateNow,
        'note': note
      });

      final res = await txn.rawQuery(
        'SELECT SUM(amount_paid) as total FROM debt_payments WHERE transaction_id = ?',
        [transId]
      );
      int alreadyPaid = (res.first['total'] as int?) ?? 0;

      final trans = await txn.query('transactions', columns: ['total_price', 'operational_cost', 'discount'], where: 'id = ?', whereArgs: [transId]);
      
      if (trans.isNotEmpty) {
        int totalPrice = (trans.first['total_price'] as int?) ?? 0;
        
        if (alreadyPaid >= totalPrice) {
          await txn.update(
            'transactions',
            {'payment_status': 'Lunas'},
            where: 'id = ?',
            whereArgs: [transId]
          );
        }
      }
    });
  }

  Future<int> getTotalPiutangAllTime() async {
    final db = await instance.database;
    final resTrans = await db.rawQuery("SELECT SUM(total_price) as total FROM transactions WHERE payment_status = 'Belum Lunas'");
    int totalHutang = (resTrans.first['total'] as int?) ?? 0;

    final resPaid = await db.rawQuery(
      "SELECT SUM(p.amount_paid) as total FROM debt_payments p JOIN transactions t ON p.transaction_id = t.id WHERE t.payment_status = 'Belum Lunas'"
    );
    int totalSudahDibayar = (resPaid.first['total'] as int?) ?? 0;

    return totalHutang - totalSudahDibayar;
  }

  Future<List<Map<String, dynamic>>> getDebtReport({
    required String status,
    required String startDate,
    required String endDate
  }) async {
    final db = await instance.database;
    String start = "$startDate 00:00:00";
    String end = "$endDate 23:59:59";

    String whereClause = 'payment_status = ? AND transaction_date BETWEEN ? AND ?';
    if (status == 'Lunas') {
      whereClause += " AND payment_method = 'HUTANG'";
    }

    return await db.query(
      'transactions',
      where: whereClause,
      whereArgs: [status, start, end],
      orderBy: 'transaction_date DESC'
    );
  }

  // ==========================================
  // QUERY LAPORAN LAINNYA
  // ==========================================

  // --- REVISI QUERY SOLD ITEMS (Join Product Info) ---
  Future<List<Map<String, dynamic>>> getSoldItemsDetail({required String startDate, required String endDate}) async {
    final db = await instance.database;
    String start = "$startDate 00:00:00";
    String end = "$endDate 23:59:59";

    return await db.rawQuery('''
      SELECT 
        i.*, 
        t.transaction_date, 
        t.customer_name, 
        t.id as trans_id,
        p.wood_class,
        p.source,
        p.dimensions
      FROM transaction_items i 
      JOIN transactions t ON i.transaction_id = t.id 
      LEFT JOIN products p ON i.product_id = p.id
      WHERE t.transaction_date BETWEEN ? AND ? 
      ORDER BY t.transaction_date DESC
    ''', [start, end]);
  }

  // REVISI: JOIN Products untuk ambil Dimensions, Wood Class, Pack Content
  Future<List<Map<String, dynamic>>> getStockLogsDetail({required String startDate, required String endDate}) async {
    final db = await instance.database;
    String start = "$startDate 00:00:00";
    String end = "$endDate 23:59:59";

    return await db.rawQuery('''
      SELECT 
        s.*, 
        p.name as product_name,
        p.dimensions,
        p.wood_class,
        p.pack_content
      FROM stock_logs s 
      LEFT JOIN products p ON s.product_id = p.id 
      WHERE s.date BETWEEN ? AND ? AND s.quantity_added > 0
      ORDER BY s.date DESC
    ''', [start, end]);
  }

  Future<List<Map<String, dynamic>>> getTransactionHistory({required String startDate, required String endDate}) async {
    final db = await instance.database;
    String start = "$startDate 00:00:00";
    String end = "$endDate 23:59:59";
    
    return await db.query(
      'transactions', 
      where: 'transaction_date BETWEEN ? AND ?', 
      whereArgs: [start, end],
      orderBy: 'transaction_date DESC' 
    );
  }

  Future<List<Map<String, dynamic>>> getTransactionItems(int transactionId) async {
    final db = await instance.database;
    return await db.query('transaction_items', where: 'transaction_id = ?', whereArgs: [transactionId]);
  }

  Future<void> updateTransactionStatus(int id, String status) async {
    final db = await instance.database;
    await db.update('transactions', {'payment_status': status}, where: 'id = ?', whereArgs: [id]);
  }

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
        t.discount,
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

  Future<int> createTransaction({
    required int totalPrice, 
    required int operational_cost, 
    required String customerName, 
    required String paymentMethod, 
    required String paymentStatus, 
    required int queueNumber, 
    required List<dynamic> items, 
    String? transaction_date,
    int discount = 0, 
  }) async {
    final db = await instance.database;
    String dateNow = transaction_date ?? DateFormat('yyyy-MM-dd HH:mm:ss').format(DateTime.now());
    
    try {
      return await db.transaction((txn) async {
        int tId = await txn.insert('transactions', {
          'total_price': totalPrice, 
          'operational_cost': operational_cost, 
          'discount': discount, 
          'customer_name': customerName, 
          'payment_method': paymentMethod, 
          'payment_status': paymentStatus, 
          'queue_number': queueNumber, 
          'transaction_date': dateNow 
        });

        for (var item in items) {
          // Cast ke CartItemModel agar field requestQty terbaca dengan aman
          CartItemModel cartItem = item as CartItemModel;
          
          await txn.insert('transaction_items', {
            'transaction_id': tId, 
            'product_id': cartItem.productId, 
            'product_name': cartItem.productName,
            'product_type': cartItem.productType, 
            'quantity': cartItem.quantity, 
            'request_qty': cartItem.requestQty,
            'unit_type': cartItem.unitType,
            'capital_price': cartItem.capitalPrice, 
            'sell_price': cartItem.sellPrice
          });
          
          await txn.rawUpdate('UPDATE products SET stock = stock - ? WHERE id = ?', [cartItem.quantity, cartItem.productId]);
        }
        return tId;
      });
    } catch (e) { return -1; }
  }

  Future<int> getNextQueueNumber() async {
    final db = await instance.database;
    String todayStart = DateFormat('yyyy-MM-dd').format(DateTime.now()) + " 00:00:00";
    String todayEnd = DateFormat('yyyy-MM-dd').format(DateTime.now()) + " 23:59:59";
    final result = await db.rawQuery("SELECT MAX(queue_number) as max_q FROM transactions WHERE transaction_date BETWEEN ? AND ?", [todayStart, todayEnd]);
    return ((result.first['max_q'] as int?) ?? 0) + 1;
  }

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

  // --- REVISI BUG FIX: STOK AWAL BENAR ---
  Future<void> updateStockQuick(int id, double newStock, int expense) async {
    final db = await instance.database;
    final old = await db.query('products', where: 'id = ?', whereArgs: [id]);
    if(old.isNotEmpty) {
      double oldStk = (old.first['stock'] as int).toDouble(); // AMBIL STOK LAMA
      double add = newStock - oldStk;
      
      // 1. UPDATE DB DULUAN (Supaya data konsisten)
      await db.update('products', {'stock': newStock.toInt()}, where: 'id = ?', whereArgs: [id]);

      // 2. BARU CATAT LOG
      if(add > 0) {
        int modal = (expense / add).round();
        if(expense == 0) modal = old.first['buy_price_unit'] as int;
        
        // KIRIM oldStk SEBAGAI manualPrevStock
        await addStockLog(id, old.first['type'] as String, add, modal, "Tambah Cepat", manualPrevStock: oldStk);
      }
    }
  }
  
  // --- REVISI: TERIMA PARAMETER manualPrevStock ---
  Future<void> addStockLog(int pid, String type, double qty, int modal, String note, {double? manualPrevStock}) async {
    final db = await instance.database;
    String dateNow = DateFormat('yyyy-MM-dd HH:mm:ss').format(DateTime.now());
    
    double prevStock = 0;

    if (manualPrevStock != null) {
      // JIKA DIKIRIM MANUAL, GUNAKAN LANGSUNG (PASTI BENAR)
      prevStock = manualPrevStock;
    } else {
      // FALLBACK (JIKA TIDAK DIKIRIM MANUAL) - Hitung Mundur
      // Asumsi: Fungsi ini dipanggil SETELAH update stok produk
      final productRes = await db.query('products', columns: ['stock'], where: 'id = ?', whereArgs: [pid]);
      double currentStock = 0;
      if (productRes.isNotEmpty) {
        currentStock = (productRes.first['stock'] as int).toDouble();
      }
      prevStock = currentStock - qty;
    }

    await db.insert('stock_logs', {
      'product_id': pid, 
      'product_type': type, 
      'quantity_added': qty, 
      'previous_stock': prevStock, 
      'capital_price': modal, 
      'date': dateNow, 
      'note': note
    });
  }
}