import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../helpers/session_manager.dart';

class TransactionHistoryFirebaseDataSource {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  CollectionReference _col(String path) {
    String uid = SessionManager().uid ?? 'UNKNOWN_STORE';
    return _db.collection('stores').doc(uid).collection(path);
  }

  /// Query adaptif anti-hang & anti-stale:
  /// - Saat [preferServer] = true (filter harian/mingguan/bulanan/titipan): ambil langsung dari
  ///   server (1x request, timeout 7 detik) agar transaksi yang baru dibuat karyawan di HP lain
  ///   langsung muncul seketika; bila offline/timeout langsung fallback mulus ke cache lokal.
  /// - Saat [preferServer] = false (filter 'Semua' ribuan nota): baca cache lokal instan agar
  ///   tidak lag, lalu sinkronisasi ringan 1x di latar belakang.
  Future<List<QueryDocumentSnapshot>> _smartQuery(
    Query q, {
    required bool preferServer,
  }) async {
    if (preferServer) {
      try {
        final serverSnap = await q
            .get(const GetOptions(source: Source.server))
            .timeout(const Duration(seconds: 7));
        return serverSnap.docs;
      } catch (_) {
        try {
          final cacheSnap = await q.get(const GetOptions(source: Source.cache));
          return cacheSnap.docs;
        } catch (_) {
          return [];
        }
      }
    }

    try {
      final cacheSnap = await q.get(const GetOptions(source: Source.cache));
      if (cacheSnap.docs.isNotEmpty) {
        q
            .get(const GetOptions(source: Source.server))
            .then((_) => null, onError: (_) => null);
        return cacheSnap.docs;
      }
    } catch (_) {}

    try {
      final serverSnap = await q
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 10));
      return serverSnap.docs;
    } catch (_) {
      try {
        final cacheSnap = await q.get(const GetOptions(source: Source.cache));
        return cacheSnap.docs;
      } catch (_) {
        return [];
      }
    }
  }

  Future<Map<String, dynamic>> getFilteredTransactionHistory({
    required String statusCondition, 
    required String startDate, 
    required String endDate
  }) async {
    String start = "${startDate}T00:00:00.000";
    String end = "${endDate}T23:59:59.999";
    final bool isAllTime = startDate == '2000-01-01';

    final List<QueryDocumentSnapshot> docs;
    if (statusCondition == 'TITIPAN') {
      // Langsung filter status pengantaran di Firestore (hemat ribuan dokumen!)
      docs = await _smartQuery(
        _col('transactions').where(
          'delivery_status',
          whereIn: ['Belum Diantar', 'Sebagian'],
        ),
        preferServer: true,
      );
    } else {
      docs = await _smartQuery(
        _col('transactions')
            .where('transaction_date', isGreaterThanOrEqualTo: start)
            .where('transaction_date', isLessThanOrEqualTo: end),
        preferServer: !isAllTime,
      );
    }

    List<Map<String, dynamic>> results = docs
        .map((doc) => Map<String, dynamic>.from(doc.data() as Map))
        .toList();

    if (statusCondition == 'LUNAS') {
      results = results
          .where((doc) => doc['payment_status'] == 'Lunas' && doc['is_legacy_titipan'] != true)
          .toList();
    } else if (statusCondition == 'TITIPAN') {
      results = results.where((doc) {
        String dStatus = doc['delivery_status']?.toString() ?? 'Selesai';
        if (dStatus == 'Selesai') return false;
        if (!isAllTime) {
          final String tDate = (doc['transaction_date'] ?? '').toString();
          if (tDate.compareTo(start) < 0 || tDate.compareTo(end) > 0) {
            return false;
          }
        }
        return true;
      }).toList();
    } else {
      results = results
          .where((doc) => doc['payment_status'] != 'Lunas' && doc['is_legacy_titipan'] != true)
          .toList();
    }

    results.sort(
      (a, b) => (b['transaction_date'] ?? '')
          .toString()
          .compareTo((a['transaction_date'] ?? '').toString()),
    );

    double globalOmsetKayu = 0;
    double globalOmsetBangunan = 0;
    double globalBensin = 0; // 🔥 VARIABEL BARU BUAT BENSIN

    for (var t in results) {
      if (t['is_legacy_titipan'] == true) continue;
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

  Future<Map<String, dynamic>> getCapitalTransactionHistory({
    required String startDate, 
    required String endDate
  }) async {
    String start = "${startDate}T00:00:00.000";
    String end = "${endDate}T23:59:59.999";
    final bool isAllTime = startDate == '2000-01-01';

    final docs = await _smartQuery(
      _col('transactions')
          .where('transaction_date', isGreaterThanOrEqualTo: start)
          .where('transaction_date', isLessThanOrEqualTo: end),
      preferServer: !isAllTime,
    );

    List<Map<String, dynamic>> results = docs
        .map((doc) => Map<String, dynamic>.from(doc.data() as Map))
        .where((doc) => doc['is_legacy_titipan'] != true)
        .toList();

    results.sort(
      (a, b) => (b['transaction_date'] ?? '')
          .toString()
          .compareTo((a['transaction_date'] ?? '').toString()),
    );

    double globalModalKayu = 0;
    double globalModalBangunan = 0;
    double globalBensin = 0; 

    for (var t in results) {
      List<dynamic> items = t['items'] ?? [];
      double trxModalKayu = 0;
      double trxModalBangunan = 0;
      
      double opCost = (t['operational_cost'] as num?)?.toDouble() ?? 0;
      globalBensin += opCost; 

      for (var i in items) {
        double capPrice = (i['capital_price'] as num?)?.toDouble() ?? 0;
        double reqQty = (i['request_qty'] as num?)?.toDouble() ?? 0;
        double qty = (i['quantity'] as num?)?.toDouble() ?? 0;
        double displayQty = reqQty > 0 ? reqQty : qty; 
        
        double itemModal = capPrice * displayQty;

        String pType = i['product_type'] ?? '';
        if (['KAYU', 'RENG', 'BULAT'].contains(pType)) {
          trxModalKayu += itemModal;
        } else {
          trxModalBangunan += itemModal;
        }
      }

      globalModalKayu += trxModalKayu;
      globalModalBangunan += trxModalBangunan;
    }

    return {
      'history': results,
      'modal_kayu': globalModalKayu.round(),
      'modal_bangunan': globalModalBangunan.round(),
      'total_bensin': globalBensin.round(), 
    };
  }
}