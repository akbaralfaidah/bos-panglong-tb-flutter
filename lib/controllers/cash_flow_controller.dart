import 'package:intl/intl.dart';
import '../data/datasources/firebase/cash_flow_firebase_datasource.dart';

class CashFlowItem {
  final String id;
  final String date;
  final String title;
  final String subtitle;
  final int amount;
  final String type; // 'IN', 'OUT', atau 'PENDING'
  final String category; // 'SALE', 'DEBT', 'STOCK_NEW', 'STOCK_ADD', 'GAS', 'GAS_TRX'
  final Map<String, dynamic> rawData; // Payload rahasia untuk buka nota!

  CashFlowItem({
    required this.id,
    required this.date,
    required this.title,
    required this.subtitle,
    required this.amount,
    required this.type,
    required this.category,
    required this.rawData,
  });
}

class CashFlowController {
  final CashFlowFirebaseDataSource _cashFlowDS = CashFlowFirebaseDataSource();

  /// Menghitung rentang ISO `startIso` & `endIso` berdasarkan mode filter UI,
  /// sehingga Firestore hanya menarik dokumen pada tanggal yang benar-benar diminta
  /// (bukan mengunduh seluruh ribuan riwayat setiap kali halaman dibuka!).
  static ({String? startIso, String? endIso, bool isAllTime}) resolveDateRange(
    String filterMode, {
    DateTime? nowOverride,
  }) {
    final DateTime now = nowOverride ?? DateTime.now();
    final DateFormat iso = DateFormat('yyyy-MM-dd');
    final String todayStr = iso.format(now);

    if (filterMode == 'Hari Ini') {
      return (
        startIso: '${todayStr}T00:00:00.000',
        endIso: '${todayStr}T23:59:59.999',
        isAllTime: false,
      );
    }
    if (filterMode == 'Kemarin') {
      final String y = iso.format(now.subtract(const Duration(days: 1)));
      return (
        startIso: '${y}T00:00:00.000',
        endIso: '${y}T23:59:59.999',
        isAllTime: false,
      );
    }
    if (filterMode == '7 Hari') {
      final String s = iso.format(now.subtract(const Duration(days: 7)));
      return (
        startIso: '${s}T00:00:00.000',
        endIso: '${todayStr}T23:59:59.999',
        isAllTime: false,
      );
    }
    if (filterMode == 'Bulan Ini') {
      final String s = DateFormat('yyyy-MM-01').format(now);
      return (
        startIso: '${s}T00:00:00.000',
        endIso: '${todayStr}T23:59:59.999',
        isAllTime: false,
      );
    }
    if (filterMode.startsWith('CUSTOM|')) {
      final parts = filterMode.split('|');
      if (parts.length >= 3) {
        return (
          startIso: '${parts[1]}T00:00:00.000',
          endIso: '${parts[2]}T23:59:59.999',
          isAllTime: false,
        );
      }
    }
    return (startIso: null, endIso: null, isAllTime: true);
  }

