import '../../../helpers/database_helper.dart';

class ProfitLocalDataSource {
  final DatabaseHelper _dbHelper = DatabaseHelper.instance;

  // Query UNION ALL dipindah murni ke sini
  Future<List<Map<String, dynamic>>> getProfitAndExpensesData(String startDate, String endDate) async {
    final db = await _dbHelper.database;
    
    return await db.rawQuery('''
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
  }
}