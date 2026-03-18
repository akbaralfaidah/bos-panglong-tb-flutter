import '../data/datasources/local/transaction_local_datasource.dart';
import '../data/datasources/local/debt_local_datasource.dart';
import '../data/datasources/local/core_local_datasource.dart';
import '../helpers/database_helper.dart'; // Panggil DB Helper buat raw query

class TransactionDetailController {
  final TransactionLocalDataSource _transDS = TransactionLocalDataSource();
  final DebtLocalDataSource _debtDS = DebtLocalDataSource();
  final CoreLocalDataSource _coreDS = CoreLocalDataSource();

  Future<Map<String, dynamic>> loadDetailData(int transId, String dateStr) async {
    final items = await _transDS.getTransactionItems(transId);
    final payments = await _debtDS.getDebtPayments(transId);
    final storeName = await _coreDS.getSetting('store_name') ?? "Bos Panglong & TB";
    final storeAddress = await _coreDS.getSetting('store_address') ?? "Alamat belum diatur";
    final storePhone = await _coreDS.getSetting('store_phone') ?? ""; 
    final logoPath = await _coreDS.getSetting('store_logo');

    // LOGIKA NOMOR URUT TRANSAKSI HARI INI
    final db = await DatabaseHelper.instance.database;
    final dateOnly = dateStr.split(' ')[0]; // Ambil YYYY-MM-DD
    final countQuery = await db.rawQuery('''
      SELECT COUNT(*) as queue_num FROM transactions 
      WHERE date(transaction_date) = ? AND id <= ?
    ''', [dateOnly, transId]);
    int queueNum = (countQuery.first['queue_num'] as int?) ?? 1;

    return {
      'items': items,
      'payments': payments,
      'storeName': storeName,
      'storeAddress': storeAddress,
      'storePhone': storePhone,
      'logoPath': logoPath,
      'queueNum': queueNum, // Masukin nomor urut
    };
  }

  Future<void> payDebt(int transId, int amount, String note) async {
    await _debtDS.addDebtPayment(transId, amount, note);
  }
}