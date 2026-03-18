import 'package:sqflite/sqflite.dart';
import '../../../helpers/database_helper.dart';

class CoreLocalDataSource {
  final DatabaseHelper _dbHelper = DatabaseHelper.instance;

  Future<List<Map<String, dynamic>>> getTransactionsByCustomer(String name) async {
    final db = await _dbHelper.database;
    return await db.query(
      'transactions',
      where: 'customer_name LIKE ?',
      whereArgs: ['$name%'], 
      orderBy: 'transaction_date DESC'
    );
  }

  Future<void> saveSetting(String k, String v) async {
    final db = await _dbHelper.database;
    await db.insert('settings', {'key': k, 'value': v}, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<String?> getSetting(String k) async {
    final db = await _dbHelper.database;
    final m = await db.query('settings', where: 'key = ?', whereArgs: [k]);
    return m.isNotEmpty ? m.first['value'] as String : null;
  }

  Future<void> saveCustomer(String name) async {
    final db = await _dbHelper.database;
    await db.rawInsert('INSERT OR IGNORE INTO customers(name) VALUES(?)', [name]);
  }

  Future<List<String>> getCustomers() async {
    final db = await _dbHelper.database;
    final r = await db.query('customers', orderBy: 'name ASC');
    return r.map((e) => e['name'] as String).toList();
  }
}