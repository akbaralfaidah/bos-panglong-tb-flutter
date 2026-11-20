import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../helpers/session_manager.dart';

class DashboardFirebaseDataSource {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  CollectionReference _col(String path) =>
      _db.collection('stores').doc(SessionManager().uid ?? 'UNKNOWN_STORE').collection(path);

  /// Query cepat server-first (timeout 6 detik) dengan fallback otomatis ke cache lokal.
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

  /// Rumus akuntansi harian murni (digunakan oleh query satu-kali maupun stream real-time).
  static Map<String, double> computeDashboardStatsFromMaps({
    required String date,
    required List<Map<String, dynamic>> todayTransactions,
    required List<Map<String, dynamic>> unpaidTransactions,
    required int activeTitipanCount,
    required List<Map<String, dynamic>> allDebtPayments,
    required List<Map<String, dynamic>> todayGasExpenses,
    required List<Map<String, dynamic>> todayStockLogs,
  }) {
    final String startToday = "${date}T00:00:00.000";
    final String endToday = "${date}T23:59:59.999";

    double todayOmsetLunas = 0;
    double todayProfitBarang = 0;
    double todayOngkirMasuk = 0;

    for (var t in todayTransactions) {
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
    for (var t in unpaidTransactions) {
      if (t['is_legacy_titipan'] == true) continue;
      final double tp = (t['total_price'] as num?)?.toDouble() ?? 0;
      totalPiutangKotorAllTime += tp;
      final int? tid = (t['id'] as num?)?.toInt();
      if (tid != null) unpaidTransIds.add(tid);
    }

    double totalCicilanAllTime = 0;
    double totalCicilanMasukHariIni = 0;
    for (var d in allDebtPayments) {
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
    for (var g in todayGasExpenses) {
      todayPengeluaranOperasional += (g['amount'] as num?)?.toDouble() ?? 0;
    }

    double todayBeliStok = 0;
    for (var log in todayStockLogs) {
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
        (totalPiutangKotorAllTime - totalCicilanAllTime)
            .clamp(0.0, double.maxFinite);
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
      'titipanCount': activeTitipanCount.toDouble(),
    };
  }

  static List<Map<String, dynamic>> _docsToMaps(
    List<QueryDocumentSnapshot> docs,
  ) =>
      docs.map((d) => Map<String, dynamic>.from(d.data() as Map)).toList();

  /// Stream REAL-TIME Dashboard untuk Pemilik Toko: angka omset, profit, piutang,
  /// operasional, beli stok, dan jumlah titipan otomatis berubah seketika begitu
  /// karyawan menyelesaikan transaksi di HP lain — tanpa perlu tombol refresh!
  Stream<Map<String, double>> watchSuperDashboardData(String date) {
    final String startToday = "${date}T00:00:00.000";
    final String endToday = "${date}T23:59:59.999";

    late final StreamController<Map<String, double>> controller;
    final List<StreamSubscription<QuerySnapshot>> subs = [];
    Timer? debounce;

    List<Map<String, dynamic>> todayTrans = [];
    List<Map<String, dynamic>> unpaidTrans = [];
    int activeTitipan = 0;
    List<Map<String, dynamic>> debtPayments = [];
    List<Map<String, dynamic>> todayGas = [];
    List<Map<String, dynamic>> todayStocks = [];

    void scheduleEmit() {
      debounce?.cancel();
      debounce = Timer(const Duration(milliseconds: 120), () {
        if (controller.isClosed) return;
        controller.add(
          computeDashboardStatsFromMaps(
            date: date,
            todayTransactions: todayTrans,
            unpaidTransactions: unpaidTrans,
            activeTitipanCount: activeTitipan,
            allDebtPayments: debtPayments,
            todayGasExpenses: todayGas,
            todayStockLogs: todayStocks,
          ),
        );
      });
    }

    controller = StreamController<Map<String, double>>(
      onListen: () {
        subs.add(
          _col('transactions')
              .where('transaction_date', isGreaterThanOrEqualTo: startToday)
              .where('transaction_date', isLessThanOrEqualTo: endToday)
              .snapshots()
              .listen((snap) {
            todayTrans = _docsToMaps(snap.docs);
            scheduleEmit();
          }, onError: (_) {}),
        );
        subs.add(
          _col('transactions')
              .where('payment_status', isNotEqualTo: 'Lunas')
              .snapshots()
              .listen((snap) {
            unpaidTrans = _docsToMaps(snap.docs);
            scheduleEmit();
          }, onError: (_) {}),
        );
        subs.add(
          _col('transactions')
              .where('delivery_status', whereIn: ['Belum Diantar', 'Sebagian'])
              .snapshots()
              .listen((snap) {
            activeTitipan = snap.docs.length;
            scheduleEmit();
          }, onError: (_) {}),
        );
        subs.add(
          _col('debt_payments').snapshots().listen((snap) {
            debtPayments = _docsToMaps(snap.docs);
            scheduleEmit();
          }, onError: (_) {}),
        );
        subs.add(
          _col('gas_expenses')
              .where('date', isGreaterThanOrEqualTo: startToday)
              .where('date', isLessThanOrEqualTo: endToday)
              .snapshots()
              .listen((snap) {
            todayGas = _docsToMaps(snap.docs);
            scheduleEmit();
          }, onError: (_) {}),
        );
        subs.add(
          _col('stock_logs')
              .where('date', isGreaterThanOrEqualTo: startToday)
              .where('date', isLessThanOrEqualTo: endToday)
              .snapshots()
              .listen((snap) {
            todayStocks = _docsToMaps(snap.docs);
            scheduleEmit();
          }, onError: (_) {}),
        );
      },
      onCancel: () async {
        debounce?.cancel();
        for (final sub in subs) {
          await sub.cancel();
        }
        subs.clear();
      },
    );

    return controller.stream;
  }

  /// Stream REAL-TIME jumlah nota barang titipan aktif (dipakai juga di mode Kasir).
  Stream<int> watchActiveTitipanCount() {
    return _col('transactions')
        .where('delivery_status', whereIn: ['Belum Diantar', 'Sebagian'])
        .snapshots()
        .map((snap) => snap.docs.length);
  }

  Future<Map<String, double>> getSuperDashboardData(String date) async {
    final String startToday = "${date}T00:00:00.000";
    final String endToday = "${date}T23:59:59.999";

    final results = await Future.wait([
      _freshOrCache(
        _col('transactions')
            .where('transaction_date', isGreaterThanOrEqualTo: startToday)
            .where('transaction_date', isLessThanOrEqualTo: endToday),
      ),
      _freshOrCache(
        _col('transactions').where('payment_status', isNotEqualTo: 'Lunas'),
      ),
      _freshOrCache(
        _col('transactions').where(
          'delivery_status',
          whereIn: ['Belum Diantar', 'Sebagian'],
        ),
      ),
      _cacheThenSync(_col('debt_payments')),
      _freshOrCache(
        _col('gas_expenses')
            .where('date', isGreaterThanOrEqualTo: startToday)
            .where('date', isLessThanOrEqualTo: endToday),
      ),
      _freshOrCache(
        _col('stock_logs')
            .where('date', isGreaterThanOrEqualTo: startToday)
            .where('date', isLessThanOrEqualTo: endToday),
      ),
    ]);

    return computeDashboardStatsFromMaps(
      date: date,
      todayTransactions: _docsToMaps(results[0]),
      unpaidTransactions: _docsToMaps(results[1]),
      activeTitipanCount: results[2].length,
      allDebtPayments: _docsToMaps(results[3]),
      todayGasExpenses: _docsToMaps(results[4]),
      todayStockLogs: _docsToMaps(results[5]),
    );
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
