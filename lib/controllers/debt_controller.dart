import '../data/datasources/firebase/debt_firebase_datasource.dart'; // KABEL FIREBASE

class DebtController {
  final DebtFirebaseDataSource _debtDS = DebtFirebaseDataSource();

  // Memisahkan logika perhitungan dari UI (LOGIKA ASLI LU KEMBALI!)
  Future<Map<String, dynamic>> getDebtSummary() async {
    final result = await _debtDS.getActiveDebtsWithDetails();

    int totalSisaPiutang = 0;
    int totalPotentialProfit = 0;
    List<Map<String, dynamic>> processedDebts = [];

    for (var row in result) {
      int totalPrice = (row['total_price'] as num?)?.toInt() ?? 0;
      int discount = (row['discount'] as num?)?.toInt() ?? 0;
      int dicicil = (row['total_dicicil'] as num?)?.toInt() ?? 0;
      int profit = (row['potential_profit'] as num?)?.toInt() ?? 0;

      // Logika lu aman di sini bro!
      int sisa = totalPrice - dicicil;
      totalSisaPiutang += sisa;
      totalPotentialProfit += profit;

      // Kita bikin map baru yang udah include sisa hutang biar UI tinggal pakai
      Map<String, dynamic> debtItem = Map<String, dynamic>.from(row);
      debtItem['sisa_hutang'] = sisa;
      processedDebts.add(debtItem);
    }

    return {
      'debts': processedDebts,
      'total_sisa': totalSisaPiutang,
      'total_potential_profit': totalPotentialProfit,
    };
  }

  // METODE BARU: Ambil data hutang yang sudah digrupkan per nama pelanggan
  Future<Map<String, dynamic>> getGroupedDebtSummary() async {
    final groupedDebts = await _debtDS.getActiveDebtsGroupedByCustomer();

    int totalSisaPiutang = 0;
    int totalPotentialProfit = 0;
    for (var group in groupedDebts) {
      totalSisaPiutang += (group['sisa_hutang'] as int);
      totalPotentialProfit += (group['potential_profit'] as int);
    }

    return {
      'groups': groupedDebts,
      'total_sisa': totalSisaPiutang,
      'total_potential_profit': totalPotentialProfit,
    };
  }

  // 🔥 AMBIL SEMUA HUTANG AKTIF (FLAT, BUKAN GROUPED) 🔥
  Future<List<Map<String, dynamic>>> getAllActiveDebts() async {
    final result = await _debtDS.getActiveDebtsWithDetails();
    return result;
  }

  // 🔥 LUNASI SEMUA HUTANG SEKALIGUS 🔥
  Future<void> payAllDebts(List<Map<String, dynamic>> allDebts, DateTime paymentDate) async {
    await _debtDS.payAllDebts(allDebts, paymentDate);
  }

  // =====================================================
  // 🏘️ DEBT GROUPS — Business Logic
  // =====================================================

  /// Buat grup baru
  Future<String> createDebtGroup(String name, List<String> customerNames) async {
    return await _debtDS.createDebtGroup(name, customerNames);
  }

  /// Update grup
  Future<void> updateDebtGroup(String groupId, String name, List<String> customerNames) async {
    await _debtDS.updateDebtGroup(groupId, name, customerNames);
  }

  /// Hapus grup
  Future<void> deleteDebtGroup(String groupId) async {
    await _debtDS.deleteDebtGroup(groupId);
  }

  /// Ambil semua grup mentah dari Firestore
  Future<List<Map<String, dynamic>>> getAllDebtGroups() async {
    return await _debtDS.getAllDebtGroups();
  }

  /// Ambil semua customer_name yang sudah masuk grup
  Future<Set<String>> getGroupedCustomerNames() async {
    return await _debtDS.getGroupedCustomerNames();
  }

  /// Hitung summary untuk setiap grup (total hutang, profit, jumlah pelanggan, jumlah nota)
  Future<List<Map<String, dynamic>>> getGroupSummaries() async {
    final groups = await _debtDS.getAllDebtGroups();
    final allDebts = await _debtDS.getActiveDebtsWithDetails();

    List<Map<String, dynamic>> summaries = [];

    for (var group in groups) {
      List<dynamic> memberNames = group['customer_names'] ?? [];
      Set<String> memberSet = memberNames.map((e) => e.toString()).toSet();

      int totalHutang = 0;
      int totalDicicil = 0;
      int totalProfit = 0;
      int notaCount = 0;
      Set<String> uniqueCustomers = {};

      for (var debt in allDebts) {
        String rawName = debt['customer_name'] ?? 'Pelanggan Umum';
        String customerKey = rawName.split(' - ').first.split('\n').first.trim();
        if (customerKey.isEmpty) customerKey = 'Pelanggan Umum';

        if (memberSet.contains(customerKey)) {
          int tp = (debt['total_price'] as num?)?.toInt() ?? 0;
          int dc = (debt['total_dicicil'] as num?)?.toInt() ?? 0;
          int profit = (debt['potential_profit'] as num?)?.toInt() ?? 0;
          totalHutang += tp;
          totalDicicil += dc;
          totalProfit += profit;
          notaCount++;
          uniqueCustomers.add(customerKey);
        }
      }

      summaries.add({
        'id': group['id'],
        'group_name': group['group_name'],
        'customer_names': memberNames,
        'total_hutang': totalHutang,
        'total_dicicil': totalDicicil,
        'sisa_hutang': totalHutang - totalDicicil,
        'potential_profit': totalProfit,
        'nota_count': notaCount,
        'customer_count': uniqueCustomers.length,
      });
    }

    return summaries;
  }

  /// Ambil data hutang yang difilter hanya pelanggan UNGROUPED
  Future<Map<String, dynamic>> getUngroupedDebtSummary() async {
    final groupedNames = await _debtDS.getGroupedCustomerNames();
    final allGrouped = await _debtDS.getActiveDebtsGroupedByCustomer();

    // Filter hanya pelanggan yang TIDAK ada di grup manapun
    List<Map<String, dynamic>> ungrouped = allGrouped.where((g) {
      String name = g['customer_name'] ?? '';
      return !groupedNames.contains(name);
    }).toList();

    int totalSisa = 0;
    int totalProfit = 0;
    for (var g in ungrouped) {
      totalSisa += (g['sisa_hutang'] as int);
      totalProfit += (g['potential_profit'] as int);
    }

    return {
      'groups': ungrouped,
      'total_sisa': totalSisa,
      'total_potential_profit': totalProfit,
    };
  }

  /// Ambil data hutang difilter per grup tertentu (untuk layar detail grup)
  Future<Map<String, dynamic>> getDebtSummaryForGroup(List<String> customerNames) async {
    final allGrouped = await _debtDS.getActiveDebtsGroupedByCustomer();
    Set<String> nameSet = customerNames.map((e) => e.toString()).toSet();

    List<Map<String, dynamic>> filtered = allGrouped.where((g) {
      String name = g['customer_name'] ?? '';
      return nameSet.contains(name);
    }).toList();

    int totalSisa = 0;
    int totalProfit = 0;
    for (var g in filtered) {
      totalSisa += (g['sisa_hutang'] as int);
      totalProfit += (g['potential_profit'] as int);
    }

    return {
      'groups': filtered,
      'total_sisa': totalSisa,
      'total_potential_profit': totalProfit,
    };
  }

  /// Lunasi semua hutang dalam grup tertentu
  Future<void> payAllDebtsInGroup(List<String> customerNames, DateTime paymentDate) async {
    await _debtDS.payAllDebtsForCustomers(customerNames, paymentDate);
  }
}