import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../helpers/session_manager.dart';

class DashboardFirebaseDataSource {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  CollectionReference _col(String path) =>
      _db.collection('stores').doc(SessionManager().uid ?? 'UNKNOWN_STORE').collection(path);

  /// Query cepat server-first (timeout 6 detik) dengan fallback otomatis ke cache lokal.
  /// Digunakan khusus pada query terfilter (hari ini / hutang aktif / titipan aktif)
  /// agar data transaksi baru dari HP karyawan langsung muncul tanpa menyedot ribuan dokumen lama!
  Future<List<QueryDocumentSnapshot>> _freshOrCache(Query q) async {
    try {
      final snap = await q
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 6));
      return snap.docs;
    } catch (_) {
      try {
        final cacheSnap = await q.get(const GetOptions(source: Source.cache));
        return cacheSnap.docs;
      } catch (_) {
        return [];
      }
    }
  }

  /// Query cache-first untuk koleksi sekunder yang relatif kecil (seperti `debt_payments`).
  Future<List<QueryDocumentSnapshot>> _cacheThenSync(Query q) async {
    try {
      final cacheSnap = await q.get(const GetOptions(source: Source.cache));
      if (cacheSnap.docs.isNotEmpty) {
        q
            .get(const GetOptions(source: Source.server))
            .then((_) => null, onError: (_) => null);
        return cacheSnap.docs;
      }
    } catch (_) {}
    return _freshOrCache(q);
  }

  // 🔥 MESIN SUPER PARALEL & RINGAN (TANPA SEDOT RIBUAN TRANSAKSI LAMA!)
  Future<Map<String, double>> getSuperDashboardData(String date) async {
    final String startToday = "${date}T00:00:00.000";
    final String endToday = "${date}T23:59:59.999";

    // Jalankan 6 query terfilter secara PARALEL (total ~20-60 dokumen, bukan ribuan!)
    final results = await Future.wait([
      // 0: Transaksi hari ini saja (fresh dari server agar transaksi karyawan langsung masuk!)
      _freshOrCache(
        _col('transactions')
            .where('transaction_date', isGreaterThanOrEqualTo: startToday)
            .where('transaction_date', isLessThanOrEqualTo: endToday),
      ),
      // 1: Transaksi belum lunas (piutang aktif)
      _freshOrCache(
        _col('transactions').where('payment_status', isNotEqualTo: 'Lunas'),
      ),
      // 2: Barang titipan aktif (belum selesai diantar)
      _freshOrCache(
        _col('transactions').where(
          'delivery_status',
          whereIn: ['Belum Diantar', 'Sebagian'],
        ),
      ),
      // 3: Cicilan piutang (untuk sisa piutang + cicilan masuk hari ini)
      _cacheThenSync(_col('debt_payments')),
      // 4: Pengeluaran operasional hari ini saja
      _freshOrCache(
        _col('gas_expenses')
            .where('date', isGreaterThanOrEqualTo: startToday)
            .where('date', isLessThanOrEqualTo: endToday),
      ),
      // 5: Stok masuk hari ini saja
      _freshOrCache(
        _col('stock_logs')
            .where('date', isGreaterThanOrEqualTo: startToday)
            .where('date', isLessThanOrEqualTo: endToday),
      ),
    ]);

    final todayTransDocs = results[0];
    final unpaidTransDocs = results[1];
    final activeTitipanDocs = results[2];
    final allDebtPaymentDocs = results[3];
    final todayGasDocs = results[4];
    final todayStockDocs = results[5];

    double todayOmsetLunas = 0;
    double todayProfitBarang = 0;
    double todayOngkirMasuk = 0;

    for (var doc in todayTransDocs) {
      final t = doc.data() as Map<String, dynamic>;
      if (t['is_legacy_titipan'] == true) continue;
      if (t['payment_status'] != 'Lunas') continue;

      final double tp = (t['total_price'] as num?)?.toDouble() ?? 0;
      final double op = (t['operational_cost'] as num?)?.toDouble() ?? 0;
      final double disc = (t['discount'] as num?)?.toDouble() ?? 0;

      todayOmsetLunas += (tp - op);
      todayOngkirMasuk += op;

      final List<dynamic> items = t['items'] ?? [];
      double trxProfit = 0;
      for (var item in items) {
        double agreed = 0;
        double capital = 0;

        if (item.containsKey('agreed_total') && item['agreed_total'] != null) {
          agreed = (item['agreed_total'] as num).toDouble();
          capital = (item['capital_total'] as num?)?.toDouble() ?? 0;
        } else {
          final double sell = (item['sell_price'] as num?)?.toDouble() ?? 0;
          double cap = (item['capital_price'] as num?)?.toDouble() ?? 0;
          final double qty = (item['quantity'] as num?)?.toDouble() ?? 0;
          final double reqQty = (item['request_qty'] as num?)?.toDouble() ?? 0;
          if (reqQty > 0 && reqQty != qty && cap > (sell * 5)) {
            cap = cap / (qty / reqQty);
          }
          agreed = sell * qty;
          capital = cap * qty;
        }
        trxProfit += (agreed - capital);
      }
      todayProfitBarang += (trxProfit - disc);
    }

    double totalPiutangKotorAllTime = 0;
    final Set<int> unpaidTransIds = {};
    for (var doc in unpaidTransDocs) {
      final t = doc.data() as Map<String, dynamic>;
      if (t['is_legacy_titipan'] == true) continue;
      final double tp = (t['total_price'] as num?)?.toDouble() ?? 0;
      totalPiutangKotorAllTime += tp;
      final int? tid = (t['id'] as num?)?.toInt();
      if (tid != null) unpaidTransIds.add(tid);
    }

    double totalCicilanAllTime = 0;
    double totalCicilanMasukHariIni = 0;
    for (var doc in allDebtPaymentDocs) {
      final d = doc.data() as Map<String, dynamic>;
      final double amount = (d['amount_paid'] as num?)?.toDouble() ?? 0;
      final String pDate = (d['payment_date'] ?? '').toString();
      final int? tid = (d['transaction_id'] as num?)?.toInt();

      if (tid != null && unpaidTransIds.contains(tid)) {
        totalCicilanAllTime += amount;
      }
      if (pDate.compareTo(startToday) >= 0 && pDate.compareTo(endToday) <= 0) {
        totalCicilanMasukHariIni += amount;
      }
    }

    double todayPengeluaranOperasional = 0;
    for (var doc in todayGasDocs) {
      final g = doc.data() as Map<String, dynamic>;
      todayPengeluaranOperasional += (g['amount'] as num?)?.toDouble() ?? 0;
    }

    double todayBeliStok = 0;
    for (var doc in todayStockDocs) {
      final log = doc.data() as Map<String, dynamic>;
      final double qty = (log['quantity'] as num?)?.toDouble() ?? 0;
      final double price = (log['price'] as num?)?.toDouble() ?? 0;
      final double itemTotal =
          log.containsKey('total_price') && log['total_price'] != null
              ? (log['total_price'] as num).toDouble()
              : (qty * price).roundToDouble();
      todayBeliStok += itemTotal;
    }

    final double finalOmsetHarian = todayOmsetLunas + totalCicilanMasukHariIni;
    final double finalSisaPiutang =
        (totalPiutangKotorAllTime - totalCicilanAllTime).clamp(0.0, double.maxFinite);
    final double saldoOperasionalHarian =
        todayOngkirMasuk - todayPengeluaranOperasional;
    final double finalProfitBersihHarian =
        todayProfitBarang + todayOngkirMasuk - todayPengeluaranOperasional;

    return {
      'omsetKotor': finalOmsetHarian,
      'profitBersih': finalProfitBersihHarian,
      'uangOperasional': saldoOperasionalHarian,
      'totalPiutang': finalSisaPiutang,
      'totalBeliStok': todayBeliStok,
      'titipanCount': activeTitipanDocs.length.toDouble(),
    };
  }

  Future<int> getActiveTitipanCount() async {
    final docs = await _freshOrCache(
      _col('transactions').where(
        'delivery_status',
        whereIn: ['Belum Diantar', 'Sebagian'],
      ),
    );
    return docs.length;
  }
}
