import 'package:intl/intl.dart';
import '../data/datasources/firebase/transaction_history_firebase_datasource.dart';

class CapitalHistoryController {
  final TransactionHistoryFirebaseDataSource _transDS = TransactionHistoryFirebaseDataSource();

  Future<Map<String, dynamic>> getCapitalHistory(String filterDate) async {
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
    } else if (filterDate == 'Semua') {
      startDate = '2000-01-01'; 
    } else {
      startDate = '2000-01-01'; 
    }

    return await _transDS.getCapitalTransactionHistory(
      startDate: startDate, 
      endDate: endDate
    );
  }
}
