import 'package:intl/intl.dart';
import '../data/datasources/local/stock_history_local_datasource.dart';

class StockHistoryController {
  final StockHistoryLocalDataSource _stockHistoryDS = StockHistoryLocalDataSource();
  
  Future<List<Map<String, dynamic>>> getStockHistory(String tabType, String filterDate) async {
    DateTime now = DateTime.now();
    String startDate = '';
    String endDate = DateFormat('yyyy-MM-dd').format(now);

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

    String typeCondition = "p.type IN ('KAYU', 'RENG', 'BULAT')";
    if (tabType == 'BANGUNAN') {
      typeCondition = "p.type = 'BANGUNAN'";
    }

    return await _stockHistoryDS.getStockHistoryData(typeCondition, startDate, endDate);
  }

  Future<List<Map<String, dynamic>>> getStockLogsByExactDate(String exactDate) async {
    return await _stockHistoryDS.getStockLogsByExactDate(exactDate);
  }
}