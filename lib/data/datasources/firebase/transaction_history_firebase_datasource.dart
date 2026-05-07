import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../helpers/session_manager.dart';

class TransactionHistoryFirebaseDataSource {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  CollectionReference _col(String path) {
    String uid = SessionManager().uid ?? 'UNKNOWN_STORE';
    return _db.collection('stores').doc(uid).collection(path);
  }

  // MESIN CACHE-FIRST TINGKAT DEWA
  Future<QuerySnapshot> _cacheFirstQuery(Query q) async {
    q.get(const GetOptions(source: Source.server)).then((_) => null, onError: (_) => null);
    try {
      final snap = await q.get(const GetOptions(source: Source.cache));
      if (snap.docs.isEmpty) return await q.get(const GetOptions(source: Source.server)).timeout(const Duration(seconds: 3));
      return snap;
    } catch (_) {
      return await q.get(const GetOptions(source: Source.server)).timeout(const Duration(seconds: 3));
    }
  }

  Future<Map<String, dynamic>> getFilteredTransactionHistory({
    required String statusCondition, 
    required String startDate, 
    required String endDate
  }) async {
    String start = "${startDate}T00:00:00.000";
    String end = "${endDate}T23:59:59.999";

    final snapshot = await _cacheFirstQuery(
      _col('transactions').where('transaction_date', isGreaterThanOrEqualTo: start).where('transaction_date', isLessThanOrEqualTo: end)
    );
        
    List<Map<String, dynamic>> results = snapshot.docs.map((doc) => doc.data() as Map<String, dynamic>).toList();

    if (statusCondition == 'LUNAS') {
      results = results.where((doc) => doc['payment_status'] == 'Lunas').toList();
    } else {
      results = results.where((doc) => doc['payment_status'] != 'Lunas').toList();
    }

    results.sort((a, b) => (b['transaction_date'] as String).compareTo(a['transaction_date'] as String));

    double globalOmsetKayu = 0;
    double globalOmsetBangunan = 0;
    double globalBensin = 0; // 🔥 VARIABEL BARU BUAT BENSIN

    for (var t in results) {
      List<dynamic> items = t['items'] ?? [];
      double trxOmsetKayu = 0;
      double trxOmsetBangunan = 0;
      
      // 🔥 SEDOT ONGOS KIRIM / BENSIN DARI NOTA INI
      double opCost = (t['operational_cost'] as num?)?.toDouble() ?? 0;
      globalBensin += opCost; 

      for (var i in items) {
        
        // 🔥 FIX ANTI-LEDAKAN OMSET 1 MILIAR: HARAM NGALIIN BATANG LAGI!
        double itemOmset = 0;
        if (i.containsKey('agreed_total') && i['agreed_total'] != null) {
          itemOmset = (i['agreed_total'] as num).toDouble();
        } else {
          // Fallback darurat biar tetep aman
          double sell = (i['sell_price'] as num?)?.toDouble() ?? 0;
          double reqQty = (i['request_qty'] as num?)?.toDouble() ?? 0;
          double qty = (i['quantity'] as num?)?.toDouble() ?? 0;
          double displayQty = reqQty > 0 ? reqQty : qty; 
          itemOmset = sell * displayQty;
        }

        String pType = i['product_type'] ?? '';
        if (['KAYU', 'RENG', 'BULAT'].contains(pType)) {
          trxOmsetKayu += itemOmset;
        } else {
          trxOmsetBangunan += itemOmset;
        }
      }

      double totalTrxOmset = trxOmsetKayu + trxOmsetBangunan;
      double discount = (t['discount'] as num?)?.toDouble() ?? 0;

      if (totalTrxOmset > 0 && discount > 0) {
        globalOmsetKayu += trxOmsetKayu - (discount * (trxOmsetKayu / totalTrxOmset));
        globalOmsetBangunan += trxOmsetBangunan - (discount * (trxOmsetBangunan / totalTrxOmset));
      } else {
        globalOmsetKayu += trxOmsetKayu;
        globalOmsetBangunan += trxOmsetBangunan;
      }
    }

    return {
      'history': results,
      'omset_kayu': globalOmsetKayu.round(),
      'omset_bangunan': globalOmsetBangunan.round(),
      'total_bensin': globalBensin.round(), // 🔥 KIRIM DATA BENSIN KE UI
    };
  }
}