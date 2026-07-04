import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../../../helpers/session_manager.dart';

class ReviewTransactionFirebaseDataSource {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  CollectionReference _col(String path) => _db.collection('stores').doc(SessionManager().uid ?? 'UNKNOWN_STORE').collection(path);

  Future<List<Map<String, dynamic>>> getCustomersData() async {
    try {
      final snapshot = await _col('customers').orderBy('name').get(const GetOptions(source: Source.cache));
      return snapshot.docs.map((doc) => doc.data() as Map<String, dynamic>).toList(); 
    } catch (e) {
      return [];
    }
  }

  Future<Map<String, dynamic>> saveTransactionToDb({
    required List<Map<String, dynamic>> cartItems, required String customerName, required String customerPhone,
    required String customerAddress, required int totalPrice, required int operationalCost,
    required int discount, required String paymentMethod, required String paymentStatus,
    required DateTime transactionDate, 
    int cutProfit = 0,
  }) async {
    
    if (customerName.trim().isEmpty) customerName = "Pelanggan Umum";
    if (customerName != "Pelanggan Umum") {
      _col('customers').doc(customerName).set({
        'name': customerName, 'phone': customerPhone, 'address': customerAddress
      }, SetOptions(merge: true));
    }

    // 🔥 NOMOR ANTRIAN DIHITUNG BERDASARKAN TANGGAL YANG DIPILIH 🔥
    String todayStr = DateFormat('yyyy-MM-dd').format(transactionDate);
    String startOfDay = "${todayStr}T00:00:00.000"; String endOfDay = "${todayStr}T23:59:59.999";

    int queueNum = 1;
    try {
      final todayTrans = await _col('transactions')
          .where('transaction_date', isGreaterThanOrEqualTo: startOfDay)
          .where('transaction_date', isLessThanOrEqualTo: endOfDay)
          .get(const GetOptions(source: Source.cache)); 
          
      queueNum = todayTrans.docs.length + 1;
    } catch (e) { queueNum = 1; }

    int transId = DateTime.now().millisecondsSinceEpoch;
    String dateNow = transactionDate.toIso8601String(); // 🔥 SIMPAN TANGGAL CUSTOM

    List<Map<String, dynamic>> embeddedItems = [];
    for (var item in cartItems) {
      double reqQty = (item['request_qty'] as num?)?.toDouble() ?? 1.0;
      int sellPrice = (item['sell_price'] as num?)?.toInt() ?? 0;
      int dbCapPrice = (item['capital_price'] as num?)?.toInt() ?? 0;
      
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
        finalCapitalTotal = (reqQty * dbCapPrice).round(); 
      }

      embeddedItems.add({
        'product_id': item['product_id'], 
        'product_name': item['product_name'], 
        'product_type': item['product_type'],
        'dimensions': item['dimensions'], // 🔥 FIX: Sertakan dimensi
        'quantity': item['quantity'], 
        'request_qty': reqQty, 
        'unit_type': item['unit_type'], 
        'capital_price': dbCapPrice, 
        'sell_price': sellPrice,
        'agreed_total': finalAgreedTotal, 
        'capital_total': finalCapitalTotal,
      });
    }

    WriteBatch batch = _db.batch();
    String currentCashier = SessionManager().userName ?? 'Tidak Diketahui';

    Map<String, dynamic> transactionData = {
      'id': transId, 'total_price': totalPrice, 'operational_cost': operationalCost, 'discount': discount,
      'cut_profit': cutProfit,
      'customer_name': customerName, 'customer_phone': customerPhone, 'customer_address': customerAddress,
      'payment_method': paymentMethod, 'payment_status': paymentStatus, 'queue_number': queueNum,
      'transaction_date': dateNow, 'items': embeddedItems,
      'cashier_name': currentCashier, 
    };

    batch.set(_col('transactions').doc(transId.toString()), transactionData);


    for (var item in cartItems) {
      batch.update(_col('products').doc(item['product_id'].toString()), {
        'stock': FieldValue.increment(-(item['quantity'] as num).toDouble())
      });
    }

    batch.commit(); 
    return transactionData;
  }
}