import 'dart:io';
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
    String deliveryStatus = 'Selesai',
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
    List<Map<String, dynamic>> initialDeliveredSummary = [];
    Map<String, double> undeliveredByProduct = {};

    bool allDelivered = true;
    bool noneDelivered = true;

    for (var item in cartItems) {
      double qty = (item['quantity'] as num?)?.toDouble() ?? 1.0;
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

      double deliveredReqQty = reqQty;
      double deliveredQty = qty;
      if (deliveryStatus == 'Belum Diantar') {
        deliveredReqQty = 0.0;
        deliveredQty = 0.0;
      } else if (deliveryStatus == 'Sebagian') {
        deliveredReqQty = ((item['delivered_request_qty'] as num?)?.toDouble() ?? 0.0).clamp(0.0, reqQty);
        deliveredQty = reqQty > 0
            ? double.parse(((deliveredReqQty / reqQty) * qty).toStringAsFixed(2))
            : 0.0;
      }

      if (deliveredQty < qty - 0.001) allDelivered = false;
      if (deliveredQty > 0.001) noneDelivered = false;

      double undeliveredQty = double.parse((qty - deliveredQty).clamp(0.0, qty).toStringAsFixed(2));
      if (undeliveredQty > 0 && item['product_id'] != null) {
        String pid = item['product_id'].toString();
        undeliveredByProduct[pid] = (undeliveredByProduct[pid] ?? 0.0) + undeliveredQty;
      }

      if (deliveredReqQty > 0) {
        initialDeliveredSummary.add({
          'product_name': item['product_name'],
          'delivered_req_qty': deliveredReqQty,
          'unit_type': item['unit_type'],
        });
      }

      embeddedItems.add({
        'product_id': item['product_id'], 
        'product_name': item['product_name'], 
        'product_type': item['product_type'],
        'dimensions': item['dimensions'], // 🔥 FIX: Sertakan dimensi
        'quantity': qty, 
        'request_qty': reqQty, 
        'delivered_qty': deliveredQty,
        'delivered_request_qty': deliveredReqQty,
        'unit_type': item['unit_type'], 
        'capital_price': dbCapPrice, 
        'sell_price': sellPrice,
        'agreed_total': finalAgreedTotal, 
        'capital_total': finalCapitalTotal,
      });
    }

    String effectiveDeliveryStatus = allDelivered
        ? 'Selesai'
        : (noneDelivered ? 'Belum Diantar' : 'Sebagian');

    String currentCashier = SessionManager().userName ?? 'Tidak Diketahui';
    List<Map<String, dynamic>> deliveryLogs = [];
    if (effectiveDeliveryStatus == 'Sebagian' && initialDeliveredSummary.isNotEmpty) {
      deliveryLogs.add({
        'date': dateNow,
        'cashier_name': currentCashier,
        'note': 'Pengambilan / pengantaran awal saat transaksi',
        'items': initialDeliveredSummary,
      });
    }

    WriteBatch batch = _db.batch();

    Map<String, dynamic> transactionData = {
      'id': transId, 'total_price': totalPrice, 'operational_cost': operationalCost, 'discount': discount,
      'cut_profit': cutProfit,
      'customer_name': customerName, 'customer_phone': customerPhone, 'customer_address': customerAddress,
      'payment_method': paymentMethod, 'payment_status': paymentStatus, 'queue_number': queueNum,
      'transaction_date': dateNow, 'items': embeddedItems,
      'cashier_name': currentCashier,
      'cashier_role': SessionManager().isOwner ? 'OWNER' : 'EMPLOYEE',
      'source_platform': Platform.isAndroid ? 'android' : (Platform.isIOS ? 'ios' : 'other'),
      'created_at_ms': DateTime.now().millisecondsSinceEpoch,
      'delivery_status': effectiveDeliveryStatus,
      'delivery_logs': deliveryLogs,
    };

    batch.set(_col('transactions').doc(transId.toString()), transactionData);

    // Kelompokkan pengurangan stok & penambahan titipan per product_id
    Map<String, double> stockDeductByProduct = {};
    for (var item in cartItems) {
      if (item['product_id'] != null) {
        String pid = item['product_id'].toString();
        stockDeductByProduct[pid] = (stockDeductByProduct[pid] ?? 0.0) + (item['quantity'] as num).toDouble();
      }
    }

    for (var entry in stockDeductByProduct.entries) {
      String pid = entry.key;
      double deductQty = entry.value;
      double reserveQty = undeliveredByProduct[pid] ?? 0.0;

      Map<String, dynamic> prodUpdate = {
        'stock': FieldValue.increment(-deductQty),
      };
      if (reserveQty > 0) {
        prodUpdate['reserved_stock'] = FieldValue.increment(reserveQty);
      }
      batch.set(_col('products').doc(pid), prodUpdate, SetOptions(merge: true));
    }

    await batch.commit(); 
    return transactionData;
  }
}