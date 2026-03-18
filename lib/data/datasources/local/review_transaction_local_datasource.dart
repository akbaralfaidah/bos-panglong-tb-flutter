import '../../../helpers/database_helper.dart';
import 'package:intl/intl.dart';

class ReviewTransactionLocalDataSource {
  final DatabaseHelper _dbHelper = DatabaseHelper.instance;

  Future<List<Map<String, dynamic>>> getCustomersData() async {
    final db = await _dbHelper.database;
    return await db.query('customers', orderBy: 'name ASC');
  }

  Future<Map<String, dynamic>> saveTransactionToDb({
    required List<Map<String, dynamic>> cartItems,
    required String customerName,
    required String customerPhone,
    required String customerAddress,
    required int totalPrice,
    required int operationalCost,
    required int discount,
    required String paymentMethod,
    required String paymentStatus,
  }) async {
    final db = await _dbHelper.database;

    if (customerName.isEmpty) customerName = "Pelanggan Umum";

    if (customerName != "Pelanggan Umum") {
      final existing = await db.query('customers', where: 'name = ?', whereArgs: [customerName]);
      if (existing.isEmpty) {
        await db.insert('customers', {'name': customerName, 'phone': customerPhone, 'address': customerAddress});
      } else {
        await db.update('customers', {'phone': customerPhone, 'address': customerAddress}, where: 'name = ?', whereArgs: [customerName]);
      }
    }

    int queueNum = 1;
    String todayStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
    
    var countRes = await db.rawQuery(
      "SELECT COUNT(*) as count FROM transactions WHERE substr(transaction_date, 1, 10) = ?", 
      [todayStr] 
    );
    
    if (countRes.isNotEmpty) {
      int totalToday = (countRes.first['count'] as int?) ?? 0;
      queueNum = totalToday + 1; 
    }

    String dateNow = DateTime.now().toIso8601String();

    int transId = await db.insert('transactions', {
      'total_price': totalPrice,
      'operational_cost': operationalCost,
      'discount': discount,
      'customer_name': customerName,
      'customer_phone': customerPhone,     
      'customer_address': customerAddress, 
      'payment_method': paymentMethod,  
      'payment_status': paymentStatus, 
      'queue_number': queueNum,  
      'transaction_date': dateNow,
    });

    for (var item in cartItems) {
      await db.insert('transaction_items', {
        'transaction_id': transId,
        'product_id': item['product_id'],
        'product_name': item['product_name'],
        'product_type': item['product_type'],
        'quantity': item['quantity'],
        'request_qty': item['request_qty'] ?? 0, 
        'unit_type': item['unit_type'], 
        'capital_price': item['capital_price'],
        'sell_price': item['sell_price'],
      });
      
      await db.rawUpdate('UPDATE products SET stock = stock - ? WHERE id = ?', [item['quantity'], item['product_id']]);
    }

    final newTrans = await db.query('transactions', where: 'id = ?', whereArgs: [transId]);
    return newTrans.first;
  }
}