import 'package:intl/intl.dart';
import '../helpers/database_helper.dart';

class ProfitHistoryController {
  Future<List<Map<String, dynamic>>> getProfitAndExpenses(String filterDate) async {
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

    // ========================================================================
    // FIX FATAL: Rumus LABA sekarang dikurangi dengan t.discount secara otomatis!
    // (SUM((ti.sell_price - ti.capital_price) * ti.quantity) - t.discount)
    // ========================================================================
    final List<Map<String, dynamic>> res = await db.rawQuery('''
      SELECT 
        t.id as ref_id, 
        t.transaction_date as date, 
        t.customer_name as title, 
        'Profit Penjualan (INV-' || t.id || ')' as subtitle, 
        (SUM((ti.sell_price - ti.capital_price) * ti.quantity) - t.discount) as amount, 
        'LABA' as type 
      FROM transactions t
      JOIN transaction_items ti ON t.id = ti.transaction_id
      WHERE t.payment_status = 'Lunas' AND substr(t.transaction_date, 1, 10) BETWEEN ? AND ?
      GROUP BY t.id

      UNION ALL

      SELECT 
        id as ref_id, 
        date, 
        'Biaya Operasional' as title, 
        description as subtitle, 
        amount, 
        'PENGELUARAN' as type 
      FROM gas_expenses
      WHERE substr(date, 1, 10) BETWEEN ? AND ?

      ORDER BY date DESC
    ''', [startDate, endDate, startDate, endDate]);

    return res;
  }
}