import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../helpers/session_manager.dart';

class CoreFirebaseDataSource {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  CollectionReference _col(String path) => _db.collection('stores').doc(SessionManager().uid ?? 'UNKNOWN_STORE').collection(path);

  // 🔥 ZERO-SECOND CACHE
  Future<List<QueryDocumentSnapshot>> _safeQuery(Query q) async {
    q.get(const GetOptions(source: Source.server)).then((_) => null, onError: (_) => null);
    try {
      final snap = await q.get(const GetOptions(source: Source.cache));
      return snap.docs;
    } catch (_) { return []; }
  }

  Future<DocumentSnapshot?> _safeDoc(DocumentReference d) async {
    d.get(const GetOptions(source: Source.server)).then((_) => null, onError: (_) => null);
    try {
      final snap = await d.get(const GetOptions(source: Source.cache));
      if (snap.exists) return snap;
      return null;
    } catch (_) { return null; }
  }

  Future<void> saveCustomer(String name) async {
    await _col('customers').doc(name).set({'name': name}, SetOptions(merge: true));
  }

  Future<List<String>> getCustomers() async {
    final docs = await _safeQuery(_col('customers').orderBy('name'));
    return docs.map((doc) => (doc.data() as Map<String, dynamic>)['name'] as String).toList(); 
  }

  Future<void> saveSetting(String k, String v) async {
    // 🔥 SUDAH DITAMBAHKAN AWAIT AGAR PIN BENAR-BENAR TERSIMPAN DI CLOUD
    await _col('settings').doc('store_info').set({k: v}, SetOptions(merge: true));
  }

  Future<String?> getSetting(String k) async {
    final doc = await _safeDoc(_col('settings').doc('store_info'));
    if (doc != null && doc.exists) {
      final data = doc.data() as Map<String, dynamic>?; 
      if (data != null && data.containsKey(k)) return data[k] as String;
    }
    return null;
  }

  Future<List<Map<String, dynamic>>> getTransactionsByCustomer(String name) async {
    final docs = await _safeQuery(
      _col('transactions').where('customer_name', isGreaterThanOrEqualTo: name).where('customer_name', isLessThan: name + 'z').orderBy('customer_name') 
    );
    List<Map<String, dynamic>> results = docs.map((doc) => doc.data() as Map<String, dynamic>).toList(); 
    results.sort((a, b) => (b['transaction_date'] as String).compareTo(a['transaction_date'] as String));
    return results;
  }

  // 🔥 FITUR SAPU JAGAT (FACTORY RESET) 🔥
  Future<void> factoryReset() async {
    List<String> collectionsToClear = [
      'products', 
      'transactions', 
      'stock_logs', 
      'customers', 
      'bensin'
    ];
    
    for (String colName in collectionsToClear) {
      var snapshot = await _col(colName).get(const GetOptions(source: Source.server));
      
      if (snapshot.docs.isNotEmpty) {
        int count = 0;
        WriteBatch batch = _db.batch();
        
        for (var doc in snapshot.docs) {
          batch.delete(doc.reference);
          count++;
          if (count % 400 == 0) {
            await batch.commit();
            batch = _db.batch(); 
          }
        }
        await batch.commit(); 
      }
    }
  }
}