  List<CashFlowItem> _buildItems({
    required List<Map<String, dynamic>> trans,
    required List<Map<String, dynamic>> debts,
    required List<Map<String, dynamic>> stocks,
    required List<Map<String, dynamic>> gas,
  }) {
    final List<CashFlowItem> items = [];

    // 1. PENJUALAN KASIR
    for (var t in trans) {
      final String dateStr = (t['transaction_date'] ?? '').toString();
      if (dateStr.isEmpty) continue;
      final int totalPrice = (t['total_price'] as num?)?.toInt() ?? 0;
      final int opCost = (t['operational_cost'] as num?)?.toInt() ?? 0;

      if (t['payment_status'] == 'Lunas') {
        items.add(CashFlowItem(
          id: 'TRX-${t['id']}',
          date: dateStr,
          title: 'Penjualan Lunas (INV-${t['id']})',
          subtitle: 'Kpd: ${t['customer_name'] ?? 'Pelanggan Umum'}',
          amount: totalPrice,
          type: 'IN',
          category: 'SALE',
          rawData: t,
        ));
      } else {
        items.add(CashFlowItem(
          id: 'TRX-${t['id']}',
          date: dateStr,
          title: 'Penjualan Hutang (INV-${t['id']})',
          subtitle:
              'Kpd: ${t['customer_name'] ?? 'Pelanggan Umum'} (Belum Lunas)',
          amount: totalPrice,
          type: 'PENDING',
          category: 'SALE',
          rawData: t,
        ));
      }

      // 2. BIAYA BENSIN DARI PENJUALAN
      if (opCost > 0) {
        items.add(CashFlowItem(
          id: 'OP-${t['id']}',
          date: dateStr,
          title: 'Biaya Bensin (INV-${t['id']})',
          subtitle: 'Potongan Operasional Pengiriman',
          amount: opCost,
          type: 'OUT',
          category: 'GAS_TRX',
          rawData: t,
        ));
      }
    }

    // 3. PEMBAYARAN CICILAN PIUTANG
    for (var d in debts) {
      final String dateStr = (d['payment_date'] ?? '').toString();
      if (dateStr.isEmpty) continue;
      final String note = (d['note'] ?? '').toString().trim();
      items.add(CashFlowItem(
        id: 'DBT-${d['id']}',
        date: dateStr,
        title: 'Terima Cicilan (INV-${d['transaction_id']})',
        subtitle: 'Catatan: ${note.isEmpty ? '-' : note}',
        amount: (d['amount_paid'] as num?)?.toInt() ?? 0,
        type: 'IN',
        category: 'DEBT',
        rawData: d,
      ));
    }

    // 4. KULAKAN (STOK BARANG MASUK / PRODUK BARU)
    for (var s in stocks) {
      final String dateStr = (s['date'] ?? '').toString();
      if (dateStr.isEmpty) continue;
      final int totalModalKeluar =
          s.containsKey('total_price') && s['total_price'] != null
              ? (s['total_price'] as num).toInt()
              : (((s['price'] as num?)?.toDouble() ?? 0) *
                      ((s['quantity'] as num?)?.toDouble() ?? 1.0))
                  .round();

      final String logType = (s['type']?.toString() ?? '').toUpperCase();
      final String category =
          (logType.contains('BARU') || logType.contains('AWAL'))
              ? 'STOCK_NEW'
              : 'STOCK_ADD';

      if (totalModalKeluar > 0) {
        final String note = (s['note'] ?? '').toString().trim();
        items.add(CashFlowItem(
          id: 'STK-${s['id']}',
          date: dateStr,
          title: category == 'STOCK_NEW'
              ? 'Produk Baru: ${s['product_name'] ?? 'Produk'}'
              : 'Stok Masuk: ${s['product_name'] ?? 'Produk'}',
          subtitle: 'Sumber/Catatan: ${note.isEmpty ? 'Modal Gudang' : note}',
          amount: totalModalKeluar,
          type: 'OUT',
          category: category,
          rawData: s,
        ));
      }
    }

    // 5. BENSIN MANUAL / PENGELUARAN LAINNYA
    for (var g in gas) {
      final String dateStr = (g['date'] ?? '').toString();
      if (dateStr.isEmpty) continue;
      items.add(CashFlowItem(
        id: 'GAS-${g['id']}',
        date: dateStr,
        title: 'Biaya Bensin / Opr',
        subtitle: g['description']?.toString() ?? 'Pengeluaran Kendaraan',
        amount: (g['amount'] as num?)?.toInt() ?? 0,
        type: 'OUT',
        category: 'GAS',
        rawData: g,
      ));
    }

    items.sort((a, b) => b.date.compareTo(a.date));
    return items;
  }

  /// Stream REAL-TIME untuk filter harian/mingguan/bulanan/custom.
  /// Mengembalikan `null` hanya pada mode `'Semua'` (ribuan dokumen lama tetap pakai 1x cache-first).
  Stream<List<CashFlowItem>>? watchSuperHistory({
    String filterMode = 'Hari Ini',
  }) {
    final range = resolveDateRange(filterMode);
    if (range.isAllTime || range.startIso == null || range.endIso == null) {
      return null;
    }
    return _cashFlowDS
        .watchDateRangeData(
          startIso: range.startIso!,
          endIso: range.endIso!,
        )
        .map(
          (bundle) => _buildItems(
            trans: bundle.transactions,
            debts: bundle.debtPayments,
            stocks: bundle.stockLogs,
            gas: bundle.gasExpenses,
          ),
        );
  }

  Future<List<CashFlowItem>> getSuperHistory({
    String filterMode = 'Hari Ini',
  }) async {
    final range = resolveDateRange(filterMode);
    final bool preferServer = !range.isAllTime;

    // Eksekusi 4 koleksi secara PARALEL (bukan berurutan) & dibatasi rentang tanggal aktif
    final results = await Future.wait([
      _cashFlowDS.getAllTransactions(
        startIso: range.startIso,
        endIso: range.endIso,
        preferServer: preferServer,
      ),
      _cashFlowDS.getAllDebtPayments(
        startIso: range.startIso,
        endIso: range.endIso,
        preferServer: preferServer,
      ),
      _cashFlowDS.getAllStockLogsWithProducts(
        startIso: range.startIso,
        endIso: range.endIso,
        preferServer: preferServer,
      ),
      _cashFlowDS.getAllGasExpenses(
        startIso: range.startIso,
        endIso: range.endIso,
        preferServer: preferServer,
      ),
    ]);

    return _buildItems(
      trans: results[0],
      debts: results[1],
      stocks: results[2],
      gas: results[3],
    );
  }

  Future<Map<String, dynamic>?> getTransactionById(int id) async {
    return await _cashFlowDS.getTransactionById(id);
  }
}
