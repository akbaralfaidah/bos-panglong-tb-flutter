import 'package:intl/intl.dart';
import '../data/datasources/firebase/stock_history_firebase_datasource.dart';
import '../data/datasources/firebase/product_firebase_datasource.dart';

class StockHistoryController {
  final StockHistoryFirebaseDataSource _stockHistoryDS = StockHistoryFirebaseDataSource();
  
  Future<List<Map<String, dynamic>>> getStockHistory(String tabType, String filterDate) async {
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
      startDate = '2000-01-01'; 
    }

    return await _stockHistoryDS.getStockHistoryData(tabType, startDate, endDate);
  }

  Future<List<Map<String, dynamic>>> getStockLogsByExactDate(String exactDate) async {
    return await _stockHistoryDS.getStockLogsByExactDate(exactDate);
  }

  Future<void> deleteStockItem(int logId) async {
    await ProductFirebaseDataSource().deleteStockItem(logId);
  }

  Future<void> updateStockItemQuantity(int logId, double newQty, int newPrice) async {
    await ProductFirebaseDataSource().updateStockItemQuantity(logId, newQty, newPrice);
  }
}