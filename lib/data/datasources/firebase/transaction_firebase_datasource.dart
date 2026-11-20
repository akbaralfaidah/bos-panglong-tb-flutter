import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../helpers/session_manager.dart';
import '../../../models/product.dart';

class TransactionFirebaseDataSource {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  CollectionReference _col(String path) => _db.collection('stores').doc(SessionManager().uid ?? 'UNKNOWN_STORE').collection(path);

  Future<List<QueryDocumentSnapshot>> _safeQuery(
    Query q, {
    bool preferServer = true,
  }) async {
    if (preferServer) {
      try {
        final serverSnap = await q
            .get(const GetOptions(source: Source.server))
            .timeout(const Duration(seconds: 5));
        return serverSnap.docs;
      } catch (_) {
        try {
          final snap = await q.get(const GetOptions(source: Source.cache));
          return snap.docs;
        } catch (_) {
          return [];
        }
      }
    }
    q.get(const GetOptions(source: Source.server)).then((_) => null, onError: (_) => null);
    try {
      final snap = await q.get(const GetOptions(source: Source.cache));
      return snap.docs;
    } catch (_) {
      return [];
    }
  }

  Future<Map<String, dynamic>?> getTransactionById(int id) async {
    final docRef = _col('transactions').doc(id.toString());
    try {
      DocumentSnapshot snap;
      try {
        snap = await docRef
            .get(const GetOptions(source: Source.server))
            .timeout(const Duration(seconds: 4));
      } catch (_) {
        snap = await docRef.get(const GetOptions(source: Source.cache));
      }
      if (snap.exists && snap.data() != null) {
        return Map<String, dynamic>.from(snap.data() as Map);
      }
    } catch (_) {}

    final docs = await _safeQuery(
      _col('transactions').where('id', isEqualTo: id),
      preferServer: true,
    );
    if (docs.isNotEmpty) {
      return Map<String, dynamic>.from(docs.first.data() as Map);
    }
    return null;
  }

  Future<List<Map<String, dynamic>>> getDebtPayments(int transId) async {
    final docs = await _safeQuery(
      _col('debt_payments').where('transaction_id', isEqualTo: transId),
      preferServer: true,
    );
    List<Map<String, dynamic>> results = docs
        .map((doc) => Map<String, dynamic>.from(doc.data() as Map))
        .toList();
    results.sort(
      (a, b) => (a['payment_date'] ?? '').toString().compareTo(
        (b['payment_date'] ?? '').toString(),
      ),
    );
    return results;
  }

  double _getItemCapitalTotal(Map<String, dynamic> item) {
    if (item.containsKey('capital_total') && item['capital_total'] != null) {
      return (item['capital_total'] as num).toDouble();
    }
    double reqQty = (item['request_qty'] as num?)?.toDouble() ??
        (item['quantity'] as num?)?.toDouble() ??
        1.0;
    double cap = (item['capital_price'] as num?)?.toDouble() ?? 0;
    return (reqQty * cap).roundToDouble();
  }

  double _getUndeliveredQty(Map<String, dynamic> item) {
    double qty = (item['quantity'] as num?)?.toDouble() ?? 0.0;
    double delivered = item.containsKey('delivered_qty') && item['delivered_qty'] != null
        ? (item['delivered_qty'] as num).toDouble()
        : qty; // backward compatibility: transaksi lama dianggap sudah diantar
    return double.parse((qty - delivered).clamp(0.0, qty).toStringAsFixed(2));
  }

  Future<double> _readCurrentReservedStock(String productId) async {
    final docRef = _col('products').doc(productId);
    try {
      DocumentSnapshot snap;
      try {
        snap = await docRef
            .get(const GetOptions(source: Source.server))
            .timeout(const Duration(seconds: 3));
      } catch (_) {
        snap = await docRef.get(const GetOptions(source: Source.cache));
      }
      if (snap.exists && snap.data() != null) {
        final data = snap.data() as Map<String, dynamic>;
        return (data['reserved_stock'] as num?)?.toDouble() ?? 0.0;
      }
    } catch (_) {}
    return 0.0;
  }

