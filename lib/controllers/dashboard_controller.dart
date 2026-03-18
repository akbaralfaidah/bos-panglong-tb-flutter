import 'package:intl/intl.dart';
import '../helpers/database_helper.dart';

class DashboardStats {
  final int omsetKotor;
  final int profitBersih;
  final int uangBensin;
  final int totalPiutang;
  final int totalBeliStok;
  final int kayuTerjual;
  final int bangunanTerjual;

  DashboardStats({
    required this.omsetKotor, required this.profitBersih, required this.uangBensin,
    required this.totalPiutang, required this.totalBeliStok,
    required this.kayuTerjual, required this.bangunanTerjual,
  });
}

class DashboardController {
  
  Future<DashboardStats> getTodayStats() async {
    try {
      final db = await DatabaseHelper.instance.database;
      String today = DateFormat('yyyy-MM-dd').format(DateTime.now());

      // 1. OMSET HARI INI (Total Tagihan Transaksi Lunas)
      var resOmset = await db.rawQuery('''
        SELECT SUM(total_price) as omset 
        FROM transactions 
        WHERE substr(transaction_date, 1, 10) = ? AND payment_status = 'Lunas'
      ''', [today]);
      double omsetKotor = _safeDouble(resOmset.first['omset']);

      // 2. PROFIT HARI INI (Margin Barang DIKURANGI Diskon)
      var resProfit = await db.rawQuery('''
        SELECT SUM((ti.sell_price - ti.capital_price) * ti.quantity) as profit
        FROM transaction_items ti
        JOIN transactions t ON ti.transaction_id = t.id
        WHERE substr(t.transaction_date, 1, 10) = ? AND t.payment_status = 'Lunas'
      ''', [today]);
      double profitKotorBarang = _safeDouble(resProfit.first['profit']);

      var resDiskon = await db.rawQuery('''
        SELECT SUM(discount) as diskon 
        FROM transactions 
        WHERE substr(transaction_date, 1, 10) = ? AND payment_status = 'Lunas'
      ''', [today]);
      double totalDiskon = _safeDouble(resDiskon.first['diskon']);

      double profitBersih = profitKotorBarang - totalDiskon;

      // 3. UANG BENSIN HARIAN (Pemasukan Customer - Pengeluaran SPBU)
      var resBensinMasuk = await db.rawQuery('''
        SELECT SUM(operational_cost) as bensin_masuk 
        FROM transactions 
        WHERE substr(transaction_date, 1, 10) = ?
      ''', [today]);
      var resBensinKeluar = await db.rawQuery('''
        SELECT SUM(amount) as bensin_keluar 
        FROM gas_expenses 
        WHERE substr(date, 1, 10) = ?
      ''', [today]);
      double bensinHarian = _safeDouble(resBensinMasuk.first['bensin_masuk']) - _safeDouble(resBensinKeluar.first['bensin_keluar']);

      // ==========================================================
      // 4. TOTAL PIUTANG (FIX FATAL: Sisa Hutang Berjalan Asli)
      // ==========================================================
      var resPiutang = await db.rawQuery('''
        SELECT SUM(t.total_price - IFNULL(dp.total_paid, 0)) as sisa_hutang
        FROM transactions t
        LEFT JOIN (
          SELECT transaction_id, SUM(amount_paid) as total_paid
          FROM debt_payments
          GROUP BY transaction_id
        ) dp ON t.id = dp.transaction_id
        WHERE t.payment_status != 'Lunas'
      ''');
      double totalPiutang = _safeDouble(resPiutang.first['sisa_hutang']);

      // 5. STOK MASUK HARI INI (Pengeluaran Modal Beli Stok)
      double totalBeliStok = 0;
      try {
        var resStok = await db.rawQuery('''
          SELECT SUM(quantity * price) as modal 
          FROM stock_logs 
          WHERE substr(date, 1, 10) = ?
        ''', [today]);
        totalBeliStok = _safeDouble(resStok.first['modal']);
      } catch (e) {
        var resStokOld = await db.rawQuery('''
          SELECT SUM(quantity_added * capital_price) as modal 
          FROM stock_logs 
          WHERE substr(date, 1, 10) = ?
        ''', [today]);
        totalBeliStok = _safeDouble(resStokOld.first['modal']);
      }

      return DashboardStats(
        omsetKotor: omsetKotor.round(),
        profitBersih: profitBersih.round(), 
        uangBensin: bensinHarian.round(),
        totalPiutang: totalPiutang.round(), // <-- SEKARANG ANTI MINUS
        totalBeliStok: totalBeliStok.round(),
        kayuTerjual: 0,
        bangunanTerjual: 0,
      );
      
    } catch (e) {
      print("CRITICAL DASHBOARD ERROR: $e");
      return DashboardStats(omsetKotor: 0, profitBersih: 0, uangBensin: 0, totalPiutang: 0, totalBeliStok: 0, kayuTerjual: 0, bangunanTerjual: 0);
    }
  }

  double _safeDouble(dynamic val) {
    if (val == null) return 0.0;
    if (val is num) return val.toDouble();
    return double.tryParse(val.toString()) ?? 0.0;
  }
}