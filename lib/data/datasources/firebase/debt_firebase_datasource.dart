import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../helpers/session_manager.dart';

class DebtFirebaseDataSource {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  CollectionReference _col(String path) => _db
      .collection('stores')
      .doc(SessionManager().uid ?? 'UNKNOWN_STORE')
      .collection(path);

  Future<List<QueryDocumentSnapshot>> _safeQuery(Query q) async {
    try {
      final snap = await q.get(const GetOptions(source: Source.cache));
      q.get(const GetOptions(source: Source.server)).then((_) => null, onError: (_) => null);
      if (snap.docs.isNotEmpty) return snap.docs;
      final sSnap = await q
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 3));
      return sSnap.docs;
    } catch (_) {
      try {
        final bSnap = await q.get(const GetOptions(source: Source.cache));
        return bSnap.docs;
      } catch (_) {
        return [];
      }
    }
  }

  Future<List<Map<String, dynamic>>> getActiveDebtsWithDetails() async {
    final tDocs = await _safeQuery(
      _col('transactions').where('payment_status', isNotEqualTo: 'Lunas'),
    );
    List<Map<String, dynamic>> activeDebts = [];
    for (var doc in tDocs) {
      Map<String, dynamic> transData = doc.data() as Map<String, dynamic>;
      int transId = transData['id'] as int;
      final pDocs = await _safeQuery(
        _col('debt_payments').where('transaction_id', isEqualTo: transId),
      );
      int totalDicicil = 0;
      for (var payDoc in pDocs) {
        var pData = payDoc.data() as Map<String, dynamic>;
        totalDicicil += (pData['amount_paid'] as num).toInt();
      }
      transData['total_dicicil'] = totalDicicil;
      activeDebts.add(transData);
    }
    activeDebts.sort(
      (a, b) => (b['transaction_date'] as String).compareTo(
        a['transaction_date'] as String,
      ),
    );
    return activeDebts;
  }
}
