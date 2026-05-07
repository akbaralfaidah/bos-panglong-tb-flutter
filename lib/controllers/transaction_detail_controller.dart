import '../data/datasources/firebase/transaction_firebase_datasource.dart';
import '../data/datasources/firebase/core_firebase_datasource.dart';

class TransactionDetailController {
  final TransactionFirebaseDataSource _transDS =
      TransactionFirebaseDataSource();
  final CoreFirebaseDataSource _coreDS = CoreFirebaseDataSource();

  Future<Map<String, dynamic>> loadDetailData(
    int transId,
    String dateStr,
  ) async {
    final transData = await _transDS.getTransactionById(transId);

    // Konversi Tipe Data Paksa biar UI lu gak meledak
    List<Map<String, dynamic>> itemsList = [];
    int queueNum = 1;

    if (transData != null && transData['items'] != null) {
      itemsList = List<Map<String, dynamic>>.from(
        transData['items'].map((item) => Map<String, dynamic>.from(item)),
      );
      queueNum = transData['queue_number'] ?? 1;
    }

    final paymentsRaw = await _transDS.getDebtPayments(transId);
    List<Map<String, dynamic>> paymentsList = List<Map<String, dynamic>>.from(
      paymentsRaw,
    );

    final storeName =
        await _coreDS.getSetting('store_name') ?? "Bos Depot & TB";
    final storeAddress =
        await _coreDS.getSetting('store_address') ?? "Alamat belum diatur";
    final storePhone = await _coreDS.getSetting('store_phone') ?? "";
    final logoPath = await _coreDS.getSetting('store_logo');

    return {
      'items': itemsList,
      'payments': paymentsList,
      'storeName': storeName,
      'storeAddress': storeAddress,
      'storePhone': storePhone,
      'logoPath': logoPath,
      'queueNum': queueNum,
    };
  }

  // FUNGSI BARU: Dijahit biar UI bisa manggil fitur bayar cicilan
  Future<void> payDebt(int transId, int amount, String note) async {
    await _transDS.payDebt(transId, amount, note);
  }

  // 🔥 JEMBATAN VOID TRANSAKSI 🔥
  Future<void> voidTransaction(
    int transId,
    List<Map<String, dynamic>> items,
  ) async {
    await _transDS.voidTransaction(transId, items);
  }
}
