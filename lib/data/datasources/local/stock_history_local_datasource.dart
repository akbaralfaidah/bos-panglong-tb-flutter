import '../../../helpers/database_helper.dart';

class StockHistoryLocalDataSource {
  final DatabaseHelper _dbHelper = DatabaseHelper.instance;

  Future<List<Map<String, dynamic>>> getStockHistoryData(String typeCondition, String startDate, String endDate) async {
    final db = await _dbHelper.database;
    return await db.rawQuery('''
      SELECT s.*, p.name as product_name, p.wood_class, p.type as prod_type, p.stock as current_stock, p.dimensions, p.source 
      FROM stock_logs s
      JOIN products p ON s.product_id = p.id
      WHERE $typeCondition 
      AND substr(s.date, 1, 10) BETWEEN ? AND ?
      ORDER BY s.id DESC
    ''', [startDate, endDate]);
  }

  Future<List<Map<String, dynamic>>> getStockLogsByExactDate(String exactDate) async {
    final db = await _dbHelper.database;
    return await db.rawQuery('''
      SELECT s.*, p.name as product_name, p.wood_class, p.type as prod_type, p.dimensions, p.source 
      FROM stock_logs s
      JOIN products p ON s.product_id = p.id
      WHERE s.date = ?
    ''', [exactDate]);
  }
}