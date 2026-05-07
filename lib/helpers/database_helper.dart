import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

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
      version: 6, // NAIK KE VERSI 6 (Auto-Upgrade Drag & Drop)
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
        pack_content INTEGER,
        modal_cair REAL DEFAULT 0,
        order_index INTEGER DEFAULT 0 -- KOLOM BARU UNTUK URUTAN DRAG & DROP
      )
    ''');

    await db.execute('''
      CREATE TABLE transactions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        total_price INTEGER,
        operational_cost INTEGER,
        discount INTEGER DEFAULT 0, 
        customer_name TEXT,
        customer_phone TEXT,
        customer_address TEXT,
        payment_method TEXT,
        payment_status TEXT,
        queue_number INTEGER, 
        transaction_date TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE gas_expenses (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        description TEXT,
        amount INTEGER,
        date TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE stock_logs (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        product_id INTEGER,
        type TEXT,
        quantity INTEGER,
        price INTEGER,
        note TEXT,
        date TEXT
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
      CREATE TABLE debt_payments (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        transaction_id INTEGER,
        amount_paid INTEGER,
        payment_date TEXT,
        note TEXT
      )
    ''');

    await db.execute('CREATE TABLE settings (key TEXT PRIMARY KEY, value TEXT)');
    await db.execute('CREATE TABLE customers (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT UNIQUE, phone TEXT, address TEXT)');
  }

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
      await db.execute('ALTER TABLE customers ADD COLUMN phone TEXT');
      await db.execute('ALTER TABLE customers ADD COLUMN address TEXT');
      await db.execute('ALTER TABLE transactions ADD COLUMN customer_phone TEXT');
      await db.execute('ALTER TABLE transactions ADD COLUMN customer_address TEXT');
    }
    if (oldVersion < 6) {
      // MIGRASI KOLOM URUTAN DRAG & DROP
      await db.execute('ALTER TABLE products ADD COLUMN order_index INTEGER DEFAULT 0');
    }
  }
}