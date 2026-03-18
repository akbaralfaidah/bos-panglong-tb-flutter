import '../../../helpers/database_helper.dart';

class DashboardLocalDataSource {
  final DatabaseHelper _dbHelper = DatabaseHelper.instance;

  Future<double> getTodayOmset(String today) async {
    final db = await _dbHelper.database;
    var res = await db.rawQuery("SELECT SUM(total_price) as omset FROM transactions WHERE substr(transaction_date, 1, 10) = ? AND payment_status = 'Lunas'", [today]);
    return _safeDouble(res.first['omset']);
  }

  Future<double> getTodayGrossProfit(String today) async {
    final db = await _dbHelper.database;
    var res = await db.rawQuery("SELECT SUM((ti.sell_price - ti.capital_price) * ti.quantity) as profit FROM transaction_items ti JOIN transactions t ON ti.transaction_id = t.id WHERE substr(t.transaction_date, 1, 10) = ? AND t.payment_status = 'Lunas'", [today]);
    return _safeDouble(res.first['profit']);
  }

  Future<double> getTodayDiscount(String today) async {
    final db = await _dbHelper.database;
    var res = await db.rawQuery("SELECT SUM(discount) as diskon FROM transactions WHERE substr(transaction_date, 1, 10) = ? AND payment_status = 'Lunas'", [today]);
    return _safeDouble(res.first['diskon']);
  }

  Future<double> getTodayGasIncome(String today) async {
    final db = await _dbHelper.database;
    var res = await db.rawQuery("SELECT SUM(operational_cost) as bensin_masuk FROM transactions WHERE substr(transaction_date, 1, 10) = ?", [today]);
    return _safeDouble(res.first['bensin_masuk']);
  }

  Future<double> getTodayGasExpense(String today) async {
    final db = await _dbHelper.database;
    var res = await db.rawQuery("SELECT SUM(amount) as bensin_keluar FROM gas_expenses WHERE substr(date, 1, 10) = ?", [today]);
    return _safeDouble(res.first['bensin_keluar']);
  }

  Future<double> getTotalDebt() async {
    final db = await _dbHelper.database;
    var res = await db.rawQuery('''
      SELECT SUM(t.total_price - IFNULL(dp.total_paid, 0)) as sisa_hutang
      FROM transactions t
      LEFT JOIN (
        SELECT transaction_id, SUM(amount_paid) as total_paid
        FROM debt_payments
        GROUP BY transaction_id
      ) dp ON t.id = dp.transaction_id
      WHERE t.payment_status != 'Lunas'
    ''');
    return _safeDouble(res.first['sisa_hutang']);
  }

  Future<double> getTodayStockExpense(String today) async {
    final db = await _dbHelper.database;
    try {
      var res = await db.rawQuery("SELECT SUM(quantity * price) as modal FROM stock_logs WHERE substr(date, 1, 10) = ?", [today]);
      return _safeDouble(res.first['modal']);
    } catch (e) {
      // Fallback untuk versi database lama lu
      var resOld = await db.rawQuery("SELECT SUM(quantity_added * capital_price) as modal FROM stock_logs WHERE substr(date, 1, 10) = ?", [today]);
      return _safeDouble(resOld.first['modal']);
    }
  }

  double _safeDouble(dynamic val) {
    if (val == null) return 0.0;
    if (val is num) return val.toDouble();
    return double.tryParse(val.toString()) ?? 0.0;
  }

  Future<double> getTotalGasBalance() async {
    final db = await _dbHelper.database;
    var resMasuk = await db.rawQuery("SELECT SUM(operational_cost) as masuk FROM transactions");
    var resKeluar = await db.rawQuery("SELECT SUM(amount) as keluar FROM gas_expenses");
    
    double masuk = _safeDouble(resMasuk.first['masuk']);
    double keluar = _safeDouble(resKeluar.first['keluar']);
    return masuk - keluar;
  }
}