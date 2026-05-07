import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../helpers/session_manager.dart';

class StockHistoryFirebaseDataSource {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  CollectionReference _col(String path) {
    String uid = SessionManager().uid ?? 'UNKNOWN_STORE';
    return _db.collection('stores').doc(uid).collection(path);
  }

  Future<QuerySnapshot> _cacheFirstQuery(Query q) async {
    q
        .get(const GetOptions(source: Source.server))
        .then((_) => null, onError: (_) => null);
    try {
      final snap = await q.get(const GetOptions(source: Source.cache));
      if (snap.docs.isEmpty)
        return await q
            .get(const GetOptions(source: Source.server))
            .timeout(const Duration(seconds: 3));
      return snap;
    } catch (_) {
      return await q
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 3));
    }
  }

  Future<List<Map<String, dynamic>>> getStockHistoryData(
    String tabType,
    String startDate,
    String endDate,
  ) async {
    String start = "${startDate}T00:00:00.000";
    String end = "${endDate}T23:59:59.999";

    final logSnap = await _cacheFirstQuery(
      _col('stock_logs')
          .where('date', isGreaterThanOrEqualTo: start)
          .where('date', isLessThanOrEqualTo: end),
    );
    List<Map<String, dynamic>> logs = logSnap.docs
        .map((doc) => doc.data() as Map<String, dynamic>)
        .toList();

    if (tabType == 'BANGUNAN') {
      logs = logs.where((log) => log['type'] == 'BANGUNAN').toList();
    } else {
      logs = logs
          .where((log) => ['KAYU', 'RENG', 'BULAT'].contains(log['type']))
          .toList();
    }

    final prodSnap = await _cacheFirstQuery(_col('products'));
    Map<int, Map<String, dynamic>> productMap = {};
    for (var doc in prodSnap.docs) {
      var d = doc.data() as Map<String, dynamic>;
      productMap[d['id'] as int] = d;
    }

    List<Map<String, dynamic>> finalResults = [];
    for (var log in logs) {
      int pid = log['product_id'] as int;
      var prod = productMap[pid];

      if (prod != null) {
        Map<String, dynamic> merged = Map.from(log);
        merged['product_name'] = prod['name'];
        merged['wood_class'] = prod['woodClass'];
        merged['prod_type'] = prod['type'];
        merged['current_stock'] = prod['stock'];
        merged['dimensions'] = prod['dimensions'];
        merged['source'] = prod['source'];

        merged['total_price'] =
            log['total_price'] ?? (log['quantity'] * log['price']).round();
        merged['input_qty'] = log['input_qty'] ?? log['quantity'];
        merged['input_unit'] =
            log['input_unit'] ?? (prod['type'] == 'BANGUNAN' ? 'Pcs' : 'Btg');
        merged['cashier_name'] = log['cashier_name'] ?? 'Tidak Diketahui';

        // 🔥 TARIK URL FOTO NOTA DISTRIBUTOR (KALAU ADA) 🔥
        merged['receipt_proof'] = log['receipt_proof'];

        finalResults.add(merged);
      }
    }

    finalResults.sort(
      (a, b) => (b['date'] as String).compareTo(a['date'] as String),
    );
    return finalResults;
  }

  Future<List<Map<String, dynamic>>> getStockLogsByExactDate(
    String exactDate,
  ) async {
    final logSnap = await _cacheFirstQuery(
      _col('stock_logs').where('date', isEqualTo: exactDate),
    );
    List<Map<String, dynamic>> logs = logSnap.docs
        .map((doc) => doc.data() as Map<String, dynamic>)
        .toList();

    final prodSnap = await _cacheFirstQuery(_col('products'));
    Map<int, Map<String, dynamic>> productMap = {};
    for (var doc in prodSnap.docs) {
      var d = doc.data() as Map<String, dynamic>;
      productMap[d['id'] as int] = d;
    }

    List<Map<String, dynamic>> finalResults = [];
    for (var log in logs) {
      int pid = log['product_id'] as int;
      var prod = productMap[pid];
      if (prod != null) {
        Map<String, dynamic> merged = Map.from(log);
        merged['product_name'] = prod['name'];
        merged['wood_class'] = prod['woodClass'];
        merged['prod_type'] = prod['type'];
        merged['dimensions'] = prod['dimensions'];
        merged['source'] = prod['source'];
        merged['current_stock'] = prod['stock'];

        merged['total_price'] =
            log['total_price'] ?? (log['quantity'] * log['price']).round();
        merged['input_qty'] = log['input_qty'] ?? log['quantity'];
        merged['input_unit'] =
            log['input_unit'] ?? (prod['type'] == 'BANGUNAN' ? 'Pcs' : 'Btg');
        merged['cashier_name'] = log['cashier_name'] ?? 'Tidak Diketahui';

        // 🔥 TARIK URL FOTO NOTA DISTRIBUTOR (KALAU ADA) 🔥
        merged['receipt_proof'] = log['receipt_proof'];

        finalResults.add(merged);
      }
    }

    finalResults.sort(
      (a, b) => (b['date'] as String).compareTo(a['date'] as String),
    );
    return finalResults;
  }
}
