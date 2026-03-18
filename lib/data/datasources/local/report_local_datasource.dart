import '../../../helpers/database_helper.dart';

class ReportLocalDataSource {
  final DatabaseHelper _dbHelper = DatabaseHelper.instance;

  Future<List<Map<String, dynamic>>> getSoldItemsDetail({required String startDate, required String endDate}) async {
    final db = await _dbHelper.database;
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
    final db = await _dbHelper.database;
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

  Future<List<Map<String, dynamic>>> getCompleteReportData({required String startDate, required String endDate}) async {
    final db = await _dbHelper.database;
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
    final db = await _dbHelper.database;
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
}