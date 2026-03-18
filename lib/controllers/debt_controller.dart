import '../data/datasources/local/debt_local_datasource.dart';

class DebtController {
  final DebtLocalDataSource _debtDS = DebtLocalDataSource();

  // Memisahkan logika perhitungan dari UI
  Future<Map<String, dynamic>> getDebtSummary() async {
    final result = await _debtDS.getActiveDebtsWithDetails();

    int totalSisaPiutang = 0;
    List<Map<String, dynamic>> processedDebts = [];

    for (var row in result) {
      int totalPrice = (row['total_price'] as int?) ?? 0;
      int discount = (row['discount'] as int?) ?? 0;
      int dicicil = (row['total_dicicil'] as int?) ?? 0;

      // Logika lu aman di sini bro!
      int sisa = (totalPrice - discount) - dicicil;
      totalSisaPiutang += sisa;

      // Kita bikin map baru yang udah include sisa hutang biar UI tinggal pakai
      Map<String, dynamic> debtItem = Map<String, dynamic>.from(row);
      debtItem['sisa_hutang'] = sisa;
      processedDebts.add(debtItem);
    }

    return {
      'debts': processedDebts,
      'total_sisa': totalSisaPiutang,
    };
  }
}