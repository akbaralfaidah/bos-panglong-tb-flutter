import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../helpers/session_manager.dart';

class CashFlowFirebaseDataSource {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  CollectionReference _col(String path) => _db.collection('stores').doc(SessionManager().uid ?? 'UNKNOWN_STORE').collection(path);

  Future<List<QueryDocumentSnapshot>> _safeQuery(Query q) async {
    try {
      final snap = await q.get(const GetOptions(source: Source.cache));
      q.get(const GetOptions(source: Source.server)).then((_) => null, onError: (_) => null);
      if (snap.docs.isNotEmpty) return snap.docs;
      final sSnap = await q.get(const GetOptions(source: Source.server)).timeout(const Duration(seconds: 3));
      return sSnap.docs;
    } catch (_) {
      try {
        final bSnap = await q.get(const GetOptions(source: Source.cache));
        return bSnap.docs;
      } catch (_) { return []; }
    }
  }

  Future<DocumentSnapshot?> _safeDoc(DocumentReference d) async {
    try {
      final snap = await d.get(const GetOptions(source: Source.cache));
      d.get(const GetOptions(source: Source.server)).catchError((_) {});
      if (snap.exists) return snap;
      final sSnap = await d.get(const GetOptions(source: Source.server)).timeout(const Duration(seconds: 3));
      return sSnap.exists ? sSnap : null;
    } catch (_) {
      return null;
    }
  }

  Future<List<Map<String, dynamic>>> getAllTransactions() async {
    final docs = await _safeQuery(_col('transactions'));
    return docs.map((doc) => doc.data() as Map<String, dynamic>).toList(); 
  }

  Future<List<Map<String, dynamic>>> getAllDebtPayments() async {
    final docs = await _safeQuery(_col('debt_payments'));
    return docs.map((doc) => doc.data() as Map<String, dynamic>).toList(); 
  }

  Future<List<Map<String, dynamic>>> getAllStockLogsWithProducts() async {
    final sDocs = await _safeQuery(_col('stock_logs'));
    final pDocs = await _safeQuery(_col('products'));
    
    Map<int, Map<String, dynamic>> productMap = {};
    for (var p in pDocs) {
      var pData = p.data() as Map<String, dynamic>;
      productMap[pData['id'] as int] = pData;
    }
    
    List<Map<String, dynamic>> joined = [];
    for (var s in sDocs) {
      var log = s.data() as Map<String, dynamic>; 
      var prod = productMap[log['product_id'] as int];
      
      // 🔥 FIX SELISIH STOK MASUK: Samakan rumus murni dengan Dashboard!
      double qty = (log['quantity'] as num?)?.toDouble() ?? 0;
      double price = (log['price'] as num?)?.toDouble() ?? 0;
      
      double itemTotal = log.containsKey('total_price') && log['total_price'] != null 
          ? (log['total_price'] as num).toDouble() 
          : (qty * price).roundToDouble();
          
      log['total_price'] = itemTotal; // Timpa datanya biar UI nampilin angka bulat murni!
      
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

  Future<List<Map<String, dynamic>>> getAllGasExpenses() async {
    final docs = await _safeQuery(_col('gas_expenses'));
    return docs.map((doc) => doc.data() as Map<String, dynamic>).toList(); 
  }

  // 🔥 INI DIA FUNGSI YANG DICARI-CARI SAMA CONTROLLER LU!
  Future<Map<String, dynamic>?> getTransactionById(int id) async {
    final doc = await _safeDoc(_col('transactions').doc(id.toString()));
    if (doc != null && doc.exists) {
      return doc.data() as Map<String, dynamic>;
    }
    return null;
  }
}