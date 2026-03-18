import 'package:intl/intl.dart';
import '../data/datasources/local/dashboard_local_datasource.dart';

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
  final DashboardLocalDataSource _dashboardDS = DashboardLocalDataSource();
  
  Future<DashboardStats> getTodayStats() async {
    try {
      String today = DateFormat('yyyy-MM-dd').format(DateTime.now());

      // Controller sekarang buta database, cuma tau minta data ke Datasource
      double omsetKotor = await _dashboardDS.getTodayOmset(today);
      
      double profitKotorBarang = await _dashboardDS.getTodayGrossProfit(today);
      double totalDiskon = await _dashboardDS.getTodayDiscount(today);
      double profitBersih = profitKotorBarang - totalDiskon;

      double bensinMasuk = await _dashboardDS.getTodayGasIncome(today);
      double bensinKeluar = await _dashboardDS.getTodayGasExpense(today);
      double totalBensin = await _dashboardDS.getTotalGasBalance();

      double totalPiutang = await _dashboardDS.getTotalDebt();
      double totalBeliStok = await _dashboardDS.getTodayStockExpense(today);

      return DashboardStats(
        omsetKotor: omsetKotor.round(),
        profitBersih: profitBersih.round(), 
        uangBensin: totalBensin.round(),
        totalPiutang: totalPiutang.round(), 
        totalBeliStok: totalBeliStok.round(),
        kayuTerjual: 0, // Sesuai dengan code asli lu
        bangunanTerjual: 0,
      );
      
    } catch (e) {
      print("CRITICAL DASHBOARD ERROR: $e");
      return DashboardStats(omsetKotor: 0, profitBersih: 0, uangBensin: 0, totalPiutang: 0, totalBeliStok: 0, kayuTerjual: 0, bangunanTerjual: 0);
    }
  }
}