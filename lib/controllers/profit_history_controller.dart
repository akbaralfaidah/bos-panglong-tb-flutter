import 'package:intl/intl.dart';
import '../data/datasources/local/profit_local_datasource.dart';

class ProfitHistoryController {
  final ProfitLocalDataSource _profitDS = ProfitLocalDataSource();

  Future<List<Map<String, dynamic>>> getProfitAndExpenses(String filterDate) async {
    DateTime now = DateTime.now();
    String startDate = '';
    String endDate = DateFormat('yyyy-MM-dd').format(now);

    // Logika filter tanggal lu tetap aman di sini
    if (filterDate == 'Hari Ini') {
      startDate = endDate;
    } else if (filterDate == 'Kemarin') {
      startDate = DateFormat('yyyy-MM-dd').format(now.subtract(const Duration(days: 1)));
      endDate = startDate;
    } else if (filterDate == '7 Hari') {
      startDate = DateFormat('yyyy-MM-dd').format(now.subtract(const Duration(days: 7)));
    } else if (filterDate == 'Bulan Ini') {
      startDate = DateFormat('yyyy-MM-01').format(now);
    } else {
      startDate = '2000-01-01'; 
    }

    // Panggil dari Datasource, Controller bersih dari SQL!
    return await _profitDS.getProfitAndExpensesData(startDate, endDate);
  }
}