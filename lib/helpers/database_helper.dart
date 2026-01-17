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
      // VERSI 6 (Fitur Manajemen Bensin)
      version: 6, 
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

    await db.execute('''
      CREATE TABLE stock_logs (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        product_id INTEGER,
        product_type TEXT,
        quantity_added REAL,
        previous_stock REAL DEFAULT 0,
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

    // TABEL PENGELUARAN (BENSIN DLL)
    await db.execute('''
      CREATE TABLE expenses (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        date TEXT,
        amount INTEGER,
        note TEXT,
        type TEXT
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
    if (oldVersion < 5) {
      await db.execute('ALTER TABLE stock_logs ADD COLUMN previous_stock REAL DEFAULT 0');
    }
    if (oldVersion < 6) {
      await db.execute('''
        CREATE TABLE expenses (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          date TEXT,
          amount INTEGER,
          note TEXT,
          type TEXT
        )
      ''');
    }
  }

  // ==========================================
  // HELPER: SMART ROUNDING
  // ==========================================
  int _smartRound(int value) {
    if (value == 0) return 0;
    if (value.abs() < 500) return value;
    double val = value.toDouble();
    return (val / 500).round() * 500;
  }

  // ==========================================
  // FITUR BARU: UNIVERSAL HISTORY (GABUNGAN)
  // ==========================================
  
  Future<List<Map<String, dynamic>>> getUniversalHistory({String? keyword}) async {
    final db = await instance.database;
    List<Map<String, dynamic>> combined = [];

    // 1. AMBIL TRANSAKSI (PENJUALAN)
    // Keyword bisa ID Transaksi atau Nama Customer
    String transWhere = "";
    List<dynamic> transArgs = [];
    
    if (keyword != null && keyword.isNotEmpty) {
      // Cek apakah keyword angka (ID) atau teks (Nama)
      if (int.tryParse(keyword) != null) {
        transWhere = "WHERE id = ?";
        transArgs = [keyword];
      } else {
        transWhere = "WHERE customer_name LIKE ?";
        transArgs = ['%$keyword%'];
      }
    }

    final trans = await db.rawQuery("SELECT * FROM transactions $transWhere", transArgs);
    for (var t in trans) {
      combined.add({
        'raw_id': t['id'], // ID Asli Tabel
        'display_id': "#${t['id']}", 
        'date': t['transaction_date'],
        'title': "Penjualan: ${t['customer_name']}",
        'subtitle': "Total Nota (Termasuk Bensin)",
        'amount': t['total_price'], // Total Tagihan
        'category': 'TRANSACTION',
        'color_code': 1, // 1: Hijau (Masuk)
        'extra_info': t['payment_status'] // Lunas/Belum
      });
    }

    // JIKA SEDANG CARI ID TRANSAKSI, TIDAK PERLU LOAD STOK & PENGELUARAN
    // KECUALI keyword kosong (Tampilkan semua)
    bool isSearchId = (keyword != null && int.tryParse(keyword) != null);

    if (!isSearchId) {
      // 2. AMBIL STOK MASUK (PENGELUARAN MODAL)
      final stocks = await db.rawQuery('''
        SELECT s.*, p.name as product_name 
        FROM stock_logs s
        LEFT JOIN products p ON s.product_id = p.id
        WHERE s.quantity_added > 0
      ''');
      
      for (var s in stocks) {
        double qty = (s['quantity_added'] as num).toDouble();
        double modal = (s['capital_price'] as num).toDouble();
        int totalModal = (qty * modal).toInt();

        combined.add({
          'raw_id': s['id'],
          'display_id': "STOK",
          'date': s['date'],
          'title': "Stok Masuk: ${s['product_name']}",
          'subtitle': "${s['note']}",
          'amount': totalModal,
          'category': 'STOCK_IN',
          'color_code': 2, // 2: Merah/Oranye (Keluar Modal)
          'extra_info': "-"
        });
      }

      // 3. AMBIL PENGELUARAN BENSIN (SPBU)
      final expenses = await db.query('expenses', where: "type='FUEL'");
      for (var e in expenses) {
        combined.add({
          'raw_id': e['id'],
          'display_id': "BBM",
          'date': e['date'],
          'title': "Pengeluaran SPBU",
          'subtitle': e['note'],
          'amount': e['amount'],
          'category': 'EXPENSE_FUEL',
          'color_code': 3, // 3: Merah (Keluar Operasional)
          'extra_info': "-"
        });
      }
    }

    // SORTING BERDASARKAN TANGGAL TERBARU
    combined.sort((a, b) {
      DateTime dA = DateTime.parse(a['date']);
      DateTime dB = DateTime.parse(b['date']);
      return dB.compareTo(dA); // Descending
    });

    return combined;
  }

  // ==========================================
  // FITUR DASHBOARD & LAINNYA
  // ==========================================

  Future<int> getRealNetProfit({required String startDate, required String endDate}) async {
    final db = await instance.database;
    String start = "$startDate 00:00:00";
    String end = "$endDate 23:59:59";

    final resSales = await db.rawQuery('''
      SELECT SUM((ti.sell_price - ti.capital_price) * ti.quantity) as profit
      FROM transaction_items ti
      JOIN transactions t ON ti.transaction_id = t.id
      WHERE t.transaction_date BETWEEN ? AND ?
    ''', [start, end]);
    int salesProfit = (resSales.first['profit'] as int?) ?? 0;

    final resOp = await db.rawQuery('''
      SELECT SUM(operational_cost) as total
      FROM transactions
      WHERE transaction_date BETWEEN ? AND ?
    ''', [start, end]);
    int shippingIncome = (resOp.first['total'] as int?) ?? 0;

    final resExp = await db.rawQuery('''
      SELECT SUM(amount) as total
      FROM expenses
      WHERE date BETWEEN ? AND ?
    ''', [start, end]);
    int fuelExpense = (resExp.first['total'] as int?) ?? 0;

    final resDisc = await db.rawQuery('''
      SELECT SUM(discount) as total
      FROM transactions
      WHERE transaction_date BETWEEN ? AND ?
    ''', [start, end]);
    int totalDiscount = (resDisc.first['total'] as int?) ?? 0;

    int tradeProfit = salesProfit - totalDiscount;

    int fuelDeficit = 0;
    if (fuelExpense > shippingIncome) {
      fuelDeficit = fuelExpense - shippingIncome;
    } 

    int rawProfit = tradeProfit - fuelDeficit;
    return _smartRound(rawProfit); 
  }

  Future<List<Map<String, dynamic>>> getMergedProfitHistory({required String startDate, required String endDate}) async {
    final db = await instance.database;
    String start = "$startDate 00:00:00";
    String end = "$endDate 23:59:59";

    final List<Map<String, dynamic>> transactions = await db.rawQuery('''
      SELECT 
        t.id,
        t.transaction_date as date,
        t.customer_name as title,
        'IN' as type,
        t.operational_cost,
        t.discount,
        SUM((ti.sell_price - ti.capital_price) * ti.quantity) as gross_profit
      FROM transactions t
      JOIN transaction_items ti ON t.id = ti.transaction_id
      WHERE t.transaction_date BETWEEN ? AND ?
      GROUP BY t.id
    ''', [start, end]);

    final List<Map<String, dynamic>> expenses = await db.rawQuery('''
      SELECT 
        id,
        date,
        note as title,
        'OUT' as type,
        amount
      FROM expenses
      WHERE date BETWEEN ? AND ?
    ''', [start, end]);

    List<Map<String, dynamic>> merged = [];

    for (var t in transactions) {
      int gross = (t['gross_profit'] as int?) ?? 0;
      int op = (t['operational_cost'] as int?) ?? 0;
      int disc = (t['discount'] as int?) ?? 0;
      
      int netTradeProfit = gross - disc;

      merged.add({
        'id': t['id'],
        'date': t['date'],
        'title': t['title'], 
        'subtitle': "Penjualan #${t['id']}",
        'type': 'IN',
        'amount': _smartRound(netTradeProfit), 
        'extra_fuel_income': op,  
      });
    }

    for (var e in expenses) {
      merged.add({
        'id': e['id'],
        'date': e['date'],
        'title': e['title'] ?? 'Pengeluaran',
        'subtitle': 'Operasional',
        'type': 'OUT',
        'amount': (e['amount'] as int),
      });
    }

    merged.sort((a, b) => DateTime.parse(b['date']).compareTo(DateTime.parse(a['date'])));

    return merged;
  }

  Future<int> addFuelExpense(int amount, String note, String date) async {
    final db = await instance.database;
    return await db.insert('expenses', {
      'date': date,
      'amount': amount,
      'note': note,
      'type': 'FUEL'
    });
  }

  Future<Map<String, dynamic>> getFuelReport({required String startDate, required String endDate}) async {
    final db = await instance.database;
    String start = "$startDate 00:00:00";
    String end = "$endDate 23:59:59";

    final resIncome = await db.rawQuery(
      "SELECT SUM(operational_cost) as total FROM transactions WHERE transaction_date BETWEEN ? AND ?", 
      [start, end]
    );
    int totalIncome = (resIncome.first['total'] as int?) ?? 0;

    final resExpense = await db.rawQuery(
      "SELECT SUM(amount) as total FROM expenses WHERE type='FUEL' AND date BETWEEN ? AND ?",
      [start, end]
    );
    int totalExpense = (resExpense.first['total'] as int?) ?? 0;

    final listExpenses = await db.query(
      'expenses',
      where: "type='FUEL' AND date BETWEEN ? AND ?",
      whereArgs: [start, end],
      orderBy: "date DESC"
    );

    return {
      'total_income': totalIncome,
      'total_expense': totalExpense,
      'history': listExpenses
    };
  }

  Future<int> deleteExpense(int id) async {
    final db = await instance.database;
    return await db.delete('expenses', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<Map<String, dynamic>>> getTopProducts({required String startDate, required String endDate}) async {
    final db = await instance.database;
    String start = "$startDate 00:00:00";
    String end = "$endDate 23:59:59";

    return await db.rawQuery('''
      SELECT 
        p.name as product_name,
        p.dimensions,
        p.wood_class,
        p.source,
        SUM(i.quantity) as total_qty,
        CASE 
          WHEN p.type IN ('KAYU', 'RENG', 'BULAT') THEN 'Batang'
          ELSE 'Pcs'
        END as unit_type
      FROM transaction_items i
      JOIN transactions t ON i.transaction_id = t.id
      LEFT JOIN products p ON i.product_id = p.id
      WHERE t.transaction_date BETWEEN ? AND ?
      GROUP BY i.product_id
      ORDER BY total_qty DESC
      LIMIT 5
    ''', [start, end]);
  }

  Future<List<Map<String, dynamic>>> getTransactionsByCustomer(String name) async {
    final db = await instance.database;
    return await db.query(
      'transactions',
      where: 'customer_name LIKE ?',
      whereArgs: ['$name%'], 
      orderBy: 'transaction_date DESC'
    );
  }

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

  Future<void> updateStockQuick(int id, double newStock, int expense) async {
    final db = await instance.database;
    final old = await db.query('products', where: 'id = ?', whereArgs: [id]);
    if(old.isNotEmpty) {
      double oldStk = (old.first['stock'] as int).toDouble(); 
      double add = newStock - oldStk;
      
      await db.update('products', {'stock': newStock.toInt()}, where: 'id = ?', whereArgs: [id]);

      if(add > 0) {
        int modal = (expense / add).round();
        if(expense == 0) modal = old.first['buy_price_unit'] as int;
        await addStockLog(id, old.first['type'] as String, add, modal, "Tambah Cepat", manualPrevStock: oldStk);
      }
    }
  }
  
  Future<void> addStockLog(int pid, String type, double qty, int modal, String note, {double? manualPrevStock}) async {
    final db = await instance.database;
    String dateNow = DateFormat('yyyy-MM-dd HH:mm:ss').format(DateTime.now());
    
    double prevStock = 0;

    if (manualPrevStock != null) {
      prevStock = manualPrevStock;
    } else {
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