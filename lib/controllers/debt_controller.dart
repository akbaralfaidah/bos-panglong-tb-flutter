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
}