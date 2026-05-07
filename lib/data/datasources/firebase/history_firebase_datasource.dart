import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../helpers/session_manager.dart';

class HistoryFirebaseDataSource {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  CollectionReference _col(String path) {
    String uid = SessionManager().uid ?? 'UNKNOWN_STORE';
    return _db.collection('stores').doc(uid).collection(path);
  }

  // MESIN CACHE-FIRST TINGKAT DEWA
  Future<List<QueryDocumentSnapshot>> _safeQuery(Query q) async {
    q.get(const GetOptions(source: Source.server)).then((_) => null, onError: (_) => null);
    try {
      final snap = await q.get(const GetOptions(source: Source.cache));
      if (snap.docs.isNotEmpty) return snap.docs;
      final sSnap = await q.get(const GetOptions(source: Source.server)).timeout(const Duration(seconds: 4));
      return sSnap.docs;
    } catch (_) { return []; }
  }

  // 1. DATA PIUTANG
  Future<Map<String, dynamic>> loadPiutangData() async {
    final tDocs = await _safeQuery(_col('transactions'));
    List<Map<String, dynamic>> unpaid = [];
    List<Map<String, dynamic>> paid = [];
    double totalUnpaid = 0;

    final pDocs = await _safeQuery(_col('debt_payments'));
    Set<int> debtTransIds = pDocs.map((d) => (d.data() as Map<String, dynamic>)['transaction_id'] as int).toSet();

    for (var doc in tDocs) {
      var t = doc.data() as Map<String, dynamic>;
      int tid = t['id'];
      String status = t['payment_status'] ?? '';
      
      if (status != 'Lunas') {
        unpaid.add(t);
        totalUnpaid += (t['total_price'] as num).toDouble();
      } else if (debtTransIds.contains(tid)) {
        paid.add(t);
      }
    }
    return {'unpaid': unpaid, 'paid': paid, 'total': totalUnpaid};
  }

  // 2. RIWAYAT STOK MASUK (ANTI-KERITING MUTLAK)
  Future<Map<String, dynamic>> loadStockHistory(String start, String end) async {
    String s = "${start}T00:00:00.000";
    String e = "${end}T23:59:59.999";
    final logs = await _safeQuery(_col('stock_logs').where('date', isGreaterThanOrEqualTo: s).where('date', isLessThanOrEqualTo: e));
    
    final prodSnap = await _safeQuery(_col('products'));
    Map<int, String> prodNames = {};
    for(var p in prodSnap) {
      var pData = p.data() as Map<String, dynamic>;
      prodNames[pData['id']] = pData['name'] ?? 'Unknown';
    }

    List<Map<String, dynamic>> data = [];
    double total = 0;

    for (var doc in logs) {
      var log = doc.data() as Map<String, dynamic>;
      int pid = log['product_id'];
      
      // 🔥 MURNI DARI DATABASE, NO RUMUS PURBA! 🔥
      int totalHargaMurni = log.containsKey('total_price') && log['total_price'] != null 
          ? (log['total_price'] as num).toInt() 
          : ((log['quantity'] as num) * (log['price'] as num)).round();
      
      double rawQty = log.containsKey('input_qty') && log['input_qty'] != null ? (log['input_qty'] as num).toDouble() : (log['quantity'] as num).toDouble();
      String rawUnit = log.containsKey('input_unit') && log['input_unit'] != null ? log['input_unit'] : "Unit";

      data.add({
        'date': log['date'],
        'product_name': prodNames[pid] ?? 'Produk Dihapus',
        'quantity_added': rawQty, // Kirim input murni (contoh: 5 m3)
        'input_qty': rawQty,
        'input_unit': rawUnit,
        'capital_price': log['price'],
        'total_price': totalHargaMurni // Kirim harga 6 Juta bulat!
      });
      total += totalHargaMurni;
    }
    return {'data': data, 'total': total};
  }

  // 3. BARANG TERJUAL
  Future<Map<String, dynamic>> loadSoldItemsHistory(String start, String end) async {
    String s = "${start}T00:00:00.000";
    String e = "${end}T23:59:59.999";
    final tDocs = await _safeQuery(_col('transactions').where('transaction_date', isGreaterThanOrEqualTo: s).where('transaction_date', isLessThanOrEqualTo: e));
    
    List<Map<String, dynamic>> data = [];
    double totalQty = 0;

    for (var doc in tDocs) {
      var t = doc.data() as Map<String, dynamic>;
      if (t['payment_status'] == 'Lunas') {
        List<dynamic> items = t['items'] ?? [];
        for (var i in items) {
          double qty = (i['request_qty'] != null && i['request_qty'] > 0) 
              ? (i['request_qty'] as num).toDouble() 
              : (i['quantity'] as num).toDouble();
          
          data.add({
            'transaction_date': t['transaction_date'],
            'trans_id': t['id'],
            'customer_name': t['customer_name'] ?? 'Pelanggan Umum',
            'product_name': i['product_name'],
            'product_type': i['product_type'] ?? '-',
            'quantity': qty,
            'unit_type': i['unit_type'] ?? 'Unit',
          });
          totalQty += qty;
        }
      }
    }
    return {'data': data, 'total': totalQty};
  }

  // 4. RIWAYAT BENSIN
  Future<Map<String, dynamic>> loadBensinHistory(String start, String end) async {
    String s = "${start}T00:00:00.000";
    String e = "${end}T23:59:59.999";
    final tDocs = await _safeQuery(_col('transactions').where('transaction_date', isGreaterThanOrEqualTo: s).where('transaction_date', isLessThanOrEqualTo: e));
    
    List<Map<String, dynamic>> data = [];
    double total = 0;

    for (var doc in tDocs) {
      var t = doc.data() as Map<String, dynamic>;
      double bensin = (t['operational_cost'] as num?)?.toDouble() ?? 0;
      if (bensin > 0) {
        data.add(t);
        total += bensin;
      }
    }
    return {'data': data, 'total': total};
  }

  // 5. RIWAYAT TRANSAKSI / OMSET
  Future<Map<String, dynamic>> loadTransactionsHistory(String start, String end) async {
    String s = "${start}T00:00:00.000";
    String e = "${end}T23:59:59.999";
    final tDocs = await _safeQuery(_col('transactions').where('transaction_date', isGreaterThanOrEqualTo: s).where('transaction_date', isLessThanOrEqualTo: e));
    
    List<Map<String, dynamic>> data = [];
    double total = 0;

    for (var doc in tDocs) {
      var t = doc.data() as Map<String, dynamic>;
      data.add(t);
      if (t['payment_status'] == 'Lunas') {
        double grand = (t['total_price'] as num?)?.toDouble() ?? 0;
        double bensin = (t['operational_cost'] as num?)?.toDouble() ?? 0;
        total += (grand - bensin);
      }
    }
    return {'data': data, 'total': total};
  }
}