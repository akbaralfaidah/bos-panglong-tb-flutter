import '../data/datasources/firebase/history_firebase_datasource.dart';
import '../screens/history_screen.dart';

class HistoryController {
  // 🔥 KONEKSI MURNI KE FIREBASE (Selamat tinggal SQLite!)
  final HistoryFirebaseDataSource _historyDS = HistoryFirebaseDataSource();

  // 1. Logika Khusus Piutang (Sekarang Mendukung Filter Tanggal)
  Future<Map<String, dynamic>> loadPiutangData(String startDate, String endDate) async {
    final res = await _historyDS.loadPiutangData();

    // Urutkan Piutang dari yang terbaru ke terlama
    List<Map<String, dynamic>> unpaid = List<Map<String, dynamic>>.from(res['unpaid']);
    List<Map<String, dynamic>> paid = List<Map<String, dynamic>>.from(res['paid']);

    // Filter berdasarkan rentang tanggal
    if (startDate != '2000-01-01') {
      unpaid = unpaid.where((item) {
        String d = (item['transaction_date'] as String).substring(0, 10);
        return d.compareTo(startDate) >= 0 && d.compareTo(endDate) <= 0;
      }).toList();

      paid = paid.where((item) {
        String d = (item['transaction_date'] as String).substring(0, 10);
        return d.compareTo(startDate) >= 0 && d.compareTo(endDate) <= 0;
      }).toList();
    }

    unpaid.sort(
      (a, b) => (b['transaction_date'] as String).compareTo(a['transaction_date'] as String),
    );
    paid.sort(
      (a, b) => (b['transaction_date'] as String).compareTo(a['transaction_date'] as String),
    );

    // Hitung ulang total piutang yang belum lunas pada rentang tanggal tersebut
    double totalFilteredUnpaid = unpaid.fold(0.0, (sum, item) {
      double tPrice = (item['total_price'] as num).toDouble();
      double tPaid = item['total_paid'] != null ? (item['total_paid'] as num).toDouble() : 0.0;
      return sum + (tPrice - tPaid);
    });

    return {'unpaid': unpaid, 'paid': paid, 'total': totalFilteredUnpaid};
  }

  // 2. Logika History Umum (Omset, Stok, Barang Terjual, Bensin)
  Future<Map<String, dynamic>> loadGeneralHistory(
    HistoryType type,
    String startDate,
    String endDate,
  ) async {
    Map<String, dynamic> result;

    // Arahkan ke mesin yang tepat sesuai tipe layarnya
    if (type == HistoryType.stock) {
      result = await _historyDS.loadStockHistory(startDate, endDate);
    } else if (type == HistoryType.soldItems) {
      result = await _historyDS.loadSoldItemsHistory(startDate, endDate);
    } else if (type == HistoryType.bensin) {
      result = await _historyDS.loadBensinHistory(startDate, endDate);
    } else {
      // History Transaksi Umum (Omset)
      result = await _historyDS.loadTransactionsHistory(startDate, endDate);
    }

    // Urutkan semua data dari yang paling baru ke paling lama
    List<Map<String, dynamic>> sortedData = List<Map<String, dynamic>>.from(
      result['data'],
    );
    sortedData.sort((a, b) {
      // Stok masuk pakai key 'date', sisanya pakai 'transaction_date'
      String dateKey = (type == HistoryType.stock) ? 'date' : 'transaction_date';
      return (b[dateKey] as String).compareTo(a[dateKey] as String);
    });

    return {'data': sortedData, 'total': result['total']};
  }
}