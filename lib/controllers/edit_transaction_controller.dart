import '../data/datasources/firebase/product_firebase_datasource.dart';
import '../data/datasources/firebase/transaction_firebase_datasource.dart';
import '../models/product.dart';
import '../helpers/session_manager.dart';

class EditTransactionController {
  final ProductFirebaseDataSource _productDS = ProductFirebaseDataSource();
  final TransactionFirebaseDataSource _transDS = TransactionFirebaseDataSource();

  Future<List<Product>> getAllProducts() async {
    List<Product> list = await _productDS.getAllProducts();
    list.sort((a, b) => a.orderIndex.compareTo(b.orderIndex));
    return list;
  }

  Future<void> saveEditedTransaction({
    required int transId,
    required List<Map<String, dynamic>> oldItems,
    required List<Map<String, dynamic>> cartItems,
    required String customerName,
    required String customerPhone,
    required String customerAddress,
    required int totalPrice,
    required int operationalCost,
    required int discount,
    required String paymentMethod,
    required String paymentStatus,
    required String transactionDate,
    required int queueNumber,
  }) async {
    List<Map<String, dynamic>> embeddedNewItems = [];
    for (var item in cartItems) {
      double reqQty = (item['request_qty'] as num?)?.toDouble() ?? 1.0;
      int sellPrice = (item['sell_price'] as num?)?.toInt() ?? 0;
      int capPrice = (item['capital_price'] as num?)?.toInt() ?? 0;
      
      int finalAgreedTotal = 0;
      if (item.containsKey('agreed_total') && item['agreed_total'] != null) {
        finalAgreedTotal = (item['agreed_total'] as num).toInt();
      } else {
        finalAgreedTotal = (reqQty * sellPrice).round(); 
      }

      int finalCapitalTotal = 0;
      if (item.containsKey('capital_total') && item['capital_total'] != null) {
        finalCapitalTotal = (item['capital_total'] as num).toInt();
      } else {
        finalCapitalTotal = (reqQty * capPrice).round(); 
      }

      embeddedNewItems.add({
        'product_id': item['product_id'], 
        'product_name': item['product_name'], 
        'product_type': item['product_type'],
        'dimensions': item['dimensions'],
        'quantity': item['quantity'], 
        'request_qty': reqQty, 
        'unit_type': item['unit_type'], 
        'capital_price': capPrice, 
        'sell_price': sellPrice,
        'agreed_total': finalAgreedTotal, 
        'capital_total': finalCapitalTotal,
      });
    }

    String currentCashier = SessionManager().userName ?? 'Tidak Diketahui';

    Map<String, dynamic> updatedTransData = {
      'total_price': totalPrice, 
      'operational_cost': operationalCost, 
      'discount': discount,
      'customer_name': customerName, 
      'customer_phone': customerPhone, 
      'customer_address': customerAddress,
      'payment_method': paymentMethod, 
      'payment_status': paymentStatus, 
      'items': embeddedNewItems,
      'cashier_name': currentCashier,
    };

    await _transDS.updateTransaction(transId, oldItems, embeddedNewItems, updatedTransData);
  }
}
