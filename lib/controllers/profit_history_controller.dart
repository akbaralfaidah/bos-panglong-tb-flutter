import 'package:intl/intl.dart';
import '../data/datasources/firebase/profit_firebase_datasource.dart';
import '../data/datasources/firebase/report_firebase_datasource.dart';

class ProfitHistoryController {
  final ProfitFirebaseDataSource _profitDS = ProfitFirebaseDataSource();

  // 🔥 JEMBATAN BUAT NARIK PROFIT DARI UI GUDANG 🔥
  Future<void> withdrawProfitForCapital(int amount, String note) async {
    await _profitDS.withdrawProfitForCapital(amount, note);
  }

  Future<Map<String, dynamic>> getProfitAndExpenses(String filterDate) async {
    DateTime now = DateTime.now();
    String startDate = '';
    String endDate = DateFormat('yyyy-MM-dd').format(now);

    // 🔥 LOGIKA FILTER CUSTOM DATE 🔥
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

    return await _profitDS.getProfitAndExpensesData(startDate, endDate);
  }
}