  Future<void> payDebt(int transId, int amount, String note) async {
    int paymentId = DateTime.now().millisecondsSinceEpoch;
    String dateNow = DateTime.now().toIso8601String();
    String currentCashier = SessionManager().userName ?? 'Tidak Diketahui';
    
    bool isLunas = false;
    final tDocs = await _safeQuery(_col('transactions').where('id', isEqualTo: transId));
    Map<String, dynamic>? transData;

    if (tDocs.isNotEmpty) {
      transData = tDocs.first.data() as Map<String, dynamic>;
      int tp = (transData['total_price'] as num?)?.toInt() ?? 0;
      
      final pDocs = await _safeQuery(_col('debt_payments').where('transaction_id', isEqualTo: transId));
      int dicicil = amount; 
      for (var p in pDocs) {
         var pd = p.data() as Map<String, dynamic>;
         dicicil += (pd['amount_paid'] as num?)?.toInt() ?? 0;
      }
      if (dicicil >= tp) isLunas = true;
    }

    WriteBatch batch = _db.batch();
    batch.set(_col('debt_payments').doc(paymentId.toString()), { 
      'id': paymentId, 'transaction_id': transId, 'amount_paid': amount, 
      'note': note, 'payment_date': dateNow, 'cashier_name': currentCashier 
    });
    
    if (isLunas) {
      batch.update(_col('transactions').doc(transId.toString()), {'payment_status': 'Lunas'});
      
      if (transData != null) {
        List<dynamic> items = transData['items'] ?? [];
        for (var rawItem in items) {
          var item = Map<String, dynamic>.from(rawItem as Map);
          double capTotal = _getItemCapitalTotal(item);
          if (item['product_id'] != null && capTotal > 0) {
            batch.set(_col('products').doc(item['product_id'].toString()), {
              'modal_cair': FieldValue.increment(capTotal) 
            }, SetOptions(merge: true));
          }
        }
      }
    }
    await batch.commit(); 
  }

  // 🔥 DOBRAK FIREBASE: BATALIN TRANSAKSI = MODAL KETARIK / NGURANG (-) & LEPAS TITIPAN 🔥
  Future<void> voidTransaction(int transId, List<Map<String, dynamic>> items) async {
    WriteBatch batch = _db.batch();

    bool wasLunas = false;
    bool isLegacyTitipan = false;
    bool deductedFromStock = true;
    List<Map<String, dynamic>> dbItems = items;
    final tDocs = await _safeQuery(_col('transactions').where('id', isEqualTo: transId));
    if (tDocs.isNotEmpty) {
       var tData = tDocs.first.data() as Map<String, dynamic>;
       wasLunas = (tData['payment_status'] ?? '').toString().toLowerCase() == 'lunas';
       isLegacyTitipan = tData['is_legacy_titipan'] == true;
       deductedFromStock = tData['deducted_from_stock'] != false;
       if (tData['items'] != null && (tData['items'] as List).isNotEmpty) {
         dbItems = List<Map<String, dynamic>>.from(
           (tData['items'] as List).map((e) => Map<String, dynamic>.from(e as Map)),
         );
       }
    }

    Map<String, double> stockRestoreByProduct = {};
    Map<String, double> modalReverseByProduct = {};
    Map<String, double> undeliveredByProduct = {};

    for (var item in dbItems) {
      if (item['product_id'] != null && item['quantity'] != null) {
        final String pid = item['product_id'].toString();
        final double qtyToRestore = (item['quantity'] as num).toDouble();
        final double capTotal = _getItemCapitalTotal(item);
        final double undeliveredToRelease = _getUndeliveredQty(item);

        if (!isLegacyTitipan || deductedFromStock) {
          stockRestoreByProduct[pid] =
              (stockRestoreByProduct[pid] ?? 0.0) + qtyToRestore;
        }
        if (wasLunas && !isLegacyTitipan && capTotal > 0) {
          modalReverseByProduct[pid] =
              (modalReverseByProduct[pid] ?? 0.0) + capTotal;
        }
        if (undeliveredToRelease > 0) {
          undeliveredByProduct[pid] =
              (undeliveredByProduct[pid] ?? 0.0) + undeliveredToRelease;
        }
      }
    }

    final Set<String> affectedProductIds = {
      ...stockRestoreByProduct.keys,
      ...modalReverseByProduct.keys,
      ...undeliveredByProduct.keys,
    };

    for (final pid in affectedProductIds) {
      final DocumentReference prodRef = _col('products').doc(pid);
      final Map<String, dynamic> updateMap = {};
      if (stockRestoreByProduct.containsKey(pid)) {
        updateMap['stock'] = FieldValue.increment(stockRestoreByProduct[pid]!);
      }
      if (modalReverseByProduct.containsKey(pid)) {
        // KARENA BATAL JUAL, DUIT MODAL DITARIK LAGI BIAR GAK MINUS! (-)
        updateMap['modal_cair'] = FieldValue.increment(-modalReverseByProduct[pid]!);
      }
      if (undeliveredByProduct.containsKey(pid)) {
        final double currentReserved = await _readCurrentReservedStock(pid);
        updateMap['reserved_stock'] = Product.clampReleasedReservedStock(
          currentReserved: currentReserved,
          releaseQty: undeliveredByProduct[pid]!,
        );
      }
      if (updateMap.isNotEmpty) {
        batch.set(prodRef, updateMap, SetOptions(merge: true));
      }
    }

    final pDocs = await _safeQuery(_col('debt_payments').where('transaction_id', isEqualTo: transId));
    for (var p in pDocs) { batch.delete(p.reference); }

    batch.delete(_col('transactions').doc(transId.toString()));
    await batch.commit();
  }

