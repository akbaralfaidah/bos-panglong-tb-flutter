import 'package:intl/intl.dart';
import '../helpers/database_helper.dart';

class TransactionHistoryController {
  Future<List<Map<String, dynamic>>> getTransactions(String tabType, String filterDate) async {
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

    String statusCondition = tabType == 'LUNAS' ? "payment_status = 'Lunas'" : "payment_status != 'Lunas'";

    final List<Map<String, dynamic>> res = await db.rawQuery('''
      SELECT * FROM transactions
      WHERE $statusCondition AND substr(transaction_date, 1, 10) BETWEEN ? AND ?
      ORDER BY id DESC
    ''', [startDate, endDate]);

    return res;
  }
}