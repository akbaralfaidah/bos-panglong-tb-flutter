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
      int disc = (transData['discount'] as num?)?.toInt() ?? 0;
      
      final pDocs = await _safeQuery(_col('debt_payments').where('transaction_id', isEqualTo: transId));
      int dicicil = amount; 
      for (var p in pDocs) {
         var pd = p.data() as Map<String, dynamic>;
         dicicil += (pd['amount_paid'] as num?)?.toInt() ?? 0;
      }
      if (dicicil >= (tp - disc)) isLunas = true;
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
        for (var item in items) {
          double cap = (item['capital_price'] as num?)?.toDouble() ?? 0;
          double qty = (item['quantity'] as num?)?.toDouble() ?? 0;
          if (item['product_id'] != null) {
            batch.set(_col('products').doc(item['product_id'].toString()), {
              'modal_cair': FieldValue.increment(cap * qty) 
            }, SetOptions(merge: true));
          }
        }
      }
    }
    batch.commit(); 
  }

  // 🔥 DOBRAK FIREBASE: BATALIN TRANSAKSI = MODAL KETARIK / NGURANG (-) 🔥
  Future<void> voidTransaction(int transId, List<Map<String, dynamic>> items) async {
    WriteBatch batch = _db.batch();

    bool wasLunas = false;
    final tDocs = await _safeQuery(_col('transactions').where('id', isEqualTo: transId));
    if (tDocs.isNotEmpty) {
       var tData = tDocs.first.data() as Map<String, dynamic>;
       wasLunas = (tData['payment_status'] ?? '').toString().toLowerCase() == 'lunas';
    }

    for (var item in items) {
      if (item['product_id'] != null && item['quantity'] != null) {
        double qtyToRestore = (item['quantity'] as num).toDouble();
        double cap = (item['capital_price'] as num?)?.toDouble() ?? 0;

        DocumentReference prodRef = _col('products').doc(item['product_id'].toString());
        
        if (wasLunas) {
          // KARENA BATAL JUAL, DUIT MODAL DITARIK LAGI BIAR GAK MINUS! (-)
          batch.set(prodRef, {
            'stock': FieldValue.increment(qtyToRestore),
            'modal_cair': FieldValue.increment(-(cap * qtyToRestore)) 
          }, SetOptions(merge: true));
        } else {
          batch.set(prodRef, {
            'stock': FieldValue.increment(qtyToRestore)
          }, SetOptions(merge: true));
        }
      }
    }

    final pDocs = await _safeQuery(_col('debt_payments').where('transaction_id', isEqualTo: transId));
    for (var p in pDocs) { batch.delete(p.reference); }

    batch.delete(_col('transactions').doc(transId.toString()));
    await batch.commit();
  }
}