  // 🔥 EDIT TRANSAKSI: REVERSE LAMA, APPLY BARU 🔥
  Future<void> updateTransaction(
    int transId, 
    List<Map<String, dynamic>> oldItems, 
    List<Map<String, dynamic>> newItems,
    Map<String, dynamic> updatedTransData,
  ) async {
    WriteBatch batch = _db.batch();

    bool wasLunas = false;
    final tDocs = await _safeQuery(_col('transactions').where('id', isEqualTo: transId));
    if (tDocs.isNotEmpty) {
       var tData = tDocs.first.data() as Map<String, dynamic>;
       wasLunas = (tData['payment_status'] ?? '').toString().toLowerCase() == 'lunas';
    }

    bool isNowLunas = (updatedTransData['payment_status'] ?? '').toString().toLowerCase() == 'lunas';

    // Gabungkan selisih stok, modal_cair, dan reserved_stock per produk agar 1x write per doc & reserved_stock >= 0
    final Map<String, double> stockDeltaByProduct = {};
    final Map<String, double> modalDeltaByProduct = {};
    final Map<String, double> reservedDeltaByProduct = {};

    // 1. REVERSE OLD ITEMS (Kembalikan stok, lepas titipan lama, & tarik modal)
    for (var item in oldItems) {
      if (item['product_id'] != null && item['quantity'] != null) {
        final String pid = item['product_id'].toString();
        final double qtyToRestore = (item['quantity'] as num).toDouble();
        final double capTotal = _getItemCapitalTotal(item);
        final double oldUndelivered = _getUndeliveredQty(item);

        stockDeltaByProduct[pid] = (stockDeltaByProduct[pid] ?? 0.0) + qtyToRestore;
        if (wasLunas && capTotal > 0) {
          modalDeltaByProduct[pid] = (modalDeltaByProduct[pid] ?? 0.0) - capTotal;
        }
        if (oldUndelivered > 0) {
          reservedDeltaByProduct[pid] =
              (reservedDeltaByProduct[pid] ?? 0.0) - oldUndelivered;
        }
      }
    }

    // 2. APPLY NEW ITEMS (Potong stok, tambah titipan baru, & tambah modal)
    for (var item in newItems) {
      if (item['product_id'] != null && item['quantity'] != null) {
        final String pid = item['product_id'].toString();
        final double qtyToDeduct = (item['quantity'] as num).toDouble();
        final double capTotal = _getItemCapitalTotal(item);
        final double newUndelivered = _getUndeliveredQty(item);

        stockDeltaByProduct[pid] = (stockDeltaByProduct[pid] ?? 0.0) - qtyToDeduct;
        if (isNowLunas && capTotal > 0) {
          modalDeltaByProduct[pid] = (modalDeltaByProduct[pid] ?? 0.0) + capTotal;
        }
        if (newUndelivered > 0) {
          reservedDeltaByProduct[pid] =
              (reservedDeltaByProduct[pid] ?? 0.0) + newUndelivered;
        }
      }
    }

    final Set<String> affectedProductIds = {
      ...stockDeltaByProduct.keys,
      ...modalDeltaByProduct.keys,
      ...reservedDeltaByProduct.keys,
    };

    for (final pid in affectedProductIds) {
      final DocumentReference prodRef = _col('products').doc(pid);
      final Map<String, dynamic> updateMap = {};
      final double stockDelta = stockDeltaByProduct[pid] ?? 0.0;
      final double modalDelta = modalDeltaByProduct[pid] ?? 0.0;
      final double reservedDelta = reservedDeltaByProduct[pid] ?? 0.0;

      if (stockDelta.abs() > 0.0001) {
        updateMap['stock'] = FieldValue.increment(stockDelta);
      }
      if (modalDelta.abs() > 0.0001) {
        updateMap['modal_cair'] = FieldValue.increment(modalDelta);
      }
      if (reservedDelta.abs() > 0.0001) {
        final double currentReserved = await _readCurrentReservedStock(pid);
        updateMap['reserved_stock'] = Product.clampReservedStockDelta(
          currentReserved: currentReserved,
          delta: reservedDelta,
        );
      }
      if (updateMap.isNotEmpty) {
        batch.set(prodRef, updateMap, SetOptions(merge: true));
      }
    }

    // 3. JIKA STATUS BERUBAH DARI LUNAS → HUTANG: HAPUS SEMUA DEBT PAYMENTS
    if (wasLunas && !isNowLunas) {
      final pDocs = await _safeQuery(_col('debt_payments').where('transaction_id', isEqualTo: transId));
      for (var p in pDocs) {
        batch.delete(p.reference);
      }
    }

    // 4. UPDATE TRANSACTION DOC
    batch.update(_col('transactions').doc(transId.toString()), updatedTransData);

    await batch.commit();
  }

