import '../data/datasources/local/transaction_local_datasource.dart';
import '../data/datasources/local/debt_local_datasource.dart';
import '../data/datasources/local/report_local_datasource.dart';
import '../screens/history_screen.dart'; // Import untuk akses enum HistoryType

class HistoryController {
  final TransactionLocalDataSource _transDS = TransactionLocalDataSource();
  final DebtLocalDataSource _debtDS = DebtLocalDataSource();
  final ReportLocalDataSource _reportDS = ReportLocalDataSource();

  // 1. Logika Khusus Piutang
  Future<Map<String, dynamic>> loadPiutangData() async {
    final rawResult = await _debtDS.getAllDebtHistory();

    List<Map<String, dynamic>> unpaid = [];
    List<Map<String, dynamic>> paid = [];
    double totalUnpaid = 0;

    for (var t in rawResult) {
      if (t['payment_status'] == 'Belum Lunas') {
        unpaid.add(t);
        totalUnpaid += (t['total_price'] as num).toDouble();
      } else {
        paid.add(t);
      }
    }

    return {'unpaid': unpaid, 'paid': paid, 'total': totalUnpaid};
  }

  // 2. Logika History Umum (Omset, Stok, Barang Terjual, Bensin)
  Future<Map<String, dynamic>> loadGeneralHistory(
    HistoryType type,
    String startDate,
    String endDate,
  ) async {
    List<Map<String, dynamic>> rawResult = [];
    double total = 0;

    if (type == HistoryType.stock) {
      rawResult = await _reportDS.getStockLogsDetail(
        startDate: startDate,
        endDate: endDate,
      );
      for (var item in rawResult)
        total += (item['quantity_added'] * item['capital_price']);
    } else if (type == HistoryType.soldItems) {
      rawResult = await _reportDS.getSoldItemsDetail(
        startDate: startDate,
        endDate: endDate,
      );
      for (var item in rawResult) total += (item['quantity'] as num).toDouble();
    } else if (type == HistoryType.bensin) {
      final allTrans = await _transDS.getTransactionHistory(
        startDate: startDate,
        endDate: endDate,
      );
      rawResult = allTrans
          .where((t) => (t['operational_cost'] as num) > 0)
          .toList();
      for (var t in rawResult)
        total += (t['operational_cost'] as num).toDouble();
    } else {
      // History Transaksi Umum (Omset)
      rawResult = await _transDS.getTransactionHistory(
        startDate: startDate,
        endDate: endDate,
      );
      for (var t in rawResult) {
        if (t['payment_status'] != 'Belum Lunas') {
          double grand = (t['total_price'] as num).toDouble();
          double bensin = (t['operational_cost'] as num).toDouble();
          total += (grand - bensin);
        }
      }
    }

    // Urutkan dari yang terbaru
    List<Map<String, dynamic>> sortedResult = List<Map<String, dynamic>>.from(
      rawResult,
    );
    sortedResult.sort((a, b) {
      DateTime dateA = DateTime.parse(
        type == HistoryType.stock ? a['date'] : a['transaction_date'],
      );
      DateTime dateB = DateTime.parse(
        type == HistoryType.stock ? b['date'] : b['transaction_date'],
      );
      return dateB.compareTo(dateA);
    });

    return {'data': sortedResult, 'total': total};
  }
}
