import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../helpers/session_manager.dart';

class OperationalFirebaseDataSource {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  CollectionReference _col(String path) => _db
      .collection('stores')
      .doc(SessionManager().uid ?? 'UNKNOWN_STORE')
      .collection(path);

  Future<List<QueryDocumentSnapshot>> _safeQuery(
    Query q, {
    bool preferServer = true,
  }) async {
    if (preferServer) {
      try {
        final sSnap = await q
            .get(const GetOptions(source: Source.server))
            .timeout(const Duration(seconds: 5));
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
    try {
      final snap = await q.get(const GetOptions(source: Source.cache));
      if (snap.docs.isNotEmpty) {
        q
            .get(const GetOptions(source: Source.server))
            .then((_) => null, onError: (_) => null);
        return snap.docs;
      }
      final sSnap = await q
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 5));
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

  Future<void> addOperationalExpense(int amount, String desc, {DateTime? customDate}) async {
    int id = DateTime.now().millisecondsSinceEpoch;
    String dateNow = customDate?.toIso8601String() ?? DateTime.now().toIso8601String();
    
    // Tetap simpan di 'gas_expenses' agar data histori lama lu tidak hangus
    await _col('gas_expenses').doc(id.toString()).set({
      'id': id,
      'amount': amount,
      'description': desc,
      'date': dateNow,
      'cashier_name': SessionManager().userName ?? 'Tidak Diketahui',
    });
  }

  Future<List<Map<String, dynamic>>> getOperationalExpenses(
    String startDate,
    String endDate,
  ) async {
    String start = "${startDate}T00:00:00.000";
    String end = "${endDate}T23:59:59.999";
    final docs = await _safeQuery(
      _col('gas_expenses')
          .where('date', isGreaterThanOrEqualTo: start)
          .where('date', isLessThanOrEqualTo: end),
      preferServer: startDate != '2000-01-01',
    );
    List<Map<String, dynamic>> results = docs
        .map((doc) => Map<String, dynamic>.from(doc.data() as Map))
        .toList();
    results.sort(
      (a, b) => (b['date'] ?? '').toString().compareTo((a['date'] ?? '').toString()),
    );
    return results;
  }

  Future<List<Map<String, dynamic>>> getOperationalIncomes(
    String startDate,
    String endDate,
  ) async {
    String start = "${startDate}T00:00:00.000";
    String end = "${endDate}T23:59:59.999";
    final docs = await _safeQuery(
      _col('transactions')
          .where('transaction_date', isGreaterThanOrEqualTo: start)
          .where('transaction_date', isLessThanOrEqualTo: end),
      preferServer: startDate != '2000-01-01',
    );
    List<Map<String, dynamic>> results = docs
        .map((doc) => Map<String, dynamic>.from(doc.data() as Map))
        .toList();

    List<Map<String, dynamic>> incomes = [];
    for (var row in results) {
      if (row['is_legacy_titipan'] == true) continue;
      int opCost = (row['operational_cost'] as num?)?.toInt() ?? 0;
      if (opCost > 0) {
        incomes.add({
          'id': row['id'],
          'title': row['customer_name'] ?? 'Pelanggan Umum',
          'amount': opCost,
          'date': row['transaction_date'],
          'cashier_name': row['cashier_name'] ?? 'Tidak Diketahui',
        });
      }
    }
    incomes.sort(
      (a, b) => (b['date'] ?? '').toString().compareTo((a['date'] ?? '').toString()),
    );
    return incomes;
  }

  Future<void> deleteOperationalExpense(int id) async {
    await _col('gas_expenses').doc(id.toString()).delete();
  }
}