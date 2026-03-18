import 'package:intl/intl.dart';
import '../data/datasources/local/transaction_local_datasource.dart';

class TransactionHistoryController {
  final TransactionLocalDataSource _transDS = TransactionLocalDataSource();

  Future<List<Map<String, dynamic>>> getTransactions(String tabType, String filterDate) async {
    DateTime now = DateTime.now();
    String startDate = '';
    String endDate = DateFormat('yyyy-MM-dd').format(now);

    // Logika filter tanggal lu tetap utuh!
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

    String statusCondition = tabType == 'LUNAS' ? "payment_status = 'Lunas'" : "payment_status != 'Lunas'";

    // Controller bersih! Tinggal suruh Datasource yang kerja
    return await _transDS.getFilteredTransactionHistory(
      statusCondition: statusCondition, 
      startDate: startDate, 
      endDate: endDate
    );
  }
}