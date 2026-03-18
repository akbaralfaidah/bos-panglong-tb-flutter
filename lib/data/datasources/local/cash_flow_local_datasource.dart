import '../../../helpers/database_helper.dart';

class CashFlowLocalDataSource {
  final DatabaseHelper _dbHelper = DatabaseHelper.instance;

  Future<List<Map<String, dynamic>>> getAllTransactions() async {
    final db = await _dbHelper.database;
    return await db.query('transactions');
  }

  Future<List<Map<String, dynamic>>> getAllDebtPayments() async {
    final db = await _dbHelper.database;
    return await db.query('debt_payments');
  }

  Future<List<Map<String, dynamic>>> getAllStockLogsWithProducts() async {
    final db = await _dbHelper.database;
    return await db.rawQuery('''
      SELECT s.*, p.name as product_name, p.type as product_category 
      FROM stock_logs s 
      LEFT JOIN products p ON s.product_id = p.id
    ''');
  }

  Future<List<Map<String, dynamic>>> getAllGasExpenses() async {
    final db = await _dbHelper.database;
    return await db.query('gas_expenses');
  }

  Future<Map<String, dynamic>?> getTransactionById(int id) async {
    final db = await _dbHelper.database;
    final res = await db.query('transactions', where: 'id = ?', whereArgs: [id]);
    if (res.isNotEmpty) return res.first;
    return null;
  }
}