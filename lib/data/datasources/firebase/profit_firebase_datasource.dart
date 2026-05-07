import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../helpers/session_manager.dart';

class ProfitFirebaseDataSource {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  CollectionReference _col(String path) => _db.collection('stores').doc(SessionManager().uid ?? 'UNKNOWN_STORE').collection(path);

  Future<List<QueryDocumentSnapshot>> _safeQuery(Query q) async {
    q.get(const GetOptions(source: Source.server)).then((_) => null, onError: (_) => null);
    try {
      final snap = await q.get(const GetOptions(source: Source.cache));
      return snap.docs;
    } catch (_) { return []; }
  }

  Future<void> withdrawProfitForCapital(int amount, String note) async {
    int id = DateTime.now().millisecondsSinceEpoch;
    String dateNow = DateTime.now().toIso8601String();
    
    await _col('reinvestasi_modal').doc(id.toString()).set({
      'id': id,
      'amount': amount,
      'note': note,
      'date': dateNow,
      'cashier_name': SessionManager().userName ?? 'Owner',
    });
  }

  Future<Map<String, dynamic>> getProfitAndExpensesData(String startDate, String endDate) async {
    String start = "${startDate}T00:00:00.000";
    String end = "${endDate}T23:59:59.999";

    double totalProfit = 0;
    double totalOngkir = 0;
    double totalPengeluaran = 0;
    double totalReinvestasi = 0; 
    
    double labaKayu = 0;
    double labaBangunan = 0;

    List<Map<String, dynamic>> historyList = [];

    final tDocs = await _safeQuery(_col('transactions')
        .where('transaction_date', isGreaterThanOrEqualTo: start)
        .where('transaction_date', isLessThanOrEqualTo: end));
        
    for (var doc in tDocs) {
      var t = doc.data() as Map<String, dynamic>;
      if (t['payment_status'] == 'Lunas') {
        double op = (t['operational_cost'] as num?)?.toDouble() ?? 0;
        double disc = (t['discount'] as num?)?.toDouble() ?? 0;
        totalOngkir += op;

        List<dynamic> items = t['items'] ?? [];
        double trxProfit = 0;
        
        for (var item in items) {
          double agreed = 0;
          double capital = 0;
          if (item.containsKey('agreed_total') && item['agreed_total'] != null) {
            agreed = (item['agreed_total'] as num).toDouble();
            capital = (item['capital_total'] as num).toDouble();
          } else {
            double sell = (item['sell_price'] as num?)?.toDouble() ?? 0;
            double cap = (item['capital_price'] as num?)?.toDouble() ?? 0;
            double qty = (item['quantity'] as num?)?.toDouble() ?? 0;
            agreed = sell * qty;
            capital = cap * qty;
          }
          
          double itemProfit = agreed - capital;
          trxProfit += itemProfit;
          
          String type = (item['product_type'] ?? '').toString().toUpperCase();
          if (type == 'KAYU' || type == 'RENG' || type == 'BULAT') {
            labaKayu += itemProfit;
          } else {
            labaBangunan += itemProfit;
          }
        }
        
        totalProfit += (trxProfit - disc);
        double finalLabaTrx = trxProfit + op - disc;

        historyList.add({
          'id': t['id'],
          'ref_id': t['id'],
          'date': t['transaction_date'],
          'type': 'LABA',
          'amount': finalLabaTrx.round(),
          'title': 'Penjualan (INV-${t['id']})',
          'subtitle': 'Pelanggan: ${t['customer_name'] ?? 'Umum'}',
          'cashier_name': t['cashier_name'] ?? 'Kasir',
        });
      }
    }

    final gDocs = await _safeQuery(_col('gas_expenses')
        .where('date', isGreaterThanOrEqualTo: start)
        .where('date', isLessThanOrEqualTo: end));
        
    for (var doc in gDocs) {
      var g = doc.data() as Map<String, dynamic>;
      double amt = (g['amount'] as num?)?.toDouble() ?? 0;
      totalPengeluaran += amt;
      
      historyList.add({
        'id': g['id'],
        'date': g['date'],
        'type': 'PENGELUARAN',
        'amount': amt.round(),
        'title': 'Biaya Operasional',
        'subtitle': g['description'] ?? 'Pengeluaran',
        'cashier_name': g['cashier_name'] ?? 'Admin',
      });
    }

    final rDocs = await _safeQuery(_col('reinvestasi_modal')
        .where('date', isGreaterThanOrEqualTo: start)
        .where('date', isLessThanOrEqualTo: end));
        
    for (var doc in rDocs) {
      var r = doc.data() as Map<String, dynamic>;
      double amt = (r['amount'] as num?)?.toDouble() ?? 0;
      totalReinvestasi += amt;
      
      historyList.add({
        'id': r['id'],
        'date': r['date'],
        'type': 'REINVEST',
        'amount': amt.round(),
        'title': 'Alokasi Profit ke Gudang', // 🔥 BAHASA DIPERBAIKI 🔥
        'subtitle': r['note'] ?? 'Subsidi Modal',
        'cashier_name': r['cashier_name'] ?? 'Owner',
      });
    }

    historyList.sort((a, b) => DateTime.parse(b['date'].toString()).compareTo(DateTime.parse(a['date'].toString())));

    return {
      'profit_kotor': totalProfit.round(), 
      'ongkir_masuk': totalOngkir.round(),
      'pengeluaran': totalPengeluaran.round(),
      'reinvestasi_modal': totalReinvestasi.round(), 
      'profit_bersih': (totalProfit + totalOngkir - totalPengeluaran - totalReinvestasi).round(), 
      'history': historyList, 
      'laba_kayu': labaKayu.round(),
      'laba_bangunan': labaBangunan.round(),
    };
  }
}