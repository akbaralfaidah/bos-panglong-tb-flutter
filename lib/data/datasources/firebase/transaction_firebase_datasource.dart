import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../helpers/session_manager.dart';

class TransactionFirebaseDataSource {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  CollectionReference _col(String path) => _db.collection('stores').doc(SessionManager().uid ?? 'UNKNOWN_STORE').collection(path);

  Future<List<QueryDocumentSnapshot>> _safeQuery(Query q) async {
    q.get(const GetOptions(source: Source.server)).then((_) => null, onError: (_) => null);
    try {
      final snap = await q.get(const GetOptions(source: Source.cache));
      return snap.docs;
    } catch (_) { return []; }
  }

  Future<Map<String, dynamic>?> getTransactionById(int id) async {
    final docs = await _safeQuery(_col('transactions').where('id', isEqualTo: id));
    if (docs.isNotEmpty) return docs.first.data() as Map<String, dynamic>; 
    return null;
  }

  Future<List<Map<String, dynamic>>> getDebtPayments(int transId) async {
    final docs = await _safeQuery(_col('debt_payments').where('transaction_id', isEqualTo: transId));
    List<Map<String, dynamic>> results = docs.map((doc) => doc.data() as Map<String, dynamic>).toList(); 
    results.sort((a, b) => (a['payment_date'] ?? '').compareTo(b['payment_date'] ?? ''));
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
    List<Map<String, dynamic>> dbItems = items;
    final tDocs = await _safeQuery(_col('transactions').where('id', isEqualTo: transId));
    if (tDocs.isNotEmpty) {
       var tData = tDocs.first.data() as Map<String, dynamic>;
       wasLunas = (tData['payment_status'] ?? '').toString().toLowerCase() == 'lunas';
       if (tData['items'] != null && (tData['items'] as List).isNotEmpty) {
         dbItems = List<Map<String, dynamic>>.from(
           (tData['items'] as List).map((e) => Map<String, dynamic>.from(e as Map)),
         );
       }
    }

    for (var item in dbItems) {
      if (item['product_id'] != null && item['quantity'] != null) {
        double qtyToRestore = (item['quantity'] as num).toDouble();
        double capTotal = _getItemCapitalTotal(item);
        double undeliveredToRelease = _getUndeliveredQty(item);

        DocumentReference prodRef = _col('products').doc(item['product_id'].toString());
        
        Map<String, dynamic> updateMap = {
          'stock': FieldValue.increment(qtyToRestore),
        };
        if (wasLunas && capTotal > 0) {
          // KARENA BATAL JUAL, DUIT MODAL DITARIK LAGI BIAR GAK MINUS! (-)
          updateMap['modal_cair'] = FieldValue.increment(-capTotal);
        }
        if (undeliveredToRelease > 0) {
          updateMap['reserved_stock'] = FieldValue.increment(-undeliveredToRelease);
        }
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

    // 1. REVERSE OLD ITEMS (Kembalikan stok, lepas titipan lama, & tarik modal)
    for (var item in oldItems) {
      if (item['product_id'] != null && item['quantity'] != null) {
        double qtyToRestore = (item['quantity'] as num).toDouble();
        double capTotal = _getItemCapitalTotal(item);
        double oldUndelivered = _getUndeliveredQty(item);
        DocumentReference prodRef = _col('products').doc(item['product_id'].toString());
        
        Map<String, dynamic> reverseMap = {
          'stock': FieldValue.increment(qtyToRestore),
        };
        if (wasLunas && capTotal > 0) {
          reverseMap['modal_cair'] = FieldValue.increment(-capTotal);
        }
        if (oldUndelivered > 0) {
          reverseMap['reserved_stock'] = FieldValue.increment(-oldUndelivered);
        }
        batch.set(prodRef, reverseMap, SetOptions(merge: true));
      }
    }

    // 2. APPLY NEW ITEMS (Potong stok, tambah titipan baru, & tambah modal)
    for (var item in newItems) {
      if (item['product_id'] != null && item['quantity'] != null) {
        double qtyToDeduct = (item['quantity'] as num).toDouble();
        double capTotal = _getItemCapitalTotal(item);
        double newUndelivered = _getUndeliveredQty(item);
        DocumentReference prodRef = _col('products').doc(item['product_id'].toString());
        
        Map<String, dynamic> applyMap = {
          'stock': FieldValue.increment(-qtyToDeduct),
        };
        if (isNowLunas && capTotal > 0) {
          applyMap['modal_cair'] = FieldValue.increment(capTotal);
        }
        if (newUndelivered > 0) {
          applyMap['reserved_stock'] = FieldValue.increment(newUndelivered);
        }
        batch.set(prodRef, applyMap, SetOptions(merge: true));
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
      batch.set(_col('products').doc(entry.key), {
        'reserved_stock': FieldValue.increment(-entry.value),
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