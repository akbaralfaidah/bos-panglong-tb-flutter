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
      
      // Hitung potensi profit untuk nota ini
      double op = (transData['operational_cost'] as num?)?.toDouble() ?? 0;
      double disc = (transData['discount'] as num?)?.toDouble() ?? 0;
      List<dynamic> items = transData['items'] ?? [];
      double trxProfit = 0;
      for (var item in items) {
        double agreed = 0;
        double capital = 0;
        if (item is Map && item.containsKey('agreed_total') && item['agreed_total'] != null) {
          agreed = (item['agreed_total'] as num).toDouble();
          capital = (item['capital_total'] as num).toDouble();
        } else if (item is Map) {
          double sell = (item['sell_price'] as num?)?.toDouble() ?? 0;
          double cap = (item['capital_price'] as num?)?.toDouble() ?? 0;
          double qty = (item['quantity'] as num?)?.toDouble() ?? 0;
          agreed = sell * qty;
          capital = cap * qty;
        }
        trxProfit += (agreed - capital);
      }
      transData['potential_profit'] = (trxProfit + op - disc).round();

      activeDebts.add(transData);
    }
    activeDebts.sort(
      (a, b) => (b['transaction_date'] as String).compareTo(
        a['transaction_date'] as String,
      ),
    );
    return activeDebts;
  }

  // GRUPKAN HUTANG BERDASARKAN NAMA PELANGGAN
  Future<List<Map<String, dynamic>>> getActiveDebtsGroupedByCustomer() async {
    // 1. Ambil semua hutang aktif (pakai method yang sudah ada)
    final allDebts = await getActiveDebtsWithDetails();

    // 2. Kelompokkan berdasarkan nama pelanggan (sebelum ' - ')
    Map<String, Map<String, dynamic>> grouped = {};

    for (var debt in allDebts) {
      String rawName = debt['customer_name'] ?? 'Pelanggan Umum';
      // Ambil nama saja (sebelum ' - ' jika ada nomor HP/alamat)
      String customerKey = rawName.split(' - ').first.split('\n').first.trim();
      if (customerKey.isEmpty) customerKey = 'Pelanggan Umum';

      if (!grouped.containsKey(customerKey)) {
        grouped[customerKey] = {
          'customer_name': customerKey,
          'full_customer_name': rawName, // simpan nama lengkap dari transaksi pertama
          'total_hutang': 0,
          'total_dicicil': 0,
          'sisa_hutang': 0,
          'potential_profit': 0, // Tambah ini
          'transactions': <Map<String, dynamic>>[],
          'transaction_count': 0,
          'latest_transaction_date': debt['transaction_date'],
        };
      }

      int totalPrice = (debt['total_price'] as num?)?.toInt() ?? 0;
      int dicicil = (debt['total_dicicil'] as num?)?.toInt() ?? 0;
      int profit = (debt['potential_profit'] as num?)?.toInt() ?? 0;

      grouped[customerKey]!['total_hutang'] += totalPrice;
      grouped[customerKey]!['total_dicicil'] += dicicil;
      grouped[customerKey]!['sisa_hutang'] += (totalPrice - dicicil);
      grouped[customerKey]!['potential_profit'] += profit; // Tambah ini
      (grouped[customerKey]!['transactions'] as List<Map<String, dynamic>>).add(debt);
      grouped[customerKey]!['transaction_count'] += 1;
    }

    // 3. Convert ke list dan sort berdasarkan tanggal transaksi terbaru
    List<Map<String, dynamic>> result = grouped.values.toList();
    result.sort((a, b) => (b['latest_transaction_date'] as String).compareTo(a['latest_transaction_date'] as String));

    return result;
  }
}
