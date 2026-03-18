import 'package:intl/intl.dart';
import '../../../helpers/database_helper.dart';

class DebtLocalDataSource {
  final DatabaseHelper _dbHelper = DatabaseHelper.instance;

  Future<List<Map<String, dynamic>>> getAllDebtHistory({
    String? startDate,
    String? endDate,
  }) async {
    final db = await _dbHelper.database;
    String whereClause = 'payment_status = ?';
    List<dynamic> args = ['Belum Lunas'];

    if (startDate != null && endDate != null) {
      whereClause += ' AND transaction_date BETWEEN ? AND ?';
      args.add("$startDate 00:00:00");
      args.add("$endDate 23:59:59");
    }

    return await db.query(
      'transactions',
      where: whereClause,
      whereArgs: args,
      orderBy: 'transaction_date DESC',
    );
  }

  Future<List<Map<String, dynamic>>> getDebtPayments(int transactionId) async {
    final db = await _dbHelper.database;
    return await db.query(
      'debt_payments',
      where: 'transaction_id = ?',
      whereArgs: [transactionId],
      orderBy: 'payment_date ASC',
    );
  }

  Future<void> addDebtPayment(int transId, int amount, String note) async {
    final db = await _dbHelper.database;
    String dateNow = DateFormat('yyyy-MM-dd HH:mm:ss').format(DateTime.now());

    await db.transaction((txn) async {
      await txn.insert('debt_payments', {
        'transaction_id': transId,
        'amount_paid': amount,
        'payment_date': dateNow,
        'note': note,
      });

      final res = await txn.rawQuery(
        'SELECT SUM(amount_paid) as total FROM debt_payments WHERE transaction_id = ?',
        [transId],
      );
      int alreadyPaid = (res.first['total'] as int?) ?? 0;

      final trans = await txn.query(
        'transactions',
        columns: ['total_price'],
        where: 'id = ?',
        whereArgs: [transId],
      );

      if (trans.isNotEmpty) {
        int totalPrice = (trans.first['total_price'] as int?) ?? 0;

        if (alreadyPaid >= totalPrice) {
          await txn.update(
            'transactions',
            {'payment_status': 'Lunas'},
            where: 'id = ?',
            whereArgs: [transId],
          );
        }
      }
    });
  }

  Future<int> getTotalPiutangAllTime() async {
    final db = await _dbHelper.database;
    final resTrans = await db.rawQuery(
      "SELECT SUM(total_price) as total FROM transactions WHERE payment_status = 'Belum Lunas'",
    );
    int totalHutang = (resTrans.first['total'] as int?) ?? 0;

    final resPaid = await db.rawQuery(
      "SELECT SUM(p.amount_paid) as total FROM debt_payments p JOIN transactions t ON p.transaction_id = t.id WHERE t.payment_status = 'Belum Lunas'",
    );
    int totalSudahDibayar = (resPaid.first['total'] as int?) ?? 0;

    return totalHutang - totalSudahDibayar;
  }

  Future<List<Map<String, dynamic>>> getActiveDebtsWithDetails() async {
    final db = await _dbHelper.database;
    final query = '''
      SELECT 
        t.id, t.transaction_date, t.customer_name, t.total_price, t.discount,
        (
          SELECT SUM(dp.amount_paid) 
          FROM debt_payments dp 
          WHERE dp.transaction_id = t.id
        ) as total_dicicil
      FROM transactions t
      WHERE t.payment_status = 'Belum Lunas'
      ORDER BY t.transaction_date DESC
    ''';
    return await db.rawQuery(query);
  }

  Future<List<Map<String, dynamic>>> getDebtReport({
    required String status,
    required String startDate,
    required String endDate,
  }) async {
    final db = await _dbHelper.database;
    String start = "$startDate 00:00:00";
    String end = "$endDate 23:59:59";

    String whereClause =
        'payment_status = ? AND transaction_date BETWEEN ? AND ?';
    if (status == 'Lunas') {
      whereClause += " AND payment_method = 'HUTANG'";
    }

    return await db.query(
      'transactions',
      where: whereClause,
      whereArgs: [status, start, end],
      orderBy: 'transaction_date DESC',
    );
  }
}
