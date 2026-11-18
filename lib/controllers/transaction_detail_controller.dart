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
    List<Map<String, dynamic>> deliveryLogsList = [];
    String deliveryStatus = 'Selesai';
    int queueNum = 1;

    if (transData != null) {
      if (transData['items'] != null) {
        itemsList = List<Map<String, dynamic>>.from(
          transData['items'].map((item) => Map<String, dynamic>.from(item)),
        );
      }
      if (transData['delivery_logs'] != null && transData['delivery_logs'] is List) {
        deliveryLogsList = List<Map<String, dynamic>>.from(
          (transData['delivery_logs'] as List).map((log) => Map<String, dynamic>.from(log as Map)),
        );
      }
      deliveryStatus = transData['delivery_status']?.toString() ?? 'Selesai';
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
      'delivery_status': deliveryStatus,
      'delivery_logs': deliveryLogsList,
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

  // 🔥 UPDATE PENGIRIMAN / PENGAMBILAN BARANG TITIPAN 🔥
  Future<Map<String, dynamic>> updateDeliveryProgress({
    required int transId,
    required List<Map<String, dynamic>> updatedItems,
    required List<Map<String, dynamic>> newlyDeliveredSummary,
    String note = '',
  }) async {
    return await _transDS.updateDeliveryProgress(
      transId: transId,
      updatedItems: updatedItems,
      newlyDeliveredSummary: newlyDeliveredSummary,
      note: note,
    );
  }

  // 🔥 JEMBATAN VOID TRANSAKSI 🔥
  Future<void> voidTransaction(
    int transId,
    List<Map<String, dynamic>> items,
  ) async {
    await _transDS.voidTransaction(transId, items);
  }
}
