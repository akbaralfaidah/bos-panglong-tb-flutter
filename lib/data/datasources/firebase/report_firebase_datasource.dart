import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../../../helpers/session_manager.dart';

class ReportFirebaseDataSource {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  CollectionReference _col(String path) {
    String uid = SessionManager().uid ?? 'UNKNOWN_STORE';
    return _db.collection('stores').doc(uid).collection(path);
  }

  Future<List<QueryDocumentSnapshot>> _safeQuery(Query q) async {
    try {
      final snap = await q.get(const GetOptions(source: Source.cache));
      q.get(const GetOptions(source: Source.server)).then((_) => null, onError: (_) => null);
      if (snap.docs.isNotEmpty) return snap.docs;

      final sSnap = await q.get(const GetOptions(source: Source.server)).timeout(const Duration(seconds: 4));
      return sSnap.docs;
    } catch (_) {
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> getCompleteReportData({
    required String startDate,
    required String endDate,
  }) async {
    String start = "${startDate}T00:00:00.000";
    String end = "${endDate}T23:59:59.999";
    final docs = await _safeQuery(
      _col('transactions').where('transaction_date', isGreaterThanOrEqualTo: start).where('transaction_date', isLessThanOrEqualTo: end),
    );
    
    List<Map<String, dynamic>> flattenedItems = [];
    for (var doc in docs) {
      var t = doc.data() as Map<String, dynamic>;
      List<dynamic> items = t['items'] ?? [];
      for (var i in items) {
        double qty = (i['quantity'] as num?)?.toDouble() ?? 0;
        double reqQty = (i['request_qty'] as num?)?.toDouble() ?? 0;
        double displayQty = reqQty > 0 ? reqQty : (qty > 0 ? qty : 1); 

        double agreedTotal = i.containsKey('agreed_total') ? (i['agreed_total'] as num).toDouble() : (((i['sell_price'] as num?)?.toDouble() ?? 0) * displayQty);
        double capitalTotal = i.containsKey('capital_total') ? (i['capital_total'] as num).toDouble() : (((i['capital_price'] as num?)?.toDouble() ?? 0) * displayQty);

        flattenedItems.add({
          'transaction_date': t['transaction_date'],
          'invoice_id': t['id'],
          'customer_name': t['customer_name'] ?? 'Pelanggan Umum',
          'payment_status': t['payment_status'],
          'discount': t['discount'] ?? 0,
          'product_name': i['product_name'],
          'quantity': displayQty, 
          'unit_type': i['unit_type'],
          'capital_price': capitalTotal / displayQty, 
          'sell_price': agreedTotal / displayQty,     
        });
      }
    }
    flattenedItems.sort((a, b) => (b['transaction_date'] as String).compareTo(a['transaction_date'] as String));
    return flattenedItems;
  }

  Future<Map<String, double>> getFinancialStatsData(String startDate, String endDate, {String businessFilter = 'SEMUA'}) async {
    String start = "${startDate}T00:00:00.000";
    String end = "${endDate}T23:59:59.999";
    
    final docs = await _safeQuery(_col('transactions').where('transaction_date', isGreaterThanOrEqualTo: start).where('transaction_date', isLessThanOrEqualTo: end));
    
    double omsetBarangMurni = 0;
    double modalTerjual = 0;
    
    for (var doc in docs) {
      var t = doc.data() as Map<String, dynamic>;
      if (t['payment_status'] == 'Lunas') {
        List<dynamic> items = t['items'] ?? [];
        
        if (businessFilter == 'SEMUA') {
          // Original logic — total_price - ongkir
          double tp = (t['total_price'] as num?)?.toDouble() ?? 0;
          double ongkir = (t['operational_cost'] as num?)?.toDouble() ?? 0;
          omsetBarangMurni += (tp - ongkir);
          
          for (var i in items) {
            double capitalTotal = i.containsKey('capital_total') 
                ? (i['capital_total'] as num).toDouble() 
                : (((i['capital_price'] as num?)?.toDouble() ?? 0) * ((i['quantity'] as num?)?.toDouble() ?? 0));
            modalTerjual += capitalTotal;
          }
        } else {
          // Filtered — hitung dari item yang cocok saja
          for (var i in items) {
            String pType = i['product_type'] ?? '';
            bool matchFilter = false;
            if (businessFilter == 'KAYU') {
              matchFilter = ['KAYU', 'RENG', 'BULAT'].contains(pType);
            } else if (businessFilter == 'BANGUNAN') {
              matchFilter = pType == 'BANGUNAN';
            }
            
            if (matchFilter) {
              double qty = (i['quantity'] as num?)?.toDouble() ?? 0;
              double reqQty = (i['request_qty'] as num?)?.toDouble() ?? 0;
              double displayQty = reqQty > 0 ? reqQty : (qty > 0 ? qty : 1);
              
              double agreedTotal = i.containsKey('agreed_total') 
                  ? (i['agreed_total'] as num).toDouble() 
                  : (((i['sell_price'] as num?)?.toDouble() ?? 0) * displayQty);
              double capitalTotal = i.containsKey('capital_total') 
                  ? (i['capital_total'] as num).toDouble() 
                  : (((i['capital_price'] as num?)?.toDouble() ?? 0) * displayQty);
              
              omsetBarangMurni += agreedTotal;
              modalTerjual += capitalTotal;
            }
          }
        }
      }
    }

    // Bensin selalu universal — tidak difilter
    double bensinSPBU = 0;
    final gDocs = await _safeQuery(_col('gas_expenses').where('date', isGreaterThanOrEqualTo: start).where('date', isLessThanOrEqualTo: end));
    for (var doc in gDocs) {
      var g = doc.data() as Map<String, dynamic>; 
      bensinSPBU += (g['amount'] as num?)?.toDouble() ?? 0;
    }

    return {
      'omset': omsetBarangMurni,
      'bensin': bensinSPBU, 
      'modal': modalTerjual,
      'profit': omsetBarangMurni - modalTerjual - bensinSPBU, 
    };
  }

  // 🔥 UPDATE 1: Aset Gudang dipisah 🔥
  Future<double> getAssetValue() async {
    final pDocs = await _safeQuery(_col('products'));
    double assetValue = 0;
    for (var doc in pDocs) {
      var p = doc.data() as Map<String, dynamic>;
      int stock = (p['stock'] as num?)?.toInt() ?? 0;
      int modal = 0;
      if (p['buy_price_unit'] != null && p['buy_price_unit'] > 0) {
        modal = (p['buy_price_unit'] as num).toInt();
      } else if (p['buy_price_cubic'] != null && p['buy_price_cubic'] > 0) {
        modal = (p['buy_price_cubic'] as num).toInt();
      }
      if (stock > 0) assetValue += (stock * modal);
    }
    return assetValue;
  }

  // 🔥 UPDATE 2: Mesin Grafik (6 Hari / 6 Bulan / 6 Tahun) 🔥
  Future<Map<String, Map<String, double>>> getChartData(String period) async {
    DateTime now = DateTime.now();
    String startStr = "";
    List<String> keys = [];

    if (period == '6_DAYS') {
      for (int i = 5; i >= 0; i--) {
        keys.add(DateFormat('yyyy-MM-dd').format(now.subtract(Duration(days: i))));
      }
      startStr = "${keys.first}T00:00:00.000";
    } else if (period == '6_MONTHS') {
      for (int i = 5; i >= 0; i--) {
        keys.add(DateFormat('yyyy-MM').format(DateTime(now.year, now.month - i, 1)));
      }
      startStr = "${keys.first}-01T00:00:00.000";
    } else if (period == '6_YEARS') {
      for (int i = 5; i >= 0; i--) {
        keys.add((now.year - i).toString());
      }
      startStr = "${keys.first}-01-01T00:00:00.000";
    }

    Map<String, double> omsetMap = { for (var k in keys) k: 0.0 };
    Map<String, double> profitMap = { for (var k in keys) k: 0.0 };

    final tDocs = await _safeQuery(_col('transactions').where('transaction_date', isGreaterThanOrEqualTo: startStr));

    for (var doc in tDocs) {
      var t = doc.data() as Map<String, dynamic>;
      if (t['payment_status'] == 'Lunas') {
        String dateStr = t['transaction_date'].toString();
        String mKey = "";
        
        if (period == '6_DAYS' && dateStr.length >= 10) mKey = dateStr.substring(0, 10);
        else if (period == '6_MONTHS' && dateStr.length >= 7) mKey = dateStr.substring(0, 7);
        else if (period == '6_YEARS' && dateStr.length >= 4) mKey = dateStr.substring(0, 4);

        if (omsetMap.containsKey(mKey)) {
          double omset = (t['total_price'] as num).toDouble();
          double ongkir = (t['operational_cost'] as num?)?.toDouble() ?? 0;
          
          double totalModalTrx = 0;
          List<dynamic> items = t['items'] ?? [];
          for (var i in items) {
            totalModalTrx += i.containsKey('capital_total') 
                ? (i['capital_total'] as num).toDouble() 
                : (((i['capital_price'] as num?)?.toDouble() ?? 0) * ((i['quantity'] as num?)?.toDouble() ?? 0));
          }

          double omsetMurni = omset - ongkir;
          omsetMap[mKey] = omsetMap[mKey]! + omsetMurni;
          profitMap[mKey] = profitMap[mKey]! + (omsetMurni - totalModalTrx);
        }
      }
    }
    return {'omset': omsetMap, 'profit': profitMap};
  }

  // 🔥 UPDATE 3: Mesin Top Produk 🔥
  Future<List<Map<String, dynamic>>> getTopProductsData(String typeCondition, String startDate, String endDate) async {
    String startStr = "${startDate}T00:00:00.000";
    String endStr = "${endDate}T23:59:59.999";
    
    final tDocs = await _safeQuery(_col('transactions')
        .where('transaction_date', isGreaterThanOrEqualTo: startStr)
        .where('transaction_date', isLessThanOrEqualTo: endStr));

    Map<String, int> productQtyCounter = {};

    for (var doc in tDocs) {
      var t = doc.data() as Map<String, dynamic>;
      if (t['payment_status'] == 'Lunas') {
        List<dynamic> items = t['items'] ?? [];
        for (var i in items) {
          double qty = (i['quantity'] as num?)?.toDouble() ?? 0;
          String pName = i['product_name'] ?? 'Unknown';
          String pType = i['product_type'] ?? 'Unknown';

          bool matchFilter = true;
          if (typeCondition.contains("('KAYU', 'RENG', 'BULAT')") && !['KAYU', 'RENG', 'BULAT'].contains(pType)) matchFilter = false;
          else if (typeCondition.contains("'BANGUNAN'") && pType != 'BANGUNAN') matchFilter = false;

          if (matchFilter) productQtyCounter[pName] = (productQtyCounter[pName] ?? 0) + qty.toInt();
        }
      }
    }

    List<Map<String, dynamic>> allProducts = [];
    productQtyCounter.forEach((key, value) { allProducts.add({'product_name': key, 'qty': value}); });
    allProducts.sort((a, b) => (b['qty'] as int).compareTo(a['qty'] as int));

    List<Map<String, dynamic>> finalTopProducts = [];
    int otherQty = 0;
    for (int i = 0; i < allProducts.length; i++) {
      if (i < 5) finalTopProducts.add(allProducts[i]);
      else otherQty += (allProducts[i]['qty'] as num).toInt();
    }
    if (otherQty > 0) finalTopProducts.add({'product_name': 'Lainnya', 'qty': otherQty});

    return finalTopProducts;
  }

  Future<List<Map<String, dynamic>>> getCustomerCRMData() async {
    final cDocs = await _safeQuery(_col('customers'));
    List<Map<String, dynamic>> result = [];
    for (var doc in cDocs) {
      var cust = doc.data() as Map<String, dynamic>;
      String name = cust['name'] ?? '';
      if (name == 'Pelanggan Umum' || name.isEmpty) continue;
      final tDocs = await _safeQuery(_col('transactions').where('customer_name', isEqualTo: name));
      
      int spent = 0; int hutang = 0;
      for (var tDoc in tDocs) {
        var t = tDoc.data() as Map<String, dynamic>;
        int tp = (t['total_price'] as num?)?.toInt() ?? 0;
        if (t['payment_status'] == 'Lunas') spent += tp;
        else {
          int tid = t['id'] as int;
          final pDocs = await _safeQuery(_col('debt_payments').where('transaction_id', isEqualTo: tid));
          int paid = 0;
          for (var p in pDocs) { paid += ((p.data() as Map<String, dynamic>)['amount_paid'] as num?)?.toInt() ?? 0; }
          hutang += (tp - paid);
        }
      }
      result.add({'name': name, 'phone': cust['phone'] ?? '', 'address': cust['address'] ?? '', 'total_spent': spent, 'total_debt': hutang});
    }
    result.sort((a, b) => (b['total_spent'] as int).compareTo(a['total_spent'] as int));
    return result;
  }

  Future<List<Map<String, dynamic>>> getTransactionsByCustomer(String customerName) async {
    final docs = await _safeQuery(_col('transactions').where('customer_name', isEqualTo: customerName));
    List<Map<String, dynamic>> results = docs.map((doc) => doc.data() as Map<String, dynamic>).toList();
    results.sort((a, b) => (b['transaction_date'] as String).compareTo(a['transaction_date'] as String));
    return results;
  }

  // 🔥 FITUR BARU: MESIN DATABASE CATATAN 🔥
  Future<List<Map<String, dynamic>>> getNotesData() async {
    final docs = await _safeQuery(_col('notes').orderBy('date', descending: true));
    return docs.map((d) {
      var data = d.data() as Map<String, dynamic>;
      data['id'] = d.id; 
      return data;
    }).toList();
  }

  Future<void> addNoteData(String title, String content, String date) async {
    await _col('notes').add({
      'title': title,
      'content': content,
      'date': date,
      'timestamp': FieldValue.serverTimestamp(),
    });
  }

  Future<void> deleteNoteData(String docId) async {
    await _col('notes').doc(docId).delete();
  }
}