import 'package:intl/intl.dart';
import '../data/datasources/firebase/transaction_history_firebase_datasource.dart';

class TransactionHistoryController {
  final TransactionHistoryFirebaseDataSource _transDS =
      TransactionHistoryFirebaseDataSource();

  ({String startDate, String endDate, String statusCondition, bool isAllTime})
      _resolveParams(String tabType, String filterDate) {
    final DateTime now = DateTime.now();
    String startDate = '';
    String endDate = DateFormat('yyyy-MM-dd').format(now);

    if (filterDate.startsWith('CUSTOM|')) {
      final parts = filterDate.split('|');
      startDate = parts[1];
      endDate = parts[2];
    } else if (filterDate == 'Hari Ini') {
      startDate = endDate;
    } else if (filterDate == 'Kemarin') {
      startDate =
          DateFormat('yyyy-MM-dd').format(now.subtract(const Duration(days: 1)));
      endDate = startDate;
    } else if (filterDate == '7 Hari') {
      startDate =
          DateFormat('yyyy-MM-dd').format(now.subtract(const Duration(days: 7)));
    } else if (filterDate == 'Bulan Ini') {
      startDate = DateFormat('yyyy-MM-01').format(now);
    } else {
      startDate = '2000-01-01';
    }

    String statusCondition = 'HUTANG';
    if (tabType == 'LUNAS') {
      statusCondition = 'LUNAS';
    } else if (tabType == 'TITIPAN') {
      statusCondition = 'TITIPAN';
    }

    return (
      startDate: startDate,
      endDate: endDate,
      statusCondition: statusCondition,
      isAllTime: startDate == '2000-01-01',
    );
  }

  /// Stream REAL-TIME untuk filter harian/mingguan/bulanan/custom/titipan.
  Stream<Map<String, dynamic>>? watchTransactions(
    String tabType,
    String filterDate,
  ) {
    final p = _resolveParams(tabType, filterDate);
    if (p.isAllTime && p.statusCondition != 'TITIPAN') {
      return null; // Mode 'Semua' ribuan nota tetap pakai cache-first 1x agar ringan
    }
    return _transDS.watchFilteredTransactionHistory(
      statusCondition: p.statusCondition,
      startDate: p.startDate,
      endDate: p.endDate,
    );
  }

  Future<Map<String, dynamic>> getTransactions(
    String tabType,
    String filterDate,
  ) async {
    final p = _resolveParams(tabType, filterDate);
    return await _transDS.getFilteredTransactionHistory(
      statusCondition: p.statusCondition,
      startDate: p.startDate,
      endDate: p.endDate,
    );
  }
}