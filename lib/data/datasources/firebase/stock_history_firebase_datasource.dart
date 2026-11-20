import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../helpers/session_manager.dart';

class StockHistoryFirebaseDataSource {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  CollectionReference _col(String path) {
    String uid = SessionManager().uid ?? 'UNKNOWN_STORE';
    return _db.collection('stores').doc(uid).collection(path);
  }

  Future<QuerySnapshot> _smartQuery(
    Query q, {
    required bool preferServer,
  }) async {
    if (preferServer) {
      try {
        return await q
            .get(const GetOptions(source: Source.server))
            .timeout(const Duration(seconds: 6));
      } catch (_) {
        return await q.get(const GetOptions(source: Source.cache));
      }
    }
    try {
      final snap = await q.get(const GetOptions(source: Source.cache));
      if (snap.docs.isNotEmpty) {
        q
            .get(const GetOptions(source: Source.server))
            .then((_) => null, onError: (_) => null);
        return snap;
      }
      return await q
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 8));
    } catch (_) {
      return await q.get(const GetOptions(source: Source.cache));
    }
  }

  Future<List<Map<String, dynamic>>> getStockHistoryData(
    String tabType,
    String startDate,
    String endDate,
  ) async {
    String start = "${startDate}T00:00:00.000";
    String end = "${endDate}T23:59:59.999";
    final bool preferServer = startDate != '2000-01-01';

    final snapshots = await Future.wait([
      _smartQuery(
        _col('stock_logs')
            .where('date', isGreaterThanOrEqualTo: start)
            .where('date', isLessThanOrEqualTo: end),
        preferServer: preferServer,
      ),
      _smartQuery(_col('products'), preferServer: preferServer),
    ]);

    final logSnap = snapshots[0];
    final prodSnap = snapshots[1];

    List<Map<String, dynamic>> logs = logSnap.docs
        .map((doc) => Map<String, dynamic>.from(doc.data() as Map))
        .toList();

    if (tabType == 'BANGUNAN') {
      logs = logs.where((log) => log['type'] == 'BANGUNAN').toList();
    } else {
      logs = logs
          .where((log) => ['KAYU', 'RENG', 'BULAT'].contains(log['type']))
          .toList();
    }

    Map<int, Map<String, dynamic>> productMap = {};
    for (var doc in prodSnap.docs) {
      var d = Map<String, dynamic>.from(doc.data() as Map);
      final int? idVal = (d['id'] as num?)?.toInt();
      if (idVal != null) productMap[idVal] = d;
    }

    List<Map<String, dynamic>> finalResults = [];
    for (var log in logs) {
      final int? pid = (log['product_id'] as num?)?.toInt();
      if (pid == null) continue;
      var prod = productMap[pid];

      if (prod != null) {
        Map<String, dynamic> merged = Map.from(log);
        merged['product_name'] = prod['name'];
        merged['wood_class'] = prod['woodClass'];
        merged['prod_type'] = prod['type'];
        merged['current_stock'] = prod['stock'];
        merged['dimensions'] = prod['dimensions'];
        merged['source'] = prod['source'];

        final double qty = (log['quantity'] as num?)?.toDouble() ?? 0;
        final double price = (log['price'] as num?)?.toDouble() ?? 0;
        merged['total_price'] =
            log['total_price'] ?? (qty * price).round();
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
      (a, b) => (b['date'] ?? '').toString().compareTo((a['date'] ?? '').toString()),
    );
    return finalResults;
  }

  Future<List<Map<String, dynamic>>> getStockLogsByExactDate(
    String exactDate,
  ) async {
    final snapshots = await Future.wait([
      _smartQuery(
        _col('stock_logs').where('date', isEqualTo: exactDate),
        preferServer: true,
      ),
      _smartQuery(_col('products'), preferServer: true),
    ]);
    final logSnap = snapshots[0];
    final prodSnap = snapshots[1];

    List<Map<String, dynamic>> logs = logSnap.docs
        .map((doc) => Map<String, dynamic>.from(doc.data() as Map))
        .toList();

    Map<int, Map<String, dynamic>> productMap = {};
    for (var doc in prodSnap.docs) {
      var d = Map<String, dynamic>.from(doc.data() as Map);
      final int? idVal = (d['id'] as num?)?.toInt();
      if (idVal != null) productMap[idVal] = d;
    }

    List<Map<String, dynamic>> finalResults = [];
    for (var log in logs) {
      final int? pid = (log['product_id'] as num?)?.toInt();
      if (pid == null) continue;
      var prod = productMap[pid];
      if (prod != null) {
        Map<String, dynamic> merged = Map.from(log);
        merged['product_name'] = prod['name'];
        merged['wood_class'] = prod['woodClass'];
        merged['prod_type'] = prod['type'];
        merged['dimensions'] = prod['dimensions'];
        merged['source'] = prod['source'];
        merged['current_stock'] = prod['stock'];

        final double qty = (log['quantity'] as num?)?.toDouble() ?? 0;
        final double price = (log['price'] as num?)?.toDouble() ?? 0;
        merged['total_price'] =
            log['total_price'] ?? (qty * price).round();
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
      (a, b) => (b['date'] ?? '').toString().compareTo((a['date'] ?? '').toString()),
    );
    return finalResults;
  }
}
