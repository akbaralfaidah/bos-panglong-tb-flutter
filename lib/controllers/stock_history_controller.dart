import 'package:intl/intl.dart';
import '../helpers/database_helper.dart';

class StockHistoryController {
  
  Future<List<Map<String, dynamic>>> getStockHistory(String tabType, String filterDate) async {
    final db = await DatabaseHelper.instance.database;
    
    DateTime now = DateTime.now();
    String startDate = '';
    String endDate = DateFormat('yyyy-MM-dd').format(now);

    if (filterDate == 'Hari Ini') {
      startDate = endDate;
    } else if (filterDate == 'Kemarin') {
      startDate = DateFormat('yyyy-MM-dd').format(now.subtract(const Duration(days: 1)));
      endDate = startDate;
    } else if (filterDate == '7 Hari') {
      startDate = DateFormat('yyyy-MM-dd').format(now.subtract(const Duration(days: 7)));
    } else if (filterDate == 'Bulan Ini') {
      startDate = DateFormat('yyyy-MM-01').format(now);
    } else {
      startDate = '2000-01-01'; 
    }

    String typeCondition = "p.type IN ('KAYU', 'RENG', 'BULAT')";
    if (tabType == 'BANGUNAN') {
      typeCondition = "p.type = 'BANGUNAN'";
    }

    final List<Map<String, dynamic>> res = await db.rawQuery('''
      SELECT s.*, p.name as product_name, p.wood_class, p.type as prod_type, p.stock as current_stock, p.dimensions, p.source 
      FROM stock_logs s
      JOIN products p ON s.product_id = p.id
      WHERE $typeCondition 
      AND substr(s.date, 1, 10) BETWEEN ? AND ?
      ORDER BY s.id DESC
    ''', [startDate, endDate]);

    return res;
  }

  // =================================================================
  // FUNGSI BARU: AMBIL SEMUA BARANG YANG DIKULAK PADA WAKTU BERSAMAAN
  // =================================================================
  Future<List<Map<String, dynamic>>> getStockLogsByExactDate(String exactDate) async {
    final db = await DatabaseHelper.instance.database;
    return await db.rawQuery('''
      SELECT s.*, p.name as product_name, p.wood_class, p.type as prod_type, p.dimensions, p.source 
      FROM stock_logs s
      JOIN products p ON s.product_id = p.id
      WHERE s.date = ?
    ''', [exactDate]);
  }
}