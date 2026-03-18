import '../../../helpers/database_helper.dart';

class ReportLocalDataSource {
  final DatabaseHelper _dbHelper = DatabaseHelper.instance;

  Future<List<Map<String, dynamic>>> getSoldItemsDetail({
    required String startDate,
    required String endDate,
  }) async {
    final db = await _dbHelper.database;
    String start = "$startDate 00:00:00";
    String end = "$endDate 23:59:59";

    return await db.rawQuery(
      '''
      SELECT i.*, t.transaction_date, t.customer_name, t.id as trans_id 
      FROM transaction_items i 
      JOIN transactions t ON i.transaction_id = t.id 
      WHERE t.transaction_date BETWEEN ? AND ? 
      ORDER BY t.transaction_date DESC
    ''',
      [start, end],
    );
  }

  Future<List<Map<String, dynamic>>> getStockLogsDetail({
    required String startDate,
    required String endDate,
  }) async {
    final db = await _dbHelper.database;
    String start = "$startDate 00:00:00";
    String end = "$endDate 23:59:59";

    return await db.rawQuery(
      '''
      SELECT s.*, p.name as product_name 
      FROM stock_logs s 
      LEFT JOIN products p ON s.product_id = p.id 
      WHERE s.date BETWEEN ? AND ? AND s.quantity_added > 0
      ORDER BY s.date DESC
    ''',
      [start, end],
    );
  }

  Future<List<Map<String, dynamic>>> getCompleteReportData({
    required String startDate,
    required String endDate,
  }) async {
    final db = await _dbHelper.database;
    String start = "$startDate 00:00:00";
    String end = "$endDate 23:59:59";

    return await db.rawQuery(
      '''
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
    ''',
      [start, end],
    );
  }

  Future<List<Map<String, dynamic>>> getTopProducts({
    required String startDate,
    required String endDate,
  }) async {
    final db = await _dbHelper.database;
    String start = "$startDate 00:00:00";
    String end = "$endDate 23:59:59";

    return await db.rawQuery(
      '''
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
    ''',
      [start, end],
    );
  }

  // =====================================================================
  // FUNGSI REFACTORING DARI REPORT CONTROLLER (FINAL BOSS)
  // =====================================================================

  Future<Map<String, double>> getFinancialStatsData(
    String startDate,
    String endDate,
  ) async {
    final db = await _dbHelper.database;

    final resTrans = await db.rawQuery(
      '''
      SELECT SUM(total_price) as omset, SUM(operational_cost) as bensin
      FROM transactions
      WHERE payment_status = 'Lunas' AND date(transaction_date) BETWEEN ? AND ?
    ''',
      [startDate, endDate],
    );

    final resModal = await db.rawQuery(
      '''
      SELECT SUM(ti.quantity * ti.capital_price) as total_modal
      FROM transaction_items ti
      JOIN transactions t ON t.id = ti.transaction_id
      WHERE t.payment_status = 'Lunas' AND date(t.transaction_date) BETWEEN ? AND ?
    ''',
      [startDate, endDate],
    );

    double omset = (resTrans.first['omset'] as num?)?.toDouble() ?? 0.0;
    double bensin = (resTrans.first['bensin'] as num?)?.toDouble() ?? 0.0;
    double modal = (resModal.first['total_modal'] as num?)?.toDouble() ?? 0.0;

    return {
      'omset': omset,
      'bensin': bensin,
      'modal': modal,
      'profit': omset - bensin - modal,
    };
  }

  Future<Map<String, dynamic>> getDashboardAnalyticsData(
    String typeCondition,
    String sixMonthsStr,
  ) async {
    final db = await _dbHelper.database;

    final products = await db.query('products');

    final allProducts = await db.rawQuery('''
      SELECT ti.product_name, SUM(ti.quantity) as qty 
      FROM transaction_items ti
      JOIN transactions t ON t.id = ti.transaction_id
      WHERE t.payment_status = 'Lunas' $typeCondition
      GROUP BY ti.product_name
      ORDER BY qty DESC
    ''');

    final trans = await db.rawQuery(
      '''
      SELECT t.transaction_date, t.total_price, t.operational_cost, 
             IFNULL(SUM(ti.quantity * ti.capital_price), 0) as total_modal
      FROM transactions t
      LEFT JOIN transaction_items ti ON ti.transaction_id = t.id
      WHERE t.payment_status = 'Lunas' AND t.transaction_date >= ?
      GROUP BY t.id
    ''',
      [sixMonthsStr],
    );

    return {'products': products, 'allProducts': allProducts, 'trans': trans};
  }

  Future<List<Map<String, dynamic>>> getCustomerCRMData() async {
    final db = await _dbHelper.database;
    final customers = await db.query('customers', orderBy: 'name ASC');
    List<Map<String, dynamic>> result = [];

    for (var c in customers) {
      String name = c['name'].toString();
      if (name == 'Pelanggan Umum') continue;

      final transLunas = await db.rawQuery(
        "SELECT SUM(total_price) as total FROM transactions WHERE customer_name = ? AND payment_status = 'Lunas'",
        [name],
      );
      int spent = ((transLunas.first['total'] as int?) ?? 0);

      final transHutang = await db.rawQuery(
        "SELECT id, total_price FROM transactions WHERE customer_name = ? AND payment_status != 'Lunas'",
        [name],
      );
      int hutang = 0;
      for (var th in transHutang) {
        int id = th['id'] as int;
        int tp = th['total_price'] as int;
        final paid = await db.rawQuery(
          "SELECT SUM(amount_paid) as total FROM debt_payments WHERE transaction_id = ?",
          [id],
        );
        int p = ((paid.first['total'] as int?) ?? 0);
        hutang += (tp - p);
      }

      result.add({
        'id': c['id'],
        'name': name,
        'phone': c['phone'] ?? '',
        'address': c['address'] ?? '',
        'total_spent': spent,
        'total_debt': hutang,
      });
    }

    result.sort(
      (a, b) => (b['total_spent'] as int).compareTo(a['total_spent'] as int),
    );
    return result;
  }

  Future<List<Map<String, dynamic>>> getTransactionsByCustomer(
    String customerName,
  ) async {
    final db = await _dbHelper.database;
    return await db.query(
      'transactions',
      where: 'customer_name = ?',
      whereArgs: [customerName],
      orderBy: 'transaction_date DESC',
    );
  }
}