  // 🔥 UPDATE PENGIRIMAN / PENGAMBILAN BARANG TITIPAN (BERTAHAP / SEKALIGUS) 🔥
  Future<Map<String, dynamic>> updateDeliveryProgress({
    required int transId,
    required List<Map<String, dynamic>> updatedItems,
    required List<Map<String, dynamic>> newlyDeliveredSummary,
    String note = '',
  }) async {
    DocumentReference transRef = _col('transactions').doc(transId.toString());
    Map<String, dynamic> existingTrans = {};
    try {
      final snap = await transRef.get(const GetOptions(source: Source.server)).timeout(const Duration(seconds: 4));
      if (snap.exists && snap.data() != null) {
        existingTrans = Map<String, dynamic>.from(snap.data() as Map);
      }
    } catch (_) {
      final snap = await transRef.get(const GetOptions(source: Source.cache));
      if (snap.exists && snap.data() != null) {
        existingTrans = Map<String, dynamic>.from(snap.data() as Map);
      }
    }

    bool allDelivered = true;
    bool noneDelivered = true;
    for (var item in updatedItems) {
      double qty = (item['quantity'] as num?)?.toDouble() ?? 0.0;
      double del = item.containsKey('delivered_qty') && item['delivered_qty'] != null
          ? (item['delivered_qty'] as num).toDouble()
          : qty;
      if (del < qty - 0.01) allDelivered = false;
      if (del > 0.01) noneDelivered = false;
    }

    String newDeliveryStatus = allDelivered
        ? 'Selesai'
        : (noneDelivered ? 'Belum Diantar' : 'Sebagian');

    List<Map<String, dynamic>> existingLogs = [];
    if (existingTrans['delivery_logs'] != null && existingTrans['delivery_logs'] is List) {
      existingLogs = List<Map<String, dynamic>>.from(
        (existingTrans['delivery_logs'] as List).map((e) => Map<String, dynamic>.from(e as Map)),
      );
    }

    if (newlyDeliveredSummary.isNotEmpty) {
      existingLogs.add({
        'date': DateTime.now().toIso8601String(),
        'cashier_name': SessionManager().userName ?? 'Admin',
        'note': note.trim(),
        'items': newlyDeliveredSummary.map((e) => {
          'product_name': e['product_name'],
          'delivered_req_qty': e['delivered_req_qty'],
          'unit_type': e['unit_type'],
        }).toList(),
      });
    }

    WriteBatch batch = _db.batch();

    // Kurangi reserved_stock di gudang sesuai jumlah fisik yang keluar
    Map<String, double> releaseByProduct = {};
    for (var entry in newlyDeliveredSummary) {
      if (entry['product_id'] != null) {
        double releaseQty = (entry['newly_delivered_qty'] as num?)?.toDouble() ?? 0.0;
        if (releaseQty > 0) {
          String pid = entry['product_id'].toString();
          releaseByProduct[pid] = (releaseByProduct[pid] ?? 0.0) + releaseQty;
        }
      }
    }

    for (var entry in releaseByProduct.entries) {
      final double currentReserved = await _readCurrentReservedStock(entry.key);
      final double nextReserved = Product.clampReleasedReservedStock(
        currentReserved: currentReserved,
        releaseQty: entry.value,
      );
      batch.set(_col('products').doc(entry.key), {
        'reserved_stock': nextReserved,
      }, SetOptions(merge: true));
    }

    Map<String, dynamic> transUpdate = {
      'items': updatedItems,
      'delivery_status': newDeliveryStatus,
      'delivery_logs': existingLogs,
    };

    batch.update(transRef, transUpdate);
    await batch.commit();

    return {
      ...existingTrans,
      ...transUpdate,
    };
  }

