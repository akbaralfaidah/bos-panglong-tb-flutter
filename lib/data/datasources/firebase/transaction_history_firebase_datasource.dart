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

  static double _itemAgreedAmount(Map<String, dynamic> item) {
    if (item.containsKey('agreed_total') && item['agreed_total'] != null) {
      return (item['agreed_total'] as num).toDouble();
    }
    final double sell = (item['sell_price'] as num?)?.toDouble() ?? 0;
    final double reqQty = (item['request_qty'] as num?)?.toDouble() ?? 0;
    final double qty = (item['quantity'] as num?)?.toDouble() ?? 0;
    final double displayQty = reqQty > 0 ? reqQty : qty;
    return sell * displayQty;
  }

  static double _remainingUndeliveredRatio(
    Map<String, dynamic> item,
    String deliveryStatus,
  ) {
    final double qty = (item['quantity'] as num?)?.toDouble() ?? 0.0;
    if (qty <= 0) {
      return deliveryStatus == 'Belum Diantar' ? 1.0 : 0.0;
    }
    final double deliveredQty =
        item.containsKey('delivered_qty') && item['delivered_qty'] != null
            ? (item['delivered_qty'] as num).toDouble()
            : (deliveryStatus == 'Belum Diantar' ? 0.0 : qty);
    final double remaining = (qty - deliveredQty).clamp(0.0, qty);
    return remaining / qty;
  }

  /// Rumus tunggal metrik ringkasan untuk daftar transaksi yang tampil di layar
  /// (dipakai oleh query/stream utama maupun saat hasil pencarian difilter).
  /// - Pada tab `TITIPAN`: menghitung sisa nilai barang yang BELUM diantar (prorata utk `Sebagian`),
  ///   memisahkan nota kasir vs Titipan Lama agar nominal Titipan Lama tidak pernah tercampur.
  static Map<String, int> computeMetricsForList({
    required List<Map<String, dynamic>> transactions,
    required String statusCondition,
  }) {
    double globalOmsetKayu = 0;
    double globalOmsetBangunan = 0;
    double globalBensin = 0;
    double legacyRemainingValue = 0;
    int kasirTitipanCount = 0;
    int legacyTitipanCount = 0;

    final bool isTitipanTab = statusCondition == 'TITIPAN';

    for (var t in transactions) {
      final bool isLegacy = t['is_legacy_titipan'] == true;
      final String deliveryStatus =
          t['delivery_status']?.toString() ?? 'Selesai';
      final List<dynamic> items = t['items'] ?? [];

      if (isTitipanTab) {
        if (isLegacy) {
          legacyTitipanCount++;
          for (var raw in items) {
            if (raw is! Map) continue;
            final Map<String, dynamic> item = Map<String, dynamic>.from(raw);
            final double itemVal = _itemAgreedAmount(item);
            final double ratio = _remainingUndeliveredRatio(item, deliveryStatus);
            legacyRemainingValue += itemVal * ratio;
          }
          continue;
        }
        kasirTitipanCount++;
      } else if (isLegacy) {
        continue;
      }

      double trxGrossTotal = 0;
      double trxValueKayu = 0;
      double trxValueBangunan = 0;

      if (!isTitipanTab) {
        final double opCost = (t['operational_cost'] as num?)?.toDouble() ?? 0;
        globalBensin += opCost;
      }

      for (var raw in items) {
        if (raw is! Map) continue;
        final Map<String, dynamic> item = Map<String, dynamic>.from(raw);
        final double fullItemOmset = _itemAgreedAmount(item);
        trxGrossTotal += fullItemOmset;

        final double effectiveItemOmset = isTitipanTab
            ? fullItemOmset * _remainingUndeliveredRatio(item, deliveryStatus)
            : fullItemOmset;

        final String pType = (item['product_type'] ?? '').toString();
        if (['KAYU', 'RENG', 'BULAT'].contains(pType)) {
          trxValueKayu += effectiveItemOmset;
        } else {
          trxValueBangunan += effectiveItemOmset;
        }
      }

      final double discount = (t['discount'] as num?)?.toDouble() ?? 0;
      if (trxGrossTotal > 0 && discount > 0) {
        globalOmsetKayu +=
            (trxValueKayu - (discount * (trxValueKayu / trxGrossTotal)))
                .clamp(0.0, double.infinity);
        globalOmsetBangunan +=
            (trxValueBangunan - (discount * (trxValueBangunan / trxGrossTotal)))
                .clamp(0.0, double.infinity);
      } else {
        globalOmsetKayu += trxValueKayu;
        globalOmsetBangunan += trxValueBangunan;
      }
    }

    return {
      'omset_kayu': globalOmsetKayu.round(),
      'omset_bangunan': globalOmsetBangunan.round(),
      'total_bensin': globalBensin.round(),
      'kasir_titipan_count': kasirTitipanCount,
      'legacy_titipan_count': legacyTitipanCount,
      'legacy_titipan_value': legacyRemainingValue.round(),
    };
  }

  /// Proses daftar map transaksi mentah menjadi payload tab riwayat yang terurut & terhitung.
  static Map<String, dynamic> computeHistorySummaryFromMaps({
    required List<Map<String, dynamic>> rawDocs,
    required String statusCondition,
    required String start,
    required String end,
    required bool isAllTime,
  }) {
    List<Map<String, dynamic>> results =
        rawDocs.map((doc) => Map<String, dynamic>.from(doc)).toList();

    if (statusCondition == 'LUNAS') {
      results = results
          .where((doc) =>
              doc['payment_status'] == 'Lunas' &&
              doc['is_legacy_titipan'] != true)
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
          .where((doc) =>
              doc['payment_status'] != 'Lunas' &&
              doc['is_legacy_titipan'] != true)
          .toList();
    }

    results.sort(
      (a, b) => (b['transaction_date'] ?? '')
          .toString()
          .compareTo((a['transaction_date'] ?? '').toString()),
    );

    final metrics = computeMetricsForList(
      transactions: results,
      statusCondition: statusCondition,
    );

    return {
      'history': results,
      'omset_kayu': metrics['omset_kayu'] ?? 0,
      'omset_bangunan': metrics['omset_bangunan'] ?? 0,
      'total_bensin': metrics['total_bensin'] ?? 0,
      'kasir_titipan_count': metrics['kasir_titipan_count'] ?? 0,
      'legacy_titipan_count': metrics['legacy_titipan_count'] ?? 0,
      'legacy_titipan_value': metrics['legacy_titipan_value'] ?? 0,
    };
  }

  Map<String, dynamic> _processTransactionDocs({
    required List<QueryDocumentSnapshot> docs,
    required String statusCondition,
    required String start,
    required String end,
    required bool isAllTime,
  }) {
    final List<Map<String, dynamic>> rawMaps = docs
        .map((doc) => Map<String, dynamic>.from(doc.data() as Map))
        .toList();
    return computeHistorySummaryFromMaps(
      rawDocs: rawMaps,
      statusCondition: statusCondition,
      start: start,
      end: end,
      isAllTime: isAllTime,
    );
  }

  /// Stream REAL-TIME riwayat nota (untuk filter harian/mingguan/bulanan/custom/titipan).
  Stream<Map<String, dynamic>> watchFilteredTransactionHistory({
    required String statusCondition,
    required String startDate,
    required String endDate,
  }) {
    final String start = "${startDate}T00:00:00.000";
    final String end = "${endDate}T23:59:59.999";
    final bool isAllTime = startDate == '2000-01-01';

    final Query query = statusCondition == 'TITIPAN'
        ? _col('transactions').where(
            'delivery_status',
            whereIn: ['Belum Diantar', 'Sebagian'],
          )
        : _col('transactions')
            .where('transaction_date', isGreaterThanOrEqualTo: start)
            .where('transaction_date', isLessThanOrEqualTo: end);

    return query.snapshots().map(
          (snap) => _processTransactionDocs(
            docs: snap.docs,
            statusCondition: statusCondition,
            start: start,
            end: end,
            isAllTime: isAllTime,
          ),
        );
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

    return _processTransactionDocs(
      docs: docs,
      statusCondition: statusCondition,
      start: start,
      end: end,
      isAllTime: isAllTime,
    );
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