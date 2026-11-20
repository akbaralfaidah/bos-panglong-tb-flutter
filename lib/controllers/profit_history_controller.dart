import 'package:intl/intl.dart';
import '../data/datasources/firebase/profit_firebase_datasource.dart';

class ProfitHistoryController {
  final ProfitFirebaseDataSource _profitDS = ProfitFirebaseDataSource();

  // 🔥 JEMBATAN BUAT NARIK PROFIT DARI UI GUDANG 🔥
  Future<void> withdrawProfitForCapital(int amount, String note) async {
    await _profitDS.withdrawProfitForCapital(amount, note);
  }

  ({String startDate, String endDate}) _resolveDateRange(String filterDate) {
    DateTime now = DateTime.now();
    String startDate = '';
    String endDate = DateFormat('yyyy-MM-dd').format(now);

    if (filterDate.startsWith('CUSTOM|')) {
      var parts = filterDate.split('|');
      startDate = parts[1];
      endDate = parts[2];
    } else if (filterDate == 'Hari Ini') {
      startDate = endDate;
    } else if (filterDate == 'Kemarin') {
      startDate = DateFormat('yyyy-MM-dd').format(now.subtract(const Duration(days: 1)));
      endDate = startDate;
    } else if (filterDate == '7 Hari') {
      startDate = DateFormat('yyyy-MM-dd').format(now.subtract(const Duration(days: 7)));
    } else if (filterDate == 'Bulan Ini') {
      startDate = DateFormat('yyyy-MM-01').format(now);
    } else {
      startDate = '2000-01-01'; // Default: Semua
    }
    return (startDate: startDate, endDate: endDate);
  }

  /// Stream REAL-TIME untuk filter rentang tanggal (non-'Semua').
  /// Mengembalikan `null` untuk mode 'Semua' agar tetap memakai query cepat 1x.
  Stream<Map<String, dynamic>>? watchProfitAndExpenses(String filterDate) {
    if (filterDate == 'Semua') return null;
    final range = _resolveDateRange(filterDate);
    return _profitDS.watchProfitAndExpensesData(range.startDate, range.endDate);
  }

  Future<Map<String, dynamic>> getProfitAndExpenses(String filterDate) async {
    final range = _resolveDateRange(filterDate);
    return await _profitDS.getProfitAndExpensesData(range.startDate, range.endDate);
  }
}