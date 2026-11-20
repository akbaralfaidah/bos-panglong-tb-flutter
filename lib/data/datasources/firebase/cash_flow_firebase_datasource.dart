import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../helpers/session_manager.dart';

class CashFlowFirebaseDataSource {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  CollectionReference _col(String path) =>
      _db.collection('stores').doc(SessionManager().uid ?? 'UNKNOWN_STORE').collection(path);

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

  Future<DocumentSnapshot?> _safeDoc(DocumentReference d) async {
    try {
      final sSnap = await d
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 5));
      return sSnap.exists ? sSnap : null;
    } catch (_) {
      try {
        final cSnap = await d.get(const GetOptions(source: Source.cache));
        return cSnap.exists ? cSnap : null;
      } catch (_) {
        return null;
      }
    }
  }

  Future<List<Map<String, dynamic>>> getAllTransactions({
    String? startIso,
    String? endIso,
    bool preferServer = true,
  }) async {
    Query q = _col('transactions');
    if (startIso != null && endIso != null) {
      q = q
          .where('transaction_date', isGreaterThanOrEqualTo: startIso)
          .where('transaction_date', isLessThanOrEqualTo: endIso);
    }
    final docs = await _smartQuery(q, preferServer: preferServer);
    return docs
        .map((doc) => Map<String, dynamic>.from(doc.data() as Map))
        .where((t) => t['is_legacy_titipan'] != true)
        .toList();
  }

  Future<List<Map<String, dynamic>>> getAllDebtPayments({
    String? startIso,
    String? endIso,
    bool preferServer = true,
  }) async {
    Query q = _col('debt_payments');
    if (startIso != null && endIso != null) {
      q = q
          .where('payment_date', isGreaterThanOrEqualTo: startIso)
          .where('payment_date', isLessThanOrEqualTo: endIso);
    }
    final docs = await _smartQuery(q, preferServer: preferServer);
    return docs
        .map((doc) => Map<String, dynamic>.from(doc.data() as Map))
        .toList();
  }

  Future<List<Map<String, dynamic>>> getAllStockLogsWithProducts({
    String? startIso,
    String? endIso,
    bool preferServer = true,
  }) async {
    Query sQuery = _col('stock_logs');
    if (startIso != null && endIso != null) {
      sQuery = sQuery
          .where('date', isGreaterThanOrEqualTo: startIso)
          .where('date', isLessThanOrEqualTo: endIso);
    }

    final results = await Future.wait([
      _smartQuery(sQuery, preferServer: preferServer),
      // Daftar produk hampir selalu ada di cache & berubah jarang -> cache-first cepat
      _smartQuery(_col('products'), preferServer: false),
    ]);

    final sDocs = results[0];
    final pDocs = results[1];

    final Map<int, Map<String, dynamic>> productMap = {};
    for (var p in pDocs) {
      final pData = Map<String, dynamic>.from(p.data() as Map);
      final int? pid = (pData['id'] as num?)?.toInt();
      if (pid != null) {
        productMap[pid] = pData;
      }
    }

    final List<Map<String, dynamic>> joined = [];
    for (var s in sDocs) {
      final log = Map<String, dynamic>.from(s.data() as Map);
      final int? pid = (log['product_id'] as num?)?.toInt();
      final prod = pid != null ? productMap[pid] : null;

      final double qty = (log['quantity'] as num?)?.toDouble() ?? 0;
      final double price = (log['price'] as num?)?.toDouble() ?? 0;

      final double itemTotal =
          log.containsKey('total_price') && log['total_price'] != null
              ? (log['total_price'] as num).toDouble()
              : (qty * price).roundToDouble();

      log['total_price'] = itemTotal;

      if (prod != null) {
        log['product_name'] = prod['name'];
        log['product_category'] = prod['type'];
      } else {
        log['product_name'] = 'Produk Dihapus';
        log['product_category'] = 'UNKNOWN';
      }
      joined.add(log);
    }
    return joined;
  }

  Future<List<Map<String, dynamic>>> getAllGasExpenses({
    String? startIso,
    String? endIso,
    bool preferServer = true,
  }) async {
    Query q = _col('gas_expenses');
    if (startIso != null && endIso != null) {
      q = q
          .where('date', isGreaterThanOrEqualTo: startIso)
          .where('date', isLessThanOrEqualTo: endIso);
    }
    final docs = await _smartQuery(q, preferServer: preferServer);
    return docs
        .map((doc) => Map<String, dynamic>.from(doc.data() as Map))
        .toList();
  }

  /// Stream REAL-TIME untuk 4 koleksi arus kas dalam rentang tanggal aktif.
  /// Menggabungkan hasil secara langsung saat karyawan membuat transaksi di HP lain!
  Stream<({
    List<Map<String, dynamic>> transactions,
    List<Map<String, dynamic>> debtPayments,
    List<Map<String, dynamic>> stockLogs,
    List<Map<String, dynamic>> gasExpenses,
  })> watchDateRangeData({
    required String startIso,
    required String endIso,
  }) {
    late final StreamController<({
      List<Map<String, dynamic>> transactions,
      List<Map<String, dynamic>> debtPayments,
      List<Map<String, dynamic>> stockLogs,
      List<Map<String, dynamic>> gasExpenses,
    })> controller;

    final List<StreamSubscription<QuerySnapshot>> subs = [];
    Timer? debounce;

    List<Map<String, dynamic>> trans = [];
    List<Map<String, dynamic>> debts = [];
    List<Map<String, dynamic>> rawStocks = [];
    List<Map<String, dynamic>> gas = [];
    Map<int, Map<String, dynamic>> productMap = {};

    List<Map<String, dynamic>> joinStocks() {
      final List<Map<String, dynamic>> joined = [];
      for (var raw in rawStocks) {
        final log = Map<String, dynamic>.from(raw);
        final int? pid = (log['product_id'] as num?)?.toInt();
        final prod = pid != null ? productMap[pid] : null;
        final double qty = (log['quantity'] as num?)?.toDouble() ?? 0;
        final double price = (log['price'] as num?)?.toDouble() ?? 0;
        final double itemTotal =
            log.containsKey('total_price') && log['total_price'] != null
                ? (log['total_price'] as num).toDouble()
                : (qty * price).roundToDouble();
        log['total_price'] = itemTotal;
        if (prod != null) {
          log['product_name'] = prod['name'];
          log['product_category'] = prod['type'];
        } else {
          log['product_name'] = 'Produk Dihapus';
          log['product_category'] = 'UNKNOWN';
        }
        joined.add(log);
      }
      return joined;
    }

    void scheduleEmit() {
      debounce?.cancel();
      debounce = Timer(const Duration(milliseconds: 120), () {
        if (controller.isClosed) return;
        controller.add((
          transactions: trans,
          debtPayments: debts,
          stockLogs: joinStocks(),
          gasExpenses: gas,
        ));
      });
    }

    controller = StreamController(
      onListen: () {
        // Muat peta nama produk sekali dari cache/server
        _smartQuery(_col('products'), preferServer: false).then((pDocs) {
          final Map<int, Map<String, dynamic>> nextMap = {};
          for (var p in pDocs) {
            final pData = Map<String, dynamic>.from(p.data() as Map);
            final int? pid = (pData['id'] as num?)?.toInt();
            if (pid != null) nextMap[pid] = pData;
          }
          productMap = nextMap;
          if (rawStocks.isNotEmpty) scheduleEmit();
        });

        subs.add(
          _col('transactions')
              .where('transaction_date', isGreaterThanOrEqualTo: startIso)
              .where('transaction_date', isLessThanOrEqualTo: endIso)
              .snapshots()
              .listen((snap) {
            trans = snap.docs
                .map((d) => Map<String, dynamic>.from(d.data() as Map))
                .where((t) => t['is_legacy_titipan'] != true)
                .toList();
            scheduleEmit();
          }, onError: (_) {}),
        );

        subs.add(
          _col('debt_payments')
              .where('payment_date', isGreaterThanOrEqualTo: startIso)
              .where('payment_date', isLessThanOrEqualTo: endIso)
              .snapshots()
              .listen((snap) {
            debts = snap.docs
                .map((d) => Map<String, dynamic>.from(d.data() as Map))
                .toList();
            scheduleEmit();
          }, onError: (_) {}),
        );

        subs.add(
          _col('stock_logs')
              .where('date', isGreaterThanOrEqualTo: startIso)
              .where('date', isLessThanOrEqualTo: endIso)
              .snapshots()
              .listen((snap) {
            rawStocks = snap.docs
                .map((d) => Map<String, dynamic>.from(d.data() as Map))
                .toList();
            scheduleEmit();
          }, onError: (_) {}),
        );

        subs.add(
          _col('gas_expenses')
              .where('date', isGreaterThanOrEqualTo: startIso)
              .where('date', isLessThanOrEqualTo: endIso)
              .snapshots()
              .listen((snap) {
            gas = snap.docs
                .map((d) => Map<String, dynamic>.from(d.data() as Map))
                .toList();
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

  Future<Map<String, dynamic>?> getTransactionById(int id) async {
    final doc = await _safeDoc(_col('transactions').doc(id.toString()));
    if (doc != null && doc.exists && doc.data() != null) {
      return Map<String, dynamic>.from(doc.data() as Map);
    }
    return null;
  }
}
