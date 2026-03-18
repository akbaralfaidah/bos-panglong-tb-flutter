import 'package:intl/intl.dart';
import '../../../helpers/database_helper.dart';
import '../../../models/product.dart';

class TransactionLocalDataSource {
  final DatabaseHelper _dbHelper = DatabaseHelper.instance;

  Future<int> createTransaction({
    required int totalPrice,
    required int operationalCost,
    required String customerName,
    required String paymentMethod,
    required String paymentStatus,
    required int queueNumber,
    required List<dynamic> items,
    String? transactionDate,
    int discount = 0,
  }) async {
    final db = await _dbHelper.database;
    String dateNow =
        transactionDate ??
        DateFormat('yyyy-MM-dd HH:mm:ss').format(DateTime.now());

    try {
      return await db.transaction((txn) async {
        int tId = await txn.insert('transactions', {
          'total_price': totalPrice,
          'operational_cost': operationalCost,
          'discount': discount,
          'customer_name': customerName,
          'payment_method': paymentMethod,
          'payment_status': paymentStatus,
          'queue_number': queueNumber,
          'transaction_date': dateNow,
        });

        for (var item in items) {
          // Cast ke CartItemModel
          CartItemModel cartItem = item as CartItemModel;

          await txn.insert('transaction_items', {
            'transaction_id': tId,
            'product_id': cartItem.productId,
            'product_name': cartItem.productName,
            'product_type': cartItem.productType,
            'quantity': cartItem.quantity,
            'request_qty': cartItem.requestQty,
            'unit_type': cartItem.unitType,
            'capital_price': cartItem.capitalPrice,
            'sell_price': cartItem.sellPrice,
          });

          await txn.rawUpdate(
            'UPDATE products SET stock = stock - ? WHERE id = ?',
            [cartItem.quantity, cartItem.productId],
          );
        }
        return tId;
      });
    } catch (e) {
      return -1;
    }
  }

  Future<List<Map<String, dynamic>>> getTransactionHistory({
    required String startDate,
    required String endDate,
  }) async {
    final db = await _dbHelper.database;
    String start = "$startDate 00:00:00";
    String end = "$endDate 23:59:59";

    return await db.query(
      'transactions',
      where: 'transaction_date BETWEEN ? AND ?',
      whereArgs: [start, end],
      orderBy: 'transaction_date DESC',
    );
  }

  Future<List<Map<String, dynamic>>> getTransactionItems(
    int transactionId,
  ) async {
    final db = await _dbHelper.database;
    return await db.query(
      'transaction_items',
      where: 'transaction_id = ?',
      whereArgs: [transactionId],
    );
  }

  Future<void> updateTransactionStatus(int id, String status) async {
    final db = await _dbHelper.database;
    await db.update(
      'transactions',
      {'payment_status': status},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<List<Map<String, dynamic>>> getFilteredTransactionHistory({
    required String statusCondition,
    required String startDate,
    required String endDate,
  }) async {
    final db = await _dbHelper.database;
    return await db.rawQuery(
      '''
      SELECT * FROM transactions
      WHERE $statusCondition AND substr(transaction_date, 1, 10) BETWEEN ? AND ?
      ORDER BY id DESC
    ''',
      [startDate, endDate],
    );
  }

  Future<int> getNextQueueNumber() async {
    final db = await _dbHelper.database;
    String todayStart =
        DateFormat('yyyy-MM-dd').format(DateTime.now()) + " 00:00:00";
    String todayEnd =
        DateFormat('yyyy-MM-dd').format(DateTime.now()) + " 23:59:59";
    final result = await db.rawQuery(
      "SELECT MAX(queue_number) as max_q FROM transactions WHERE transaction_date BETWEEN ? AND ?",
      [todayStart, todayEnd],
    );
    return ((result.first['max_q'] as int?) ?? 0) + 1;
  }
}