  /// INPUT TITIPAN LAMA / EXISTING WAREHOUSE RESERVATION (TANPA TRANSAKSI ULANG)
  /// Tidak menambah Omset, Profit, Modal Cair, atau Cashflow.
  Future<Map<String, dynamic>> createLegacyTitipan({
    required String customerName,
    String customerPhone = '',
    String customerAddress = '',
    required String cashierName,
    required String transactionDate,
    required List<Map<String, dynamic>> items,
    required bool deductFromStock,
    String note = '',
  }) async {
    String cleanCust = customerName.trim().isEmpty
        ? 'Pelanggan Umum'
        : customerName.trim();
    int transId = DateTime.now().millisecondsSinceEpoch;

    String datePrefix = transactionDate.length >= 10
        ? transactionDate.substring(0, 10)
        : DateTime.now().toIso8601String().substring(0, 10);
    int queueNum = 1;
    try {
      final daySnap = await _col('transactions')
          .where('transaction_date', isGreaterThanOrEqualTo: '${datePrefix}T00:00:00.000')
          .where('transaction_date', isLessThanOrEqualTo: '${datePrefix}T23:59:59.999')
          .get(const GetOptions(source: Source.cache));
      queueNum = daySnap.docs.length + 1;
    } catch (_) {
      queueNum = 1;
    }

    WriteBatch batch = _db.batch();

    if (cleanCust != 'Pelanggan Umum') {
      batch.set(_col('customers').doc(cleanCust), {
        'name': cleanCust,
        if (customerPhone.trim().isNotEmpty) 'phone': customerPhone.trim(),
        if (customerAddress.trim().isNotEmpty) 'address': customerAddress.trim(),
      }, SetOptions(merge: true));
    }

    Map<String, double> reserveByProduct = {};
    List<Map<String, dynamic>> embeddedItems = [];

    for (var raw in items) {
      double baseQty = (raw['quantity'] as num?)?.toDouble() ?? 1.0;
      double reqQty = (raw['request_qty'] as num?)?.toDouble() ?? baseQty;
      if (raw['product_id'] != null) {
        String pid = raw['product_id'].toString();
        reserveByProduct[pid] = (reserveByProduct[pid] ?? 0.0) + baseQty;
      }

      embeddedItems.add({
        'product_id': raw['product_id'],
        'product_name': raw['product_name'] ?? 'Barang Titipan',
        'product_type': raw['product_type'] ?? 'BANGUNAN',
        'dimensions': raw['dimensions'] ?? '',
        'quantity': baseQty,
        'request_qty': reqQty,
        'delivered_qty': 0.0,
        'delivered_request_qty': 0.0,
        'unit_type': raw['unit_type'] ?? 'Pcs',
        'capital_price': 0,
        'sell_price': 0,
        'agreed_total': 0,
        'capital_total': 0,
      });
    }

    for (var entry in reserveByProduct.entries) {
      Map<String, dynamic> prodUpdate = {
        'reserved_stock': FieldValue.increment(entry.value),
      };
      if (deductFromStock) {
        prodUpdate['stock'] = FieldValue.increment(-entry.value);
      }
      batch.set(_col('products').doc(entry.key), prodUpdate, SetOptions(merge: true));
    }

    String modeLabel = deductFromStock
        ? 'Potong Stok Siap Jual -> Pindah ke Titipan'
        : 'Tambah Angka Titipan Saja (Stok Siap Jual Tetap)';
    String logNote = note.trim().isNotEmpty
        ? 'Input Titipan Lama ($modeLabel): ${note.trim()}'
        : 'Input Titipan Lama ($modeLabel)';

    Map<String, dynamic> transactionData = {
      'id': transId,
      'total_price': 0,
      'operational_cost': 0,
      'discount': 0,
      'cut_profit': 0,
      'customer_name': cleanCust,
      'customer_phone': customerPhone.trim(),
      'customer_address': customerAddress.trim(),
      'payment_method': 'Titipan Lama',
      'payment_status': 'Lunas',
      'queue_number': queueNum,
      'delivery_status': 'Belum Diantar',
      'is_legacy_titipan': true,
      'deducted_from_stock': deductFromStock,
      'legacy_note': note.trim(),
      'transaction_date': transactionDate,
      'cashier_name': cashierName,
      'items': embeddedItems,
      'delivery_logs': [
        {
          'date': DateTime.now().toIso8601String(),
          'cashier_name': cashierName,
          'note': logNote,
          'items': [],
        }
      ],
    };

    batch.set(_col('transactions').doc(transId.toString()), transactionData);
    await batch.commit();
    return transactionData;
  }

