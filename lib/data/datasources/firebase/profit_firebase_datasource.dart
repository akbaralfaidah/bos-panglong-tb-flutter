import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../helpers/session_manager.dart';

class ProfitFirebaseDataSource {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  CollectionReference _col(String path) => _db
      .collection('stores')
      .doc(SessionManager().uid ?? 'UNKNOWN_STORE')
      .collection(path);

  Future<List<QueryDocumentSnapshot>> _smartQuery(
    Query q, {
    required bool preferServer,
  }) async {
    if (preferServer) {
      try {
        final sSnap = await q
            .get(const GetOptions(source: Source.server))
            .timeout(const Duration(seconds: 7));
        return sSnap.docs;
      } catch (_) {
        try {
          final cSnap = await q.get(const GetOptions(source: Source.cache));
          return cSnap.docs;
        } catch (_) {
          return [];
        }
      }
    }

    try {
      final cSnap = await q.get(const GetOptions(source: Source.cache));
      if (cSnap.docs.isNotEmpty) {
        q
            .get(const GetOptions(source: Source.server))
            .then((_) => null, onError: (_) => null);
        return cSnap.docs;
      }
    } catch (_) {}

    try {
      final sSnap = await q
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 10));
      return sSnap.docs;
    } catch (_) {
      try {
        final cSnap = await q.get(const GetOptions(source: Source.cache));
        return cSnap.docs;
      } catch (_) {
        return [];
      }
    }
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

  static Map<String, dynamic> buildProfitSummaryFromMaps({
    required List<Map<String, dynamic>> transactions,
    required List<Map<String, dynamic>> gasExpenses,
    required List<Map<String, dynamic>> reinvestments,
  }) {
    double totalProfit = 0;
    double totalOngkir = 0;
    double totalPengeluaran = 0;
    double totalReinvestasi = 0;

    double labaKayu = 0;
    double labaBangunan = 0;

    List<Map<String, dynamic>> historyList = [];

    for (var t in transactions) {
      if (t['is_legacy_titipan'] == true) continue;
      if (t['payment_status'] == 'Lunas') {
        double op = (t['operational_cost'] as num?)?.toDouble() ?? 0;
        double disc = (t['discount'] as num?)?.toDouble() ?? 0;
        totalOngkir += op;

        List<dynamic> items = t['items'] ?? [];
        double trxProfit = 0;

        for (var item in items) {
          if (item is! Map) continue;
          double agreed = 0;
          double capital = 0;
          if (item.containsKey('agreed_total') && item['agreed_total'] != null) {
            agreed = (item['agreed_total'] as num).toDouble();
            capital = (item['capital_total'] as num?)?.toDouble() ?? 0;
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

        double cutProfit = (t['cut_profit'] as num?)?.toDouble() ?? 0;
        totalProfit += (trxProfit - disc - cutProfit);
        double finalLabaTrx = trxProfit + op - disc - cutProfit;

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

    for (var g in gasExpenses) {
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

    for (var r in reinvestments) {
      double amt = (r['amount'] as num?)?.toDouble() ?? 0;
      totalReinvestasi += amt;

      historyList.add({
        'id': r['id'],
        'date': r['date'],
        'type': 'REINVEST',
        'amount': amt.round(),
        'title': 'Alokasi Profit ke Gudang',
        'subtitle': r['note'] ?? 'Subsidi Modal',
        'cashier_name': r['cashier_name'] ?? 'Owner',
      });
    }

    historyList.sort((a, b) {
      final da = DateTime.tryParse((a['date'] ?? '').toString()) ?? DateTime(2000);
      final db = DateTime.tryParse((b['date'] ?? '').toString()) ?? DateTime(2000);
      return db.compareTo(da);
    });

    return {
      'profit_kotor': totalProfit.round(),
      'ongkir_masuk': totalOngkir.round(),
      'pengeluaran': totalPengeluaran.round(),
      'reinvestasi_modal': totalReinvestasi.round(),
      'profit_bersih':
          (totalProfit + totalOngkir - totalPengeluaran - totalReinvestasi)
              .round(),
      'history': historyList,
      'laba_kayu': labaKayu.round(),
      'laba_bangunan': labaBangunan.round(),
    };
  }

  /// Stream REAL-TIME Riwayat Profit & Operasional untuk filter rentang tanggal.
  Stream<Map<String, dynamic>> watchProfitAndExpensesData(
    String startDate,
    String endDate,
  ) {
    final String start = "${startDate}T00:00:00.000";
    final String end = "${endDate}T23:59:59.999";

    late StreamController<Map<String, dynamic>> ctrl;
    final List<StreamSubscription> subs = [];

    List<Map<String, dynamic>> txs = [];
    List<Map<String, dynamic>> gas = [];
    List<Map<String, dynamic>> reinv = [];
    bool hasTx = false;
    bool hasGas = false;
    bool hasReinv = false;
    Timer? debounce;

    void scheduleEmit() {
      if (!hasTx && !hasGas && !hasReinv) return;
      debounce?.cancel();
      debounce = Timer(const Duration(milliseconds: 90), () {
        if (!ctrl.isClosed) {
          ctrl.add(
            buildProfitSummaryFromMaps(
              transactions: txs,
              gasExpenses: gas,
              reinvestments: reinv,
            ),
          );
        }
      });
    }

    ctrl = StreamController<Map<String, dynamic>>(
      onListen: () {
        subs.add(
          _col('transactions')
              .where('transaction_date', isGreaterThanOrEqualTo: start)
              .where('transaction_date', isLessThanOrEqualTo: end)
              .snapshots()
              .listen(
                (snap) {
                  txs = snap.docs
                      .map((d) => Map<String, dynamic>.from(d.data() as Map))
                      .toList();
                  hasTx = true;
                  scheduleEmit();
                },
                onError: (e) {
                  if (!ctrl.isClosed) ctrl.addError(e);
                },
              ),
        );

        subs.add(
          _col('gas_expenses')
              .where('date', isGreaterThanOrEqualTo: start)
              .where('date', isLessThanOrEqualTo: end)
              .snapshots()
              .listen(
                (snap) {
                  gas = snap.docs
                      .map((d) => Map<String, dynamic>.from(d.data() as Map))
                      .toList();
                  hasGas = true;
                  scheduleEmit();
                },
                onError: (_) {},
              ),
        );

        subs.add(
          _col('reinvestasi_modal')
              .where('date', isGreaterThanOrEqualTo: start)
              .where('date', isLessThanOrEqualTo: end)
              .snapshots()
              .listen(
                (snap) {
                  reinv = snap.docs
                      .map((d) => Map<String, dynamic>.from(d.data() as Map))
                      .toList();
                  hasReinv = true;
                  scheduleEmit();
                },
                onError: (_) {},
              ),
        );
      },
      onCancel: () async {
        debounce?.cancel();
        for (final s in subs) {
          await s.cancel();
        }
      },
    );

    return ctrl.stream;
  }

  Future<Map<String, dynamic>> getProfitAndExpensesData(
    String startDate,
    String endDate,
  ) async {
    String start = "${startDate}T00:00:00.000";
    String end = "${endDate}T23:59:59.999";
    final bool preferServer = startDate != '2000-01-01';

    final results = await Future.wait([
      _smartQuery(
        _col('transactions')
            .where('transaction_date', isGreaterThanOrEqualTo: start)
            .where('transaction_date', isLessThanOrEqualTo: end),
        preferServer: preferServer,
      ),
      _smartQuery(
        _col('gas_expenses')
            .where('date', isGreaterThanOrEqualTo: start)
            .where('date', isLessThanOrEqualTo: end),
        preferServer: preferServer,
      ),
      _smartQuery(
        _col('reinvestasi_modal')
            .where('date', isGreaterThanOrEqualTo: start)
            .where('date', isLessThanOrEqualTo: end),
        preferServer: preferServer,
      ),
    ]);

    return buildProfitSummaryFromMaps(
      transactions: results[0]
          .map((d) => Map<String, dynamic>.from(d.data() as Map))
          .toList(),
      gasExpenses: results[1]
          .map((d) => Map<String, dynamic>.from(d.data() as Map))
          .toList(),
      reinvestments: results[2]
          .map((d) => Map<String, dynamic>.from(d.data() as Map))
          .toList(),
    );
  }
}