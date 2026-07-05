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
    // 🔥 OPTIMASI: Ambil transaksi dan pembayaran secara PARALEL (2 query saja, bukan N+1)
    final results = await Future.wait([
      _safeQuery(_col('transactions').where('payment_status', isNotEqualTo: 'Lunas')),
      _safeQuery(_col('debt_payments')),
    ]);

    final tDocs = results[0];
    final allPaymentDocs = results[1];

    // Buat map: transaction_id -> total_dicicil (hitung sekali di memori)
    Map<int, int> paymentMap = {};
    for (var payDoc in allPaymentDocs) {
      var pData = payDoc.data() as Map<String, dynamic>;
      int transId = (pData['transaction_id'] as num).toInt();
      int amount = (pData['amount_paid'] as num).toInt();
      paymentMap[transId] = (paymentMap[transId] ?? 0) + amount;
    }

    List<Map<String, dynamic>> activeDebts = [];
    for (var doc in tDocs) {
      Map<String, dynamic> transData = doc.data() as Map<String, dynamic>;
      int transId = transData['id'] as int;
      transData['total_dicicil'] = paymentMap[transId] ?? 0;
      
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
      double cutProfit = (transData['cut_profit'] as num?)?.toDouble() ?? 0;
      transData['potential_profit'] = (trxProfit + op - disc - cutProfit).round();

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

  // 🔥 LUNASI SEMUA HUTANG SEKALIGUS (BATCH ATOMIC) 🔥
  Future<void> payAllDebts(List<Map<String, dynamic>> allDebts, DateTime paymentDate) async {
    WriteBatch batch = _db.batch();
    String currentCashier = SessionManager().userName ?? 'Tidak Diketahui';
    String payDateStr = paymentDate.toIso8601String();

    for (var debt in allDebts) {
      int transId = debt['id'] as int;
      int totalPrice = (debt['total_price'] as num?)?.toInt() ?? 0;
      int totalDicicil = (debt['total_dicicil'] as num?)?.toInt() ?? 0;
      int sisaHutang = totalPrice - totalDicicil;

      if (sisaHutang <= 0) continue; // Sudah lunas, skip

      // 1. Buat payment record untuk sisa hutang
      int paymentId = DateTime.now().millisecondsSinceEpoch + transId; // Unique per transaksi
      batch.set(_col('debt_payments').doc(paymentId.toString()), {
        'id': paymentId,
        'transaction_id': transId,
        'amount_paid': sisaHutang,
        'note': 'Lunasi Semua Hutang (Batch)',
        'payment_date': payDateStr,
        'cashier_name': currentCashier,
      });

      // 2. Update status transaksi jadi Lunas
      batch.update(_col('transactions').doc(transId.toString()), {
        'payment_status': 'Lunas',
      });

      // 3. Update modal_cair di produk (sama seperti flow payDebt)
      List<dynamic> items = debt['items'] ?? [];
      for (var item in items) {
        double cap = (item['capital_price'] as num?)?.toDouble() ?? 0;
        double qty = (item['quantity'] as num?)?.toDouble() ?? 0;
        if (item['product_id'] != null) {
          batch.set(_col('products').doc(item['product_id'].toString()), {
            'modal_cair': FieldValue.increment(cap * qty),
          }, SetOptions(merge: true));
        }
      }
    }

    await batch.commit();
  }

  // =====================================================
  // 🏘️ DEBT GROUPS — CRUD Firestore `debt_groups`
  // =====================================================

  /// Buat grup hutang baru
  Future<String> createDebtGroup(String groupName, List<String> customerNames) async {
    final docRef = _col('debt_groups').doc();
    await docRef.set({
      'id': docRef.id,
      'group_name': groupName.trim(),
      'customer_names': customerNames,
      'created_at': DateTime.now().toIso8601String(),
    });
    return docRef.id;
  }

  /// Update nama & anggota grup
  Future<void> updateDebtGroup(String groupId, String groupName, List<String> customerNames) async {
    await _col('debt_groups').doc(groupId).update({
      'group_name': groupName.trim(),
      'customer_names': customerNames,
    });
  }

  /// Hapus grup
  Future<void> deleteDebtGroup(String groupId) async {
    await _col('debt_groups').doc(groupId).delete();
  }

  /// Ambil semua grup dari Firestore
  Future<List<Map<String, dynamic>>> getAllDebtGroups() async {
    final docs = await _safeQuery(_col('debt_groups').orderBy('created_at'));
    return docs.map((d) {
      final data = d.data() as Map<String, dynamic>;
      // Pastikan id selalu ada
      data['id'] = d.id;
      return data;
    }).toList();
  }

  /// Ambil semua customer_name yang sudah masuk ke grup manapun
  Future<Set<String>> getGroupedCustomerNames() async {
    final groups = await getAllDebtGroups();
    Set<String> names = {};
    for (var g in groups) {
      List<dynamic> members = g['customer_names'] ?? [];
      for (var m in members) {
        names.add(m.toString());
      }
    }
    return names;
  }

  /// Lunasi semua hutang untuk customer-customer tertentu (untuk fitur lunasi per grup)
  Future<void> payAllDebtsForCustomers(List<String> customerNames, DateTime paymentDate) async {
    final allDebts = await getActiveDebtsWithDetails();
    Set<String> nameSet = customerNames.toSet();

    // Filter hanya transaksi milik customer dalam list
    List<Map<String, dynamic>> filteredDebts = allDebts.where((debt) {
      String rawName = debt['customer_name'] ?? 'Pelanggan Umum';
      String customerKey = rawName.split(' - ').first.split('\n').first.trim();
      if (customerKey.isEmpty) customerKey = 'Pelanggan Umum';
      return nameSet.contains(customerKey);
    }).toList();

    if (filteredDebts.isEmpty) return;

    // Gunakan logic yang sama seperti payAllDebts
    await payAllDebts(filteredDebts, paymentDate);
  }
}