  /// UBAH NOTA TRANSAKSI LAMA YANG SUDAH SELESAI MENJADI BARANG TITIPAN
  /// Hanya menambah reserved_stock tanpa memotong stok siap jual lagi.
  Future<Map<String, dynamic>> convertTransactionToTitipan({
    required int transId,
    required List<Map<String, dynamic>> updatedItems,
    String note = '',
  }) async {
    DocumentReference transRef = _col('transactions').doc(transId.toString());
    Map<String, dynamic> existingTrans = {};
    try {
      final snap = await transRef
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 4));
      if (snap.exists && snap.data() != null) {
        existingTrans = Map<String, dynamic>.from(snap.data() as Map);
      }
    } catch (_) {
      final snap = await transRef.get(const GetOptions(source: Source.cache));
      if (snap.exists && snap.data() != null) {
        existingTrans = Map<String, dynamic>.from(snap.data() as Map);
      }
    }

    List<dynamic> oldItemsRaw = existingTrans['items'] is List
        ? List<dynamic>.from(existingTrans['items'])
        : [];

    bool allDelivered = true;
    bool noneDelivered = true;
    Map<String, double> reserveByProduct = {};

    for (int i = 0; i < updatedItems.length; i++) {
      var newItem = updatedItems[i];
      double qty = (newItem['quantity'] as num?)?.toDouble() ?? 0.0;
      double newDelQty = (newItem['delivered_qty'] as num?)?.toDouble() ?? 0.0;

      if (newDelQty < qty - 0.01) allDelivered = false;
      if (newDelQty > 0.01) noneDelivered = false;

      double oldDelQty = qty;
      if (i < oldItemsRaw.length && oldItemsRaw[i] is Map) {
        var oldIt = Map<String, dynamic>.from(oldItemsRaw[i] as Map);
        oldDelQty = oldIt.containsKey('delivered_qty') && oldIt['delivered_qty'] != null
            ? (oldIt['delivered_qty'] as num).toDouble()
            : qty;
      }

      double newlyReserved = double.parse((oldDelQty - newDelQty).clamp(0.0, qty).toStringAsFixed(2));
      if (newlyReserved > 0.0001 && newItem['product_id'] != null) {
        String pid = newItem['product_id'].toString();
        reserveByProduct[pid] = (reserveByProduct[pid] ?? 0.0) + newlyReserved;
      }
    }

    String newDeliveryStatus = allDelivered
        ? 'Selesai'
        : (noneDelivered ? 'Belum Diantar' : 'Sebagian');

    List<Map<String, dynamic>> existingLogs = [];
    if (existingTrans['delivery_logs'] != null && existingTrans['delivery_logs'] is List) {
      existingLogs = List<Map<String, dynamic>>.from(
        (existingTrans['delivery_logs'] as List).map((e) => Map<String, dynamic>.from(e as Map)),
      );
    }

    existingLogs.add({
      'date': DateTime.now().toIso8601String(),
      'cashier_name': SessionManager().userName ?? 'Admin',
      'note': note.trim().isNotEmpty
          ? 'Nota diubah jadi Titipan Gudang: ${note.trim()}'
          : 'Nota diubah jadi Barang Titipan (Belum Diantar)',
      'items': [],
    });

    WriteBatch batch = _db.batch();
    for (var entry in reserveByProduct.entries) {
      batch.set(_col('products').doc(entry.key), {
        'reserved_stock': FieldValue.increment(entry.value),
      }, SetOptions(merge: true));
    }

    Map<String, dynamic> transUpdate = {
      'items': updatedItems,
      'delivery_status': newDeliveryStatus,
      'delivery_logs': existingLogs,
    };

    batch.update(transRef, transUpdate);
    await batch.commit();

    return {
      ...existingTrans,
      ...transUpdate,
    };
  